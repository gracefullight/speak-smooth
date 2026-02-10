import Foundation
import Testing
@testable import SpeakSmooth

@Suite("Settings Tests")
struct SettingsTests {
    // Clean up UserDefaults before each test to avoid cross-test pollution
    private func cleanDefaults() {
        UserDefaults.standard.removeObject(forKey: "silenceTimeoutSeconds")
        UserDefaults.standard.removeObject(forKey: "selectedTodoListId")
        UserDefaults.standard.removeObject(forKey: "selectedTodoListName")
    }

    @Test("Default silence timeout is 3.0")
    func defaultSilenceTimeout() {
        cleanDefaults()
        let settings = AppSettings()
        #expect(settings.silenceTimeoutSeconds == 3.0)
    }

    @Test("Default todo list is nil")
    func defaultTodoList() {
        cleanDefaults()
        let settings = AppSettings()
        #expect(settings.selectedTodoListId == nil)
        #expect(settings.selectedTodoListName == nil)
    }

    @Test("Silence timeout clamps to valid range")
    func silenceTimeoutClamped() {
        cleanDefaults()
        var settings = AppSettings()
        settings.silenceTimeoutSeconds = 0.5
        #expect(settings.silenceTimeoutSeconds == 1.0)
        settings.silenceTimeoutSeconds = 15.0
        #expect(settings.silenceTimeoutSeconds == 10.0)
    }
}
