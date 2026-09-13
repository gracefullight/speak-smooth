import SwiftUI
import AppKit

struct MenuBarPopover: View {
    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var settings
    @Environment(RemindersManager.self) private var remindersManager
    @Environment(\.openWindow) private var openWindow
    @State private var confirmQuit = false
    var coordinator: PipelineCoordinator?

    private var needsSetup: Bool {
        !remindersManager.isAuthorized || settings.selectedReminderListId == nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("SpeakSmooth").font(.headline)
                Spacer()
                Button(action: openSettings) { Image(systemName: "gearshape") }
                    .help("Settings")
                    .accessibilityLabel("Settings")
                    .keyboardShortcut(",")
            }
            .padding(16)
            Divider()

            VStack(spacing: 12) {
                if needsSetup && !appState.isRecording && !appState.isStartingRecording {
                    Button("Set Up Reminders", action: openSettings)
                        .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        if appState.isRecording || appState.isStartingRecording {
                            coordinator?.stopRecording()
                        } else {
                            coordinator?.startRecording()
                        }
                    } label: {
                        Label(
                            appState.isStartingRecording ? "Cancel" : appState.isRecording ? "Stop Recording" : appState.isProcessing ? "Finishing..." : "Start Recording",
                            systemImage: appState.isRecording || appState.isStartingRecording ? "stop.fill" : "mic.fill"
                        )
                        .frame(maxWidth: .infinity, minHeight: 28)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(appState.isRecording ? .red : .accentColor)
                    .disabled(!appState.isRecording && !appState.isStartingRecording && appState.isProcessing)
                }

                HStack(spacing: 6) {
                    if appState.isProcessing || appState.isStartingRecording {
                        ProgressView().controlSize(.small)
                    } else {
                        StatusIndicator(state: appState.pipelineState)
                    }
                    Text(appState.isStartingRecording ? appState.startupStatus : appState.pipelineState.isError ? "Action needed" : appState.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if appState.isRecording && appState.isProcessing {
                    Label("Microphone is still on", systemImage: "mic.fill")
                        .font(.caption).foregroundStyle(.red)
                }
                if appState.queuedSegmentCount > 1 {
                    Text("\(appState.queuedSegmentCount) sentences remaining").font(.caption)
                }
                if let message = appState.lastErrorMessage {
                    HStack(alignment: .top) {
                        Text(message).font(.caption).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Button { appState.dismissError() } label: { Image(systemName: "xmark") }
                            .help("Dismiss error").accessibilityLabel("Dismiss error")
                    }
                    .foregroundStyle(.red)
                    if message == AudioCaptureError.micPermissionDenied.localizedDescription {
                        Button("Microphone Privacy Settings") { AudioCaptureManager.openMicrophonePrivacySettings() }
                    }
                }
                if let notice = appState.notice {
                    Text(notice).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)

            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(appState.pendingReminders) { pending in
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Not saved", systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.orange)
                            Text(pending.title).textSelection(.enabled)
                            HStack {
                                Button("Retry Save") { coordinator?.retrySave(pending) }
                                    .disabled(appState.isProcessing)
                                Spacer()
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(pending.title + "\n" + pending.body, forType: .string)
                                } label: { Image(systemName: "doc.on.doc") }
                                .help("Copy unsaved sentence").accessibilityLabel("Copy unsaved sentence")
                            }
                        }
                        .padding(10)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    }
                    if let task = appState.lastSavedTask {
                        Text("Last saved").font(.caption).foregroundStyle(.secondary)
                        TaskPreviewCard(task: task)
                    } else if appState.pendingReminders.isEmpty {
                        Text("No sentences saved yet").font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                }
                .padding(16)
            }
            .frame(height: appState.pendingReminders.isEmpty ? (appState.lastSavedTask == nil ? 68 : 220) : 260)
            Divider()
            HStack {
                Image(systemName: remindersManager.isAuthorized ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundStyle(remindersManager.isAuthorized ? .green : .secondary)
                Text(settings.selectedReminderListName ?? "No list selected")
                    .font(.caption).lineLimit(1)
                    .help(settings.selectedReminderListName ?? "No list selected")
                Spacer()
                Button {
                    if appState.isRecording || appState.isStartingRecording || appState.isProcessing || !appState.pendingReminders.isEmpty {
                        confirmQuit = true
                    } else {
                        NSApp.terminate(nil)
                    }
                } label: { Image(systemName: "power") }
                .help("Quit SpeakSmooth").accessibilityLabel("Quit SpeakSmooth")
            }
            .padding(16)
        }
        .frame(width: 360)
        .onAppear { remindersManager.refreshAuthorizationStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            remindersManager.refreshAuthorizationStatus()
        }
        .alert("Quit SpeakSmooth?", isPresented: $confirmQuit) {
            Button("Keep Open", role: .cancel) {}
            Button("Quit", role: .destructive) { NSApp.terminate(nil) }
        } message: {
            Text("Recording and processing will stop. Unsaved sentences will be lost.")
        }
    }

    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "settings")
    }
}
