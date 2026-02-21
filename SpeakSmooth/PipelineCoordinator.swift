import Foundation

@MainActor
final class PipelineCoordinator {
    let appState: AppState
    let settings: AppSettings

    private let audioCaptureManager = AudioCaptureManager()
    private var segmentBuilder: SegmentBuilder?
    private let transcriptionService = TranscriptionService()
    private let remindersClient: RemindersClient
    private var rewriter: (any RewriteService)?

    init(appState: AppState, settings: AppSettings, remindersManager: RemindersManager) {
        self.appState = appState
        self.settings = settings
        self.remindersClient = RemindersClient(remindersManager: remindersManager)
        setupRewriter()
    }

    private func setupRewriter() {
        if #available(macOS 26.0, *), AppleRewriter.isAvailable {
            rewriter = AppleRewriter()
        } else if let apiKey = settings.openRouterApiKey, !apiKey.isEmpty {
            rewriter = OpenRouterRewriter(apiKey: apiKey)
        }
    }

    func loadSTTModel() async {
        do {
            try await transcriptionService.loadModel(allowSpeechPermissionPrompt: false)
        } catch {
            print("STT preload skipped: \(error.localizedDescription)")
        }
    }

    func startRecording() {
        guard AudioCaptureManager.isMicAuthorized else {
            Task { @MainActor in
                let granted = await AudioCaptureManager.requestMicPermission()
                if granted {
                    self.startRecording()
                } else {
                    appState.handleError(AudioCaptureError.micPermissionDenied.localizedDescription)
                    AudioCaptureManager.openMicrophonePrivacySettings()
                }
            }
            return
        }

        appState.startRecording()

        let builder = SegmentBuilder(
            sampleRate: .SAMPLERATE_48,
            silenceTimeoutSeconds: settings.silenceTimeoutSeconds
        )

        builder.onVoiceStarted = { [weak self] in
            Task { @MainActor in
                self?.appState.transitionTo(.speaking)
            }
        }

        builder.onVoiceEnded = { [weak self] in
            Task { @MainActor in
                guard self?.appState.pipelineState == .speaking else { return }
                self?.appState.transitionTo(.silenceCountdown)
            }
        }

        builder.onSegmentReady = { [weak self] segment in
            Task { @MainActor in
                await self?.processSegment(segment)
            }
        }

        audioCaptureManager.onAudioBuffer = { buffer, count in
            builder.feedAudio(buffer: buffer, count: count)
        }

        do {
            try audioCaptureManager.start()
            segmentBuilder = builder
        } catch {
            if case AudioCaptureError.micPermissionDenied = error {
                AudioCaptureManager.openMicrophonePrivacySettings()
            }
            appState.handleError(error.localizedDescription)
        }
    }

    func stopRecording() {
        audioCaptureManager.stop()

        guard let builder = segmentBuilder else {
            appState.stopRecording()
            return
        }

        let emittedPendingSegment = builder.flushPendingSegment()
        segmentBuilder = nil

        if !emittedPendingSegment {
            appState.stopRecording()
        }
    }

    private func processSegment(_ segment: AudioSegment) async {
        if await !transcriptionService.isModelLoaded {
            do {
                try await transcriptionService.loadModel()
            } catch {
                appState.handleError("STT model setup failed: \(error.localizedDescription)")
                transitionToNextStateAfterProcessing()
                return
            }
        }

        appState.transitionTo(.finalizingSTT)
        let transcript: TranscriptResult
        do {
            transcript = try await transcriptionService.transcribe(segment)
        } catch {
            appState.handleError("STT failed: \(error.localizedDescription)")
            transitionToNextStateAfterProcessing()
            return
        }

        appState.transitionTo(.rewriting)
        let rewriteResult: RewriteResult
        do {
            if let rewriter {
                rewriteResult = try await rewriter.rewrite(transcript.originalTranscript)
            } else {
                rewriteResult = RewriteResult(
                    revised: transcript.originalTranscript,
                    alternatives: [],
                    corrections: []
                )
            }
        } catch {
            if let apiKey = settings.openRouterApiKey, !apiKey.isEmpty {
                let fallback = OpenRouterRewriter(apiKey: apiKey)
                do {
                    rewriteResult = try await fallback.rewrite(transcript.originalTranscript)
                } catch {
                    rewriteResult = RewriteResult(
                        revised: transcript.originalTranscript,
                        alternatives: [],
                        corrections: ["(rewrite unavailable)"]
                    )
                }
            } else {
                rewriteResult = RewriteResult(
                    revised: transcript.originalTranscript,
                    alternatives: [],
                    corrections: ["(rewrite unavailable)"]
                )
            }
        }

        appState.transitionTo(.saving)
        guard let listId = settings.selectedReminderListId else {
            appState.handleError("No Reminders list selected")
            transitionToNextStateAfterProcessing()
            return
        }

        do {
            let notes = rewriteResult.formatTaskBody(original: transcript.originalTranscript)
            let reminderId = try remindersClient.createReminder(
                listId: listId,
                title: rewriteResult.revised,
                notes: notes
            )

            appState.lastSavedTask = SavedTask(
                reminderId: reminderId,
                title: rewriteResult.revised,
                body: notes,
                savedAt: Date()
            )
        } catch {
            appState.handleError("Save failed: \(error.localizedDescription)")
        }

        transitionToNextStateAfterProcessing()
    }

    private func transitionToNextStateAfterProcessing() {
        appState.transitionTo(audioCaptureManager.isRunning ? .listening : .idle)
    }
}
