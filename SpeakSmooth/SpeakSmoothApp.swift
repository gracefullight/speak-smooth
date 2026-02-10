import SwiftUI

@main
struct SpeakSmoothApp: App {
    @State private var appState: AppState
    @State private var settings: AppSettings
    @State private var authManager: AuthManager
    @State private var coordinator: PipelineCoordinator

    init() {
        let appState = AppState()
        let settings = AppSettings()
        let authManager = AuthManager()
        let coordinator = PipelineCoordinator(
            appState: appState,
            settings: settings,
            authManager: authManager
        )
        _appState = State(initialValue: appState)
        _settings = State(initialValue: settings)
        _authManager = State(initialValue: authManager)
        _coordinator = State(initialValue: coordinator)
        Task { await coordinator.loadSTTModel() }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover(coordinator: coordinator)
                .environment(appState)
                .environment(settings)
                .environment(authManager)
        } label: {
            Image(systemName: appState.menuBarIconName)
        }
        .menuBarExtraStyle(.window)
    }
}
