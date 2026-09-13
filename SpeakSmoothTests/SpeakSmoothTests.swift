import Testing
import Foundation
@testable import SpeakSmooth

final class MemoryAPIKeyStore: APIKeyStore {
    var key: String?
    var shouldFail = false
    func load() throws -> String? { key }
    func save(_ key: String?) throws {
        if shouldFail { throw RewriteError.unavailable }
        self.key = key
    }
}

func makeTestSettings() -> AppSettings {
    AppSettings(defaults: UserDefaults(suiteName: "SpeakSmoothTests.\(UUID().uuidString)")!, keyStore: MemoryAPIKeyStore())
}

@MainActor
private final class TestReminderStore: ReminderStore {
    var lists = [ReminderList(id: "list-a", displayName: "Practice")]
    var saved: [(listId: String, title: String)] = []
    var shouldFail = false
    func fetchReminderLists() throws -> [ReminderList] { lists }
    func createReminder(listId: String, title: String, notes: String?) throws -> String {
        if shouldFail { throw RemindersError.saveFailed("Test failure") }
        saved.append((listId, title))
        return "saved-\(saved.count)"
    }
}

private final class TestAudioCapture: AudioCapturing {
    var isRunning = false
    var startCount = 0
    var onAudioBuffer: (@Sendable (UnsafePointer<Float>, UInt) -> Void)?
    func start() throws { isRunning = true; startCount += 1 }
    func stop() { isRunning = false }
}

private actor TestTranscriber: Transcribing {
    var count = 0
    let fail: Bool
    init(fail: Bool = false) { self.fail = fail }
    func loadModel(allowSpeechPermissionPrompt: Bool) async throws {}
    func transcribe(_ segment: AudioSegment) async throws -> TranscriptResult {
        if fail { throw TranscriptionError.emptyTranscript }
        count += 1
        return TranscriptResult(originalTranscript: "Sentence \(count)")
    }
}

private struct TestRewriter: RewriteService {
    let text: String
    func rewrite(_ original: String) async throws -> RewriteResult {
        RewriteResult(revised: text, alternatives: [], corrections: [])
    }
}

@Suite("Pipeline regression tests")
@MainActor
struct PipelineTests {
    private let segment = AudioSegment(pcmFloats: [0.1, 0.2], durationSeconds: 0.01)

    @Test("Segments save in order to their captured destination")
    func orderedSaving() async {
        let state = AppState()
        let settings = makeTestSettings()
        let store = TestReminderStore()
        let coordinator = PipelineCoordinator(appState: state, settings: settings, remindersManager: store,
            transcriptionService: TestTranscriber(), makeRewriter: { nil })
        coordinator.enqueueSegmentForProcessing(segment, listId: "list-a")
        coordinator.enqueueSegmentForProcessing(segment, listId: "list-a")
        settings.selectedReminderListId = "list-b"
        #expect(state.isProcessing)
        #expect(!state.isRecording)
        #expect(!state.canStartRecording)
        await coordinator.waitForProcessing()
        #expect(store.saved.map(\.title) == ["Sentence 1", "Sentence 2"])
        #expect(store.saved.allSatisfy { $0.listId == "list-a" })
        #expect(state.queuedSegmentCount == 0)
        #expect(state.canStartRecording)
    }

    @Test("Save failures preserve every sentence and retry only once")
    func retrySaving() async throws {
        let state = AppState()
        let settings = makeTestSettings()
        let store = TestReminderStore()
        store.shouldFail = true
        let coordinator = PipelineCoordinator(appState: state, settings: settings, remindersManager: store,
            transcriptionService: TestTranscriber(), makeRewriter: { nil })
        coordinator.enqueueSegmentForProcessing(segment, listId: "list-a")
        coordinator.enqueueSegmentForProcessing(segment, listId: "list-a")
        await coordinator.waitForProcessing()
        #expect(state.pendingReminders.count == 2)
        #expect(state.pipelineState.isError)
        let pending = try #require(state.pendingReminders.first)
        store.shouldFail = false
        settings.selectedReminderListId = "list-b"
        coordinator.retrySave(pending)
        coordinator.retrySave(pending)
        #expect(store.saved.count == 1)
        #expect(store.saved.first?.listId == "list-b")
        #expect(state.pendingReminders.count == 1)
    }

    @Test("Blank rewrite falls back to original transcript")
    func invalidRewrite() async {
        let state = AppState()
        let store = TestReminderStore()
        let coordinator = PipelineCoordinator(appState: state, settings: makeTestSettings(), remindersManager: store,
            transcriptionService: TestTranscriber(), makeRewriter: { TestRewriter(text: "  \n") })
        coordinator.enqueueSegmentForProcessing(segment, listId: "list-a")
        await coordinator.waitForProcessing()
        #expect(store.saved.first?.title == "Sentence 1")
        #expect(state.notice != nil)
    }

    @Test("Rewrite settings are reevaluated for the next sentence")
    func updatedRewriter() async {
        let state = AppState()
        let settings = makeTestSettings()
        let store = TestReminderStore()
        let coordinator = PipelineCoordinator(appState: state, settings: settings, remindersManager: store,
            transcriptionService: TestTranscriber(), makeRewriter: {
                settings.openRouterApiKey == nil ? nil : TestRewriter(text: "Corrected")
            })
        coordinator.enqueueSegmentForProcessing(segment, listId: "list-a")
        await coordinator.waitForProcessing()
        settings.saveAPIKey("test-key")
        coordinator.enqueueSegmentForProcessing(segment, listId: "list-a")
        await coordinator.waitForProcessing()
        #expect(store.saved.map(\.title) == ["Sentence 1", "Corrected"])
    }

    @Test("Silence creates no reminder and leaves pipeline ready")
    func emptySpeech() async {
        let state = AppState()
        let store = TestReminderStore()
        let coordinator = PipelineCoordinator(appState: state, settings: makeTestSettings(), remindersManager: store,
            transcriptionService: TestTranscriber(fail: true), makeRewriter: { nil })
        coordinator.enqueueSegmentForProcessing(segment, listId: "list-a")
        await coordinator.waitForProcessing()
        #expect(store.saved.isEmpty)
        #expect(state.pipelineState == .idle)
        #expect(state.notice != nil)
    }

    @Test("Missing list prevents permission prompt and microphone capture")
    func missingDestination() {
        let state = AppState()
        let audio = TestAudioCapture()
        let coordinator = PipelineCoordinator(appState: state, settings: makeTestSettings(), remindersManager: TestReminderStore(),
            audioCaptureManager: audio, requestMicPermission: { Issue.record("Unexpected permission prompt"); return true })
        coordinator.startRecording()
        #expect(audio.startCount == 0)
        #expect(state.pipelineState.isError)
    }

    @Test("Stop cancels a pending microphone request")
    func cancelPendingStart() async {
        let state = AppState()
        let settings = makeTestSettings()
        settings.selectedReminderListId = "list-a"
        let audio = TestAudioCapture()
        var permission: CheckedContinuation<Bool, Never>?
        let coordinator = PipelineCoordinator(appState: state, settings: settings, remindersManager: TestReminderStore(),
            audioCaptureManager: audio, requestMicPermission: {
                await withCheckedContinuation { permission = $0 }
            })
        coordinator.startRecording()
        while permission == nil { await Task.yield() }
        coordinator.startRecording()
        coordinator.stopRecording()
        permission?.resume(returning: true)
        await Task.yield()
        #expect(audio.startCount == 0)
        #expect(!state.isRecording)
        #expect(!state.isStartingRecording)
    }
}
