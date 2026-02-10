import Testing
@testable import SpeakSmooth

@Suite("Settings Tests")
struct SettingsTests {
    @Test("Default silence timeout is 3.0")
    func defaultSilenceTimeout() {
        let settings = AppSettings()
        #expect(settings.silenceTimeoutSeconds == 3.0)
    }

    @Test("Default todo list is nil")
    func defaultTodoList() {
        let settings = AppSettings()
        #expect(settings.selectedTodoListId == nil)
        #expect(settings.selectedTodoListName == nil)
    }

    @Test("Silence timeout clamps to valid range")
    func silenceTimeoutClamped() {
        var settings = AppSettings()
        settings.silenceTimeoutSeconds = 0.5
        #expect(settings.silenceTimeoutSeconds == 1.0)
        settings.silenceTimeoutSeconds = 15.0
        #expect(settings.silenceTimeoutSeconds == 10.0)
    }
}
