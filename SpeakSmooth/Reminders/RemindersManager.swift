import EventKit
import Foundation

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
        let granted: Bool
        if #available(macOS 14.0, *) {
            granted = try await withCheckedThrowingContinuation { continuation in
                eventStore.requestFullAccessToReminders { granted, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    continuation.resume(returning: granted)
                }
            }
        } else {
            granted = try await withCheckedThrowingContinuation { continuation in
                eventStore.requestAccess(to: .reminder) { granted, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    continuation.resume(returning: granted)
                }
            }
        }

        refreshAuthorizationStatus()
        if !granted || !isAuthorized {
            throw RemindersError.accessDenied
        }
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
        if #available(macOS 14.0, *) {
            return status == .authorized || status == .fullAccess || status == .writeOnly
        }
        return status == .authorized
    }
}

enum RemindersError: LocalizedError {
    case accessDenied
    case listNotFound
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Reminders access is not allowed"
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
