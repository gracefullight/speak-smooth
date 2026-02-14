import Foundation

struct ReminderList: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
}

@MainActor
final class RemindersClient {
    private let remindersManager: RemindersManager

    init(remindersManager: RemindersManager) {
        self.remindersManager = remindersManager
    }

    func fetchReminderLists() throws -> [ReminderList] {
        try remindersManager.fetchReminderLists()
    }

    func createReminder(
        listId: String,
        title: String,
        notes: String?
    ) throws -> String {
        try remindersManager.createReminder(
            listId: listId,
            title: title,
            notes: notes
        )
    }
}
