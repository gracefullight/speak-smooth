import SwiftUI
import Security

protocol APIKeyStore {
    func load() throws -> String?
    func save(_ key: String?) throws
}

struct KeychainAPIKeyStore: APIKeyStore {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.speaksmooth.app",
         kSecAttrAccount as String: "openrouter-api-key"]
    }

    func load() throws -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        return (result as? Data).flatMap { String(data: $0, encoding: .utf8) }
    }

    func save(_ key: String?) throws {
        guard let key else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainError(status: status)
            }
            return
        }
        let values = [kSecValueData as String: Data(key.utf8)]
        var status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var item = query.merging(values) { _, new in new }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }
}

struct KeychainError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? {
        "Could not access Keychain: \(SecCopyErrorMessageString(status, nil) as String? ?? String(status))"
    }
}

@Observable
final class AppSettings {
    private let defaults: UserDefaults
    private let keyStore: any APIKeyStore
    private(set) var apiKeyError: String?
    private enum Keys {
        static let silenceTimeout = "silenceTimeoutSeconds"
        static let reminderListId = "selectedReminderListId"
        static let reminderListName = "selectedReminderListName"
        static let legacyTodoListId = "selectedTodoListId"
        static let legacyTodoListName = "selectedTodoListName"
    }

    var silenceTimeoutSeconds: Double {
        didSet {
            let clamped = silenceTimeoutSeconds.isFinite ? min(max(silenceTimeoutSeconds, 1.0), 10.0) : 3.0
            if silenceTimeoutSeconds != clamped { silenceTimeoutSeconds = clamped }
            defaults.set(clamped, forKey: Keys.silenceTimeout)
        }
    }

    var selectedReminderListId: String? {
        didSet {
            defaults.set(selectedReminderListId, forKey: Keys.reminderListId)
            defaults.removeObject(forKey: Keys.legacyTodoListId)
        }
    }

    var selectedReminderListName: String? {
        didSet {
            defaults.set(selectedReminderListName, forKey: Keys.reminderListName)
            defaults.removeObject(forKey: Keys.legacyTodoListName)
        }
    }

    private(set) var openRouterApiKey: String?

    @discardableResult
    func saveAPIKey(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = trimmed.isEmpty ? nil : trimmed
        do {
            try keyStore.save(key)
            openRouterApiKey = key
            apiKeyError = nil
            return true
        } catch {
            apiKeyError = error.localizedDescription
            return false
        }
    }

    init(defaults: UserDefaults = .standard, keyStore: any APIKeyStore = KeychainAPIKeyStore()) {
        self.defaults = defaults
        self.keyStore = keyStore
        let stored = defaults.double(forKey: Keys.silenceTimeout)
        self.silenceTimeoutSeconds = stored.isFinite && stored > 0 ? min(max(stored, 1.0), 10.0) : 3.0
        self.selectedReminderListId = defaults.string(forKey: Keys.reminderListId)
            ?? defaults.string(forKey: Keys.legacyTodoListId)
        self.selectedReminderListName = defaults.string(forKey: Keys.reminderListName)
            ?? defaults.string(forKey: Keys.legacyTodoListName)
        do {
            self.openRouterApiKey = try keyStore.load()
        } catch {
            self.apiKeyError = error.localizedDescription
        }
    }
}
