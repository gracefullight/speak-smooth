import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    @State private var todoLists: [TodoList] = []
    @State private var isLoadingLists = false
    @State private var apiKeyInput = ""

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
                    Text("Microsoft Account")
                        .font(.headline)

                    if authManager.isSignedIn {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(authManager.accountName ?? "Signed in")
                            Spacer()
                            Button("Sign Out") {
                                try? authManager.signOut()
                            }
                        }
                    } else {
                        Button("Sign In with Microsoft") {
                            Task { try? await authManager.signIn() }
                        }
                    }
                }

                if authManager.isSignedIn {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("To Do List")
                                .font(.headline)
                            Spacer()
                            if isLoadingLists {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                        }

                        Picker("List", selection: $settings.selectedTodoListId) {
                            Text("Select a list").tag(String?.none)
                            ForEach(todoLists) { list in
                                Text(list.displayName).tag(Optional(list.id))
                            }
                        }
                        .labelsHidden()
                        .onChange(of: settings.selectedTodoListId) { _, newValue in
                            settings.selectedTodoListName = todoLists.first { $0.id == newValue }?.displayName
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
        .task {
            apiKeyInput = settings.openRouterApiKey ?? ""
            if authManager.isSignedIn {
                await loadLists()
            }
        }
    }

    private func loadLists() async {
        isLoadingLists = true
        defer { isLoadingLists = false }
        let client = TodoClient { try await authManager.getAccessToken() }
        do {
            todoLists = try await client.fetchTodoLists()
        } catch {
            print("Failed to load lists: \(error)")
        }
    }
}
