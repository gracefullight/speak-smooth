import EventKit
import Foundation
import AppKit

@Observable
@MainActor
final class RemindersManager {
    private let eventStore: EKEventStore
    private(set) var authorizationStatus: EKAuthorizationStatus

    var isAuthorized: Bool {
        Self.isAuthorizedStatus(authorizationStatus)
    }

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
        self.authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
    }

    func refreshAuthorizationStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
    }

    func requestAccess() async throws {
        refreshAuthorizationStatus()
        if isAuthorized { return }

        if authorizationStatus == .denied || authorizationStatus == .restricted {
            throw RemindersError.openSystemSettingsRequired
        }

        let granted = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            eventStore.requestFullAccessToReminders { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: granted)
            }
        }

        refreshAuthorizationStatus()
        if !granted || !isAuthorized {
            if authorizationStatus == .denied || authorizationStatus == .restricted {
                throw RemindersError.openSystemSettingsRequired
            }
            throw RemindersError.accessDenied
        }
    }

    func openRemindersPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func fetchReminderLists() throws -> [ReminderList] {
        refreshAuthorizationStatus()
        guard isAuthorized else {
            throw RemindersError.accessDenied
        }

        return eventStore
            .calendars(for: .reminder)
            .filter(\.allowsContentModifications)
            .map { ReminderList(id: $0.calendarIdentifier, displayName: $0.title) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func reminderListName(for listId: String) -> String? {
        eventStore.calendar(withIdentifier: listId)?.title
    }

    func createReminder(
        listId: String,
        title: String,
        notes: String?
    ) throws -> String {
        refreshAuthorizationStatus()
        guard isAuthorized else {
            throw RemindersError.accessDenied
        }

        guard let calendar = eventStore.calendar(withIdentifier: listId) else {
            throw RemindersError.listNotFound
        }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.calendar = calendar
        reminder.title = title
        reminder.notes = notes

        do {
            try eventStore.save(reminder, commit: true)
            return reminder.calendarItemIdentifier
        } catch {
            throw RemindersError.saveFailed(error.localizedDescription)
        }
    }

    private static func isAuthorizedStatus(_ status: EKAuthorizationStatus) -> Bool {
        status == .fullAccess || status == .writeOnly
    }
}

enum RemindersError: LocalizedError {
    case accessDenied
    case openSystemSettingsRequired
    case listNotFound
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Reminders access is not allowed"
        case .openSystemSettingsRequired:
            return "Reminders access is denied. Enable SpeakSmooth in System Settings > Privacy & Security > Reminders."
        case .listNotFound:
            return "Selected Reminders list not found"
        case .saveFailed(let message):
            return "Failed to save reminder: \(message)"
        }
    }
}

#if DEBUG
extension RemindersManager {
    func setAuthorizationStatusForTesting(_ status: EKAuthorizationStatus) {
        self.authorizationStatus = status
    }
}
#endif
