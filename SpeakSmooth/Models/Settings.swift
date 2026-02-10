import SwiftUI

@Observable
final class AppSettings {
    private enum Keys {
        static let silenceTimeout = "silenceTimeoutSeconds"
        static let todoListId = "selectedTodoListId"
        static let todoListName = "selectedTodoListName"
    }

    var silenceTimeoutSeconds: Double {
        didSet {
            let clamped = min(max(silenceTimeoutSeconds, 1.0), 10.0)
            if silenceTimeoutSeconds != clamped { silenceTimeoutSeconds = clamped }
            UserDefaults.standard.set(clamped, forKey: Keys.silenceTimeout)
        }
    }

    var selectedTodoListId: String? {
        didSet { UserDefaults.standard.set(selectedTodoListId, forKey: Keys.todoListId) }
    }

    var selectedTodoListName: String? {
        didSet { UserDefaults.standard.set(selectedTodoListName, forKey: Keys.todoListName) }
    }

    var openRouterApiKey: String?

    init() {
        let stored = UserDefaults.standard.double(forKey: Keys.silenceTimeout)
        self.silenceTimeoutSeconds = stored > 0 ? min(max(stored, 1.0), 10.0) : 3.0
        self.selectedTodoListId = UserDefaults.standard.string(forKey: Keys.todoListId)
        self.selectedTodoListName = UserDefaults.standard.string(forKey: Keys.todoListName)
    }
}
