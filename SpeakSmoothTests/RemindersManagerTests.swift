import Testing
@testable import SpeakSmooth

@Suite("Reminders Error Tests")
struct RemindersManagerTests {
    @Test("Access denied description")
    func accessDeniedDescription() {
        #expect(RemindersError.accessDenied.errorDescription == "Reminders access is not allowed")
    }

    @Test("List not found description")
    func listNotFoundDescription() {
        #expect(RemindersError.listNotFound.errorDescription == "Selected Reminders list not found")
    }

    @Test("Save failed description wraps original message")
    func saveFailedDescription() {
        #expect(RemindersError.saveFailed("x").errorDescription == "Failed to save reminder: x")
    }
}
