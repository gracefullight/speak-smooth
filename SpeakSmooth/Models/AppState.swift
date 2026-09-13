import SwiftUI

enum PipelineState: Equatable {
    case idle
    case listening
    case speaking
    case silenceCountdown
    case finalizingSTT
    case rewriting
    case saving
    case error(String)
}

struct SavedTask: Equatable {
    let reminderId: String
    let title: String
    let body: String?
    let savedAt: Date
}

struct PendingReminder: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let body: String
    let listId: String
}

@Observable
@MainActor
final class AppState {
    var pipelineState: PipelineState = .idle
    var lastSavedTask: SavedTask?
    var lastErrorMessage: String?
    var lastErrorAt: Date?
    private(set) var isRecording = false
    var isStartingRecording = false
    var startupStatus = "Waiting for microphone access..."
    var isFinishingRecording = false
    var queuedSegmentCount = 0
    var pendingReminders: [PendingReminder] = []
    var notice: String?

    var isProcessing: Bool { queuedSegmentCount > 0 || isFinishingRecording }
    var canStartRecording: Bool { !isRecording && !isStartingRecording && !isProcessing }

    var menuBarIconName: String {
        if isRecording { return "mic.fill" }
        switch pipelineState {
        case .idle: return "mic"
        case .listening, .speaking, .silenceCountdown: return "mic.fill"
        case .finalizingSTT, .rewriting, .saving: return "mic.fill"
        case .error: return "mic.slash"
        }
    }

    var statusText: String {
        switch pipelineState {
        case .idle: return "Ready"
        case .listening: return "Listening..."
        case .speaking: return "Hearing you..."
        case .silenceCountdown: return "Waiting..."
        case .finalizingSTT: return "Transcribing..."
        case .rewriting: return "Rewriting..."
        case .saving: return "Saving to Reminders..."
        case .error(let msg): return msg
        }
    }

    func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        pipelineState = .listening
    }

    func stopRecording() {
        isRecording = false
        if !isProcessing { pipelineState = .idle }
    }

    func transitionTo(_ state: PipelineState) {
        pipelineState = state
    }

    func handleError(_ message: String) {
        lastErrorMessage = message
        lastErrorAt = Date()
        pipelineState = .error(message)
    }

    func dismissError() {
        lastErrorMessage = nil
        lastErrorAt = nil
        if pipelineState.isError {
            pipelineState = isRecording ? .listening : .idle
        }
    }
}

extension PipelineState {
    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}
