import SwiftUI

@Observable
final class AppSettings {
    private enum Keys {
        static let silenceTimeout = "silenceTimeoutSeconds"
        static let reminderListId = "selectedReminderListId"
        static let reminderListName = "selectedReminderListName"
        static let legacyTodoListId = "selectedTodoListId"
        static let legacyTodoListName = "selectedTodoListName"
    }

    var silenceTimeoutSeconds: Double {
        didSet {
            let clamped = min(max(silenceTimeoutSeconds, 1.0), 10.0)
            if silenceTimeoutSeconds != clamped { silenceTimeoutSeconds = clamped }
            UserDefaults.standard.set(clamped, forKey: Keys.silenceTimeout)
        }
    }

    var selectedReminderListId: String? {
        didSet {
            UserDefaults.standard.set(selectedReminderListId, forKey: Keys.reminderListId)
        }
    }

    var selectedReminderListName: String? {
        didSet {
            UserDefaults.standard.set(selectedReminderListName, forKey: Keys.reminderListName)
        }
    }

    var openRouterApiKey: String?

    init() {
        let stored = UserDefaults.standard.double(forKey: Keys.silenceTimeout)
        self.silenceTimeoutSeconds = stored > 0 ? min(max(stored, 1.0), 10.0) : 3.0
        self.selectedReminderListId = UserDefaults.standard.string(forKey: Keys.reminderListId)
            ?? UserDefaults.standard.string(forKey: Keys.legacyTodoListId)
        self.selectedReminderListName = UserDefaults.standard.string(forKey: Keys.reminderListName)
            ?? UserDefaults.standard.string(forKey: Keys.legacyTodoListName)
    }
}
