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

@Observable
@MainActor
final class AppState {
    var pipelineState: PipelineState = .idle
    var lastSavedTask: SavedTask?
    var lastErrorMessage: String?
    var lastErrorAt: Date?

    var isRecording: Bool {
        switch pipelineState {
        case .idle, .error: return false
        default: return true
        }
    }

    var menuBarIconName: String {
        switch pipelineState {
        case .idle: return "mic"
        case .listening, .speaking, .silenceCountdown: return "mic.fill"
        case .finalizingSTT, .rewriting, .saving: return "mic.badge.ellipsis"
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
        guard pipelineState == .idle || pipelineState.isError else { return }
        pipelineState = .listening
    }

    func stopRecording() {
        pipelineState = .idle
    }

    func transitionTo(_ state: PipelineState) {
        pipelineState = state
    }

    func handleError(_ message: String) {
        lastErrorMessage = message
        lastErrorAt = Date()
        pipelineState = .error(message)
        Task {
            try? await Task.sleep(for: .seconds(3))
            if case .error = pipelineState {
                pipelineState = .idle
            }
        }
    }
}

extension PipelineState {
    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}
