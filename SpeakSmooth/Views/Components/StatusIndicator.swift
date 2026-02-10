import SwiftUI

struct StatusIndicator: View {
    let state: PipelineState

    private var color: Color {
        switch state {
        case .idle: return .secondary
        case .listening: return .green
        case .speaking, .silenceCountdown: return .red
        case .finalizingSTT, .rewriting, .saving: return .orange
        case .error: return .yellow
        }
    }

    private var shouldPulse: Bool {
        switch state {
        case .speaking, .finalizingSTT, .rewriting, .saving: return true
        default: return false
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .opacity(shouldPulse ? 0.6 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: shouldPulse)
    }
}
