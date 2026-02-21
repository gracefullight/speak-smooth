import Testing
@testable import SpeakSmooth

@Suite("AppState Tests")
struct AppStateTests {
    @Test("Initial state is idle")
    @MainActor func initialState() {
        let state = AppState()
        #expect(state.pipelineState == .idle)
    }

    @Test("Menu bar icon name reflects state")
    @MainActor func menuBarIconName() {
        let state = AppState()
        #expect(state.menuBarIconName == "mic")

        state.pipelineState = .listening
        #expect(state.menuBarIconName == "mic.fill")

        state.pipelineState = .finalizingSTT
        #expect(state.menuBarIconName == "mic.fill")

        state.pipelineState = .error("test")
        #expect(state.menuBarIconName == "mic.slash")
    }

    @Test("Can start recording from idle")
    @MainActor func startFromIdle() {
        let state = AppState()
        state.startRecording()
        #expect(state.pipelineState == .listening)
    }

    @Test("Can stop recording from any active state")
    @MainActor func stopFromActive() {
        let state = AppState()
        state.pipelineState = .speaking
        state.stopRecording()
        #expect(state.pipelineState == .idle)
    }

    @Test("Error auto-description")
    @MainActor func errorState() {
        let state = AppState()
        state.pipelineState = .error("Network failed")
        #expect(state.statusText == "Network failed")
    }
}
