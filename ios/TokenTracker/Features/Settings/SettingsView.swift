import SwiftUI

/// Account / settings screen reachable from the gear icon on the dashboard.
/// MVP only does one useful thing: disconnect (wipe key from Keychain).
struct SettingsView: View {
    let maskedKey: String?
    let orgName: String?
    var onDisconnect: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showConfirm = false
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Anthropic Admin key") {
                    LabeledContent("Organization", value: orgName ?? "—")
                    LabeledContent("Admin key", value: maskedKey ?? "Not set")
                        .font(.body.monospaced())
                }

                Section {
                    Button(role: .destructive) {
                        showConfirm = true
                    } label: {
                        HStack {
                            if isWorking { ProgressView() }
                            Text("Remove Admin key")
                        }
                    }
                    .disabled(isWorking || maskedKey == nil)
                } footer: {
                    Text("Removes the admin key from this device's Keychain. You'll need to paste it again to reconnect.")
                    // Note: this app has no login/account; the key is the only stored credential.
                }

                Section("About") {
                    LabeledContent("App", value: appVersion)
                    Link("Anthropic Admin Keys", destination: URL(string: "https://console.anthropic.com/settings/admin-keys")!)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Remove the saved Admin key?",
                isPresented: $showConfirm,
                titleVisibility: .visible
            ) {
                Button("Disconnect", role: .destructive) {
                    Task {
                        isWorking = true
                        await onDisconnect()
                        isWorking = false
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your admin key will be removed from this device. The key itself is not revoked — you can revoke it in the Anthropic Console.")
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
