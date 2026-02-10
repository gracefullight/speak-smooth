import SwiftUI

@main
struct SpeakSmoothApp: App {
    var body: some Scene {
        MenuBarExtra {
            VStack(spacing: 12) {
                Text("SpeakSmooth")
                    .font(.headline)
                Text("Ready")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(width: 300)
        } label: {
            Image(systemName: "mic")
        }
        .menuBarExtraStyle(.window)
    }
}
