import Foundation
import Testing
@testable import SpeakSmooth

@Suite("Settings Tests", .serialized)
struct SettingsTests {
    @Test("Default silence timeout is 3.0")
    func defaultSilenceTimeout() {
        let settings = makeTestSettings()
        #expect(settings.silenceTimeoutSeconds == 3.0)
    }

    @Test("Default reminders list is nil")
    func defaultReminderList() {
        let settings = makeTestSettings()
        #expect(settings.selectedReminderListId == nil)
        #expect(settings.selectedReminderListName == nil)
    }

    @Test("Silence timeout clamps to valid range")
    func silenceTimeoutClamped() {
        let settings = makeTestSettings()
        settings.silenceTimeoutSeconds = 0.5
        #expect(settings.silenceTimeoutSeconds == 1.0)
        settings.silenceTimeoutSeconds = 15.0
        #expect(settings.silenceTimeoutSeconds == 10.0)
        settings.silenceTimeoutSeconds = .nan
        #expect(settings.silenceTimeoutSeconds == 3.0)
        settings.silenceTimeoutSeconds = .infinity
        #expect(settings.silenceTimeoutSeconds == 3.0)
    }

    @Test("API key survives reload, trims whitespace, and can be removed")
    func apiKeyPersistence() {
        let defaults = UserDefaults(suiteName: "SpeakSmoothTests.\(UUID())")!
        let store = MemoryAPIKeyStore()
        let settings = AppSettings(defaults: defaults, keyStore: store)
        #expect(settings.saveAPIKey("  test-key\n"))
        #expect(AppSettings(defaults: defaults, keyStore: store).openRouterApiKey == "test-key")
        #expect(settings.saveAPIKey(""))
        #expect(AppSettings(defaults: defaults, keyStore: store).openRouterApiKey == nil)
    }

    @Test("Failed credential save preserves the working key")
    func credentialFailure() {
        let store = MemoryAPIKeyStore()
        store.key = "working-key"
        let settings = AppSettings(defaults: UserDefaults(suiteName: "SpeakSmoothTests.\(UUID())")!, keyStore: store)
        store.shouldFail = true
        #expect(!settings.saveAPIKey("replacement"))
        #expect(settings.openRouterApiKey == "working-key")
        #expect(settings.apiKeyError != nil)
    }

    @Test("Cleared migrated list does not reappear on restart")
    func legacyListMigration() {
        let name = "SpeakSmoothTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("old-list", forKey: "selectedTodoListId")
        defaults.set("Old list", forKey: "selectedTodoListName")
        let settings = AppSettings(defaults: defaults, keyStore: MemoryAPIKeyStore())
        #expect(settings.selectedReminderListId == "old-list")
        settings.selectedReminderListId = nil
        settings.selectedReminderListName = nil
        let reloaded = AppSettings(defaults: defaults, keyStore: MemoryAPIKeyStore())
        #expect(reloaded.selectedReminderListId == nil)
        #expect(reloaded.selectedReminderListName == nil)
    }
}
