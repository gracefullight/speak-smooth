import Foundation

@MainActor
final class PipelineCoordinator {
    let appState: AppState
    let settings: AppSettings
    let authManager: AuthManager

    private let audioCaptureManager = AudioCaptureManager()
    private var segmentBuilder: SegmentBuilder?
    private let transcriptionService = TranscriptionService()
    private var todoClient: TodoClient?
    private var rewriter: (any RewriteService)?

    init(appState: AppState, settings: AppSettings, authManager: AuthManager) {
        self.appState = appState
        self.settings = settings
        self.authManager = authManager
        self.todoClient = TodoClient { [weak authManager] in
            guard let authManager else { throw AuthError.notSignedIn }
            return try await authManager.getAccessToken()
        }
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
            try await transcriptionService.loadModel()
        } catch {
            appState.handleError("Failed to load STT model: \(error.localizedDescription)")
        }
    }

    func startRecording() {
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
            appState.handleError(error.localizedDescription)
        }
    }

    func stopRecording() {
        audioCaptureManager.stop()
        segmentBuilder = nil
        appState.stopRecording()
    }

    private func processSegment(_ segment: AudioSegment) async {
        appState.transitionTo(.finalizingSTT)
        let transcript: TranscriptResult
        do {
            transcript = try await transcriptionService.transcribe(segment)
        } catch {
            appState.handleError("STT failed: \(error.localizedDescription)")
            appState.transitionTo(.listening)
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
        guard let listId = settings.selectedTodoListId else {
            appState.handleError("No To Do list selected")
            appState.transitionTo(.listening)
            return
        }

        guard let todoClient else {
            appState.handleError("To Do client unavailable")
            appState.transitionTo(.listening)
            return
        }

        do {
            let bodyText = rewriteResult.formatTaskBody(original: transcript.originalTranscript)
            let taskId = try await todoClient.createTask(
                listId: listId,
                title: rewriteResult.revised,
                bodyText: bodyText
            )

            appState.lastSavedTask = SavedTask(
                graphTaskId: taskId,
                title: rewriteResult.revised,
                body: bodyText,
                savedAt: Date()
            )
        } catch {
            appState.handleError("Save failed: \(error.localizedDescription)")
        }

        appState.transitionTo(.listening)
    }
}
