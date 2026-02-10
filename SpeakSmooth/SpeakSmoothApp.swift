import SwiftUI

@main
struct SpeakSmoothApp: App {
    var body: some Scene {
        MenuBarExtra("SpeakSmooth", systemImage: "mic") {
            Text("Hello")
        }
        .menuBarExtraStyle(.window)
    }
}
