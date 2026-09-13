import SwiftUI
import AppKit

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(RemindersManager.self) private var remindersManager
    @Environment(\.dismiss) private var dismiss

    @State private var reminderLists: [ReminderList] = []
    @State private var isLoadingLists = false
    @State private var apiKeyInput = ""
    @State private var remindersErrorMessage: String?
    @State private var showOpenPrivacySettingsButton = false
    @State private var apiKeySaved = false

    var body: some View {
        @Bindable var settings = settings

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Settings")
                    .font(.title2.weight(.semibold))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Silence timeout")
                        .font(.headline)
                    HStack {
                        Slider(value: $settings.silenceTimeoutSeconds, in: 1.0...10.0, step: 0.5)
                            .accessibilityLabel("Silence timeout")
                        Text("\(settings.silenceTimeoutSeconds, specifier: "%.1f")s")
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Apple Reminders")
                        .font(.headline)

                    if remindersManager.isAuthorized {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Access enabled")
                            Spacer()
                            Button {
                                Task { await loadLists() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .help("Refresh lists")
                            .accessibilityLabel("Refresh lists")
                            .disabled(isLoadingLists)
                        }
                    } else {
                        Button("Enable Reminders Access") {
                            Task { await requestRemindersAccess() }
                        }
                    }

                    if let remindersErrorMessage, !remindersErrorMessage.isEmpty {
                        Text(remindersErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)

                        if showOpenPrivacySettingsButton {
                            Button("Open Privacy Settings") {
                                remindersManager.openRemindersPrivacySettings()
                            }
                            .font(.caption)
                        }
                    }
                }

                if remindersManager.isAuthorized {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Reminders List")
                                .font(.headline)
                            Spacer()
                            if isLoadingLists {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                        }

                        listPicker
                        if !isLoadingLists && reminderLists.isEmpty {
                            Text("No writable lists available.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Open Reminders") {
                                NSWorkspace.shared.open(URL(string: "x-apple-reminderkit://")!)
                            }
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("OpenRouter API Key")
                        .font(.headline)
                    Text("Optional. Fallback sends transcript text to OpenRouter. Saved in Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField("sk-or-...", text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { saveAPIKey() }
                        .onChange(of: apiKeyInput) { _, _ in apiKeySaved = false }
                    HStack {
                        Button("Save Key") { saveAPIKey() }
                            .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("Remove Key", role: .destructive) {
                            if settings.saveAPIKey("") {
                                apiKeyInput = ""
                                apiKeySaved = false
                            }
                        }
                        .disabled(settings.openRouterApiKey == nil)
                        if apiKeySaved {
                            Label("Saved", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }
                    }
                    if let error = settings.apiKeyError {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("About")
                        .font(.headline)
                    Link("Buy Me A Coffee", destination: URL(string: "https://www.buymeacoffee.com/gracefullight")!)
                    Link("GitHub Repository", destination: URL(string: "https://github.com/gracefullight/speak-smooth")!)
                }

                Divider()

                HStack {
                    Spacer()
                    Button("Done") {
                        if apiKeyInput == (settings.openRouterApiKey ?? "") || settings.saveAPIKey(apiKeyInput) {
                            dismiss()
                        }
                    }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 460, idealWidth: 500, minHeight: 580, idealHeight: 640)
        .onAppear {
            bringWindowToFront()
        }
        .task {
            apiKeyInput = settings.openRouterApiKey ?? ""
            remindersManager.refreshAuthorizationStatus()
            if remindersManager.isAuthorized {
                await loadLists()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task {
                remindersManager.refreshAuthorizationStatus()
                if remindersManager.isAuthorized { await loadLists() }
            }
        }
    }

    private func saveAPIKey() {
        apiKeySaved = settings.saveAPIKey(apiKeyInput)
    }

    private var listPicker: some View {
        Picker("List", selection: Binding<String>(
            get: { settings.selectedReminderListId ?? "" },
            set: { id in
                settings.selectedReminderListId = id.isEmpty ? nil : id
                settings.selectedReminderListName = reminderLists.first { $0.id == id }?.displayName
            }
        )) {
            Text("Select a list").tag("")
            ForEach(reminderLists) { list in
                Text(list.displayName).tag(list.id)
            }
        }
        .labelsHidden()
        .disabled(isLoadingLists || reminderLists.isEmpty)
    }

    private func requestRemindersAccess() async {
        do {
            try await remindersManager.requestAccess()
            remindersErrorMessage = nil
            showOpenPrivacySettingsButton = false
            await loadLists()
        } catch {
            remindersErrorMessage = error.localizedDescription
            if case .openSystemSettingsRequired = (error as? RemindersError) {
                showOpenPrivacySettingsButton = true
            } else {
                showOpenPrivacySettingsButton = false
            }
        }
    }

    private func loadLists() async {
        isLoadingLists = true
        defer { isLoadingLists = false }

        do {
            reminderLists = try remindersManager.fetchReminderLists()
            remindersErrorMessage = nil
            showOpenPrivacySettingsButton = false
            if
                let selectedId = settings.selectedReminderListId,
                !reminderLists.contains(where: { $0.id == selectedId })
            {
                settings.selectedReminderListId = nil
                settings.selectedReminderListName = nil
            } else if let selectedId = settings.selectedReminderListId {
                settings.selectedReminderListName = reminderLists.first { $0.id == selectedId }?.displayName
            }
        } catch {
            remindersErrorMessage = error.localizedDescription
            if case .openSystemSettingsRequired = (error as? RemindersError) {
                showOpenPrivacySettingsButton = true
            } else {
                showOpenPrivacySettingsButton = false
            }
        }
    }

    private func bringWindowToFront() {
        NSApp.activate(ignoringOtherApps: true)
        guard let window = NSApp.windows.first(where: { $0.title == "Settings" }) else {
            return
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
