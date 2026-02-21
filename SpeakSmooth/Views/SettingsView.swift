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
                            Button("Refresh Lists") {
                                Task { await loadLists() }
                            }
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

                        Picker("List", selection: $settings.selectedReminderListId) {
                            Text("Select a list").tag(String?.none)
                            ForEach(reminderLists) { list in
                                Text(list.displayName).tag(Optional(list.id))
                            }
                        }
                        .labelsHidden()
                        .onChange(of: settings.selectedReminderListId) { _, newValue in
                            settings.selectedReminderListName = reminderLists.first { $0.id == newValue }?.displayName
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("OpenRouter API Key")
                        .font(.headline)
                    Text("Optional. Used as LLM fallback when Apple Intelligence is unavailable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField("sk-or-...", text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            settings.openRouterApiKey = apiKeyInput.isEmpty ? nil : apiKeyInput
                        }
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Sponsors")
                        .font(.headline)
                    Text("If this project helped you, please consider buying me a coffee!")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Link("Buy Me A Coffee", destination: URL(string: "https://www.buymeacoffee.com/gracefullight")!)
                    Link("GitHub Repository", destination: URL(string: "https://github.com/gracefullight/speak-smooth")!)

                    Text("Or leave a star:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("gh api --method PUT /user/starred/gracefullight/pkgs")
                        .font(.caption.monospaced())
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }

                Divider()

                HStack {
                    Spacer()
                    Button("Done") { dismiss() }
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
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.title == "Settings" }) else {
            return
        }
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
