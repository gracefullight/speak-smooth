import SwiftUI

struct MenuBarPopover: View {
    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var settings
    @Environment(RemindersManager.self) private var remindersManager
    @Environment(\.openWindow) private var openWindow
    var coordinator: PipelineCoordinator?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("SpeakSmooth")
                    .font(.headline)
                Spacer()
                Button {
                    openWindow(id: "settings")
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
                Image(systemName: remindersManager.isAuthorized ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(remindersManager.isAuthorized ? .green : .secondary)
                VStack(alignment: .leading) {
                    Text(remindersManager.isAuthorized ? "Reminders access enabled" : "Reminders access needed")
                        .font(.caption)
                    if let listName = settings.selectedReminderListName {
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
    }
}
