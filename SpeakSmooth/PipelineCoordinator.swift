import Foundation

@MainActor
final class PipelineCoordinator {
    let appState: AppState
    let settings: AppSettings

    private let audioCaptureManager: any AudioCapturing
    private var segmentBuilder: SegmentBuilder?
    private let transcriptionService: any Transcribing
    private let remindersManager: any ReminderStore
    private let requestMicPermission: () async -> Bool
    private let makeRewriter: () -> (any RewriteService)?
    private var segmentProcessingTailTask: Task<Void, Never>?
    private var startTask: Task<Void, Never>?
    private var startAttemptId = UUID()
    private var recordingListId: String?
    private var sessionId = UUID()
    private var captureState: PipelineState = .listening

    init(
        appState: AppState,
        settings: AppSettings,
        remindersManager: any ReminderStore,
        audioCaptureManager: any AudioCapturing = AudioCaptureManager(),
        transcriptionService: any Transcribing = TranscriptionService(),
        requestMicPermission: @escaping () async -> Bool = { await AudioCaptureManager.requestMicPermission() },
        makeRewriter: (() -> (any RewriteService)?)? = nil
    ) {
        self.appState = appState
        self.settings = settings
        self.remindersManager = remindersManager
        self.audioCaptureManager = audioCaptureManager
        self.transcriptionService = transcriptionService
        self.requestMicPermission = requestMicPermission
        self.makeRewriter = makeRewriter ?? {
            if #available(macOS 26.0, *), AppleRewriter.isAvailable { return AppleRewriter() }
            if let key = settings.openRouterApiKey, !key.isEmpty { return OpenRouterRewriter(apiKey: key) }
            return nil
        }
    }

    func startRecording() {
        guard appState.canStartRecording else { return }
        do {
            guard let listId = settings.selectedReminderListId,
                  try remindersManager.fetchReminderLists().contains(where: { $0.id == listId }) else {
                appState.handleError("Select an available Reminders list in Settings.")
                return
            }
            recordingListId = listId
        } catch {
            appState.handleError(error.localizedDescription)
            return
        }
        appState.isStartingRecording = true
        appState.startupStatus = "Waiting for microphone access..."
        appState.dismissError()
        appState.notice = nil
        let attemptId = UUID()
        startAttemptId = attemptId
        startTask = Task { [weak self] in
            guard let self else { return }
            let granted = await requestMicPermission()
            guard !Task.isCancelled else { return }
            defer {
                if startAttemptId == attemptId {
                    appState.isStartingRecording = false
                    startTask = nil
                }
            }
            guard granted else {
                appState.handleError(AudioCaptureError.micPermissionDenied.localizedDescription)
                return
            }
            appState.startupStatus = "Preparing speech recognition..."
            do {
                try await transcriptionService.loadModel(allowSpeechPermissionPrompt: true)
                guard !Task.isCancelled else { return }
                beginCapture()
            } catch {
                guard !Task.isCancelled else { return }
                appState.handleError("Speech recognition setup failed: \(error.localizedDescription)")
            }
        }
    }

    private func beginCapture() {
        let id = UUID()
        sessionId = id
        captureState = .listening
        let builder = SegmentBuilder(silenceTimeoutSeconds: settings.silenceTimeoutSeconds)
        builder.onVoiceStarted = { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.sessionId == id, self.appState.isRecording else { return }
                self.captureState = .speaking
                if !self.appState.isProcessing { self.appState.transitionTo(.speaking) }
            }
        }
        builder.onVoiceEnded = { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.sessionId == id, self.appState.isRecording else { return }
                self.captureState = .listening
            }
        }
        builder.onSegmentReady = { [weak self] segment in
            DispatchQueue.main.async {
                guard let self, self.sessionId == id, let listId = self.recordingListId else { return }
                self.enqueueSegmentForProcessing(segment, listId: listId)
            }
        }
        audioCaptureManager.onAudioBuffer = { buffer, count in builder.feedAudio(buffer: buffer, count: count) }
        do {
            try audioCaptureManager.start()
            segmentBuilder = builder
            appState.startRecording()
        } catch {
            audioCaptureManager.stop()
            appState.handleError(error.localizedDescription)
        }
    }

    func stopRecording() {
        startTask?.cancel()
        startAttemptId = UUID()
        startTask = nil
        appState.isStartingRecording = false
        audioCaptureManager.stop()
        appState.isFinishingRecording = true
        appState.stopRecording()
        segmentBuilder?.flushPendingSegment()
        segmentBuilder = nil
        // Deliver queued VAD callbacks before settling the UI.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.appState.isFinishingRecording = false
            if self.appState.queuedSegmentCount == 0 { self.appState.transitionTo(.idle) }
        }
    }

    func enqueueSegmentForProcessing(_ segment: AudioSegment, listId: String) {
        guard !segment.pcmFloats.isEmpty else { return }
        appState.queuedSegmentCount += 1
        let previousTask = segmentProcessingTailTask
        segmentProcessingTailTask = Task { [weak self] in
            await previousTask?.value
            guard let self else { return }
            await processSegment(segment, listId: listId)
            appState.queuedSegmentCount -= 1
            if appState.queuedSegmentCount == 0 {
                segmentProcessingTailTask = nil
                if !appState.pipelineState.isError {
                    appState.transitionTo(appState.isRecording ? captureState : .idle)
                }
            }
        }
    }

    func waitForProcessing() async { await segmentProcessingTailTask?.value }

    private func processSegment(_ segment: AudioSegment, listId: String) async {
        appState.notice = nil
        appState.transitionTo(.finalizingSTT)
        let transcript: TranscriptResult
        do {
            try await transcriptionService.loadModel(allowSpeechPermissionPrompt: true)
            transcript = try await transcriptionService.transcribe(segment)
        } catch TranscriptionError.emptyTranscript {
            appState.notice = "No speech detected. Try speaking a little longer."
            return
        } catch {
            appState.handleError("Transcription failed: \(error.localizedDescription)")
            return
        }
        let original = transcript.originalTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else { return }
        appState.transitionTo(.rewriting)
        let result = await rewrite(original)
        let pending = PendingReminder(title: result.revised, body: result.formatTaskBody(original: original), listId: listId)
        appState.transitionTo(.saving)
        do {
            try save(pending, listId: listId)
        } catch {
            appState.pendingReminders.append(pending)
            appState.handleError("Save failed: \(error.localizedDescription)")
        }
    }

    private func rewrite(_ original: String) async -> RewriteResult {
        if let rewriter = makeRewriter() {
            do {
                return try await rewriter.rewrite(original).validated()
            } catch {
                if !(rewriter is OpenRouterRewriter), let key = settings.openRouterApiKey,
                   let result = try? await OpenRouterRewriter(apiKey: key).rewrite(original).validated() {
                    return result
                }
                appState.notice = "Rewriting unavailable. Original text retained."
            }
        } else {
            appState.notice = "No rewrite service configured. Original text retained."
        }
        return RewriteResult(revised: original, alternatives: [], corrections: [])
    }

    private func save(_ pending: PendingReminder, listId: String) throws {
        let id = try remindersManager.createReminder(listId: listId, title: pending.title, notes: pending.body)
        appState.lastSavedTask = SavedTask(reminderId: id, title: pending.title, body: pending.body, savedAt: Date())
    }

    func retrySave(_ pending: PendingReminder) {
        guard !appState.isProcessing,
              appState.pendingReminders.contains(where: { $0.id == pending.id }) else { return }
        do {
            try save(pending, listId: settings.selectedReminderListId ?? pending.listId)
            appState.pendingReminders.removeAll { $0.id == pending.id }
            appState.dismissError()
        } catch {
            appState.handleError("Save failed: \(error.localizedDescription)")
        }
    }
}
