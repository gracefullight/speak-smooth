import SwiftUI

struct MenuBarPopover: View {
    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var settings
    @Environment(AuthManager.self) private var authManager
    var coordinator: PipelineCoordinator?

    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("SpeakSmooth")
                    .font(.headline)
                Spacer()
                Button {
                    showSettings.toggle()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            VStack(spacing: 12) {
                Button {
                    if appState.isRecording {
                        coordinator?.stopRecording()
                    } else {
                        coordinator?.startRecording()
                    }
                } label: {
                    Label(
                        appState.isRecording ? "Stop" : "Start",
                        systemImage: appState.isRecording ? "stop.circle.fill" : "mic.circle.fill"
                    )
                    .font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(appState.isRecording ? .red : .accentColor)

                HStack(spacing: 6) {
                    StatusIndicator(state: appState.pipelineState)
                    Text(appState.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 12)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                if let task = appState.lastSavedTask {
                    Text("Last saved:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TaskPreviewCard(task: task)
                } else {
                    Text("No tasks saved yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            HStack {
                Image(systemName: authManager.isSignedIn ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(authManager.isSignedIn ? .green : .secondary)
                VStack(alignment: .leading) {
                    Text(authManager.isSignedIn ? "Signed in" : "Not signed in")
                        .font(.caption)
                    if let listName = settings.selectedTodoListName {
                        Text("List: \(listName)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(width: 320)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(settings)
                .environment(authManager)
        }
    }
}
