import SwiftUI

@main
struct SpeakSmoothApp: App {
    @State private var appState: AppState
    @State private var settings: AppSettings
    @State private var remindersManager: RemindersManager
    @State private var coordinator: PipelineCoordinator

    init() {
        let appState = AppState()
        let settings = AppSettings()
        let remindersManager = RemindersManager()
        let coordinator = PipelineCoordinator(
            appState: appState,
            settings: settings,
            remindersManager: remindersManager
        )
        _appState = State(initialValue: appState)
        _settings = State(initialValue: settings)
        _remindersManager = State(initialValue: remindersManager)
        _coordinator = State(initialValue: coordinator)
        Task { await coordinator.loadSTTModel() }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover(coordinator: coordinator)
                .environment(appState)
                .environment(settings)
                .environment(remindersManager)
        } label: {
            Image(systemName: appState.menuBarIconName)
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Settings", id: "settings") {
            SettingsView()
                .environment(settings)
                .environment(remindersManager)
        }
    }
}
