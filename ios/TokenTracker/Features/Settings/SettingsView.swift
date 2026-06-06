import SwiftUI

/// Account / settings screen reachable from the gear icon on the dashboard.
/// Disconnect, the local spend-limit target + 90% alert opt-in, and Console
/// links for the billing data the Admin API can't expose.
struct SettingsView: View {
    let maskedKey: String?
    let orgName: String?
    let spendLimitCents: Int64?
    let spendAlertEnabled: Bool
    var onSetLimit: (Int64) -> Void
    var onClearLimit: () -> Void
    var onAlertEnabledChange: (Bool) -> Void
    var onDisconnect: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showConfirm = false
    @State private var showLimitEditor = false
    @State private var isWorking = false

    private static let limitsURL = URL(string: "https://platform.claude.com/settings/limits")!
    private static let billingURL = URL(string: "https://platform.claude.com/settings/billing")!

    var body: some View {
        NavigationStack {
            Form {
                Section("Anthropic Admin key") {
                    LabeledContent("Organization", value: orgName ?? "—")
                    LabeledContent("Admin key", value: maskedKey ?? "Not set")
                        .font(.body.monospaced())
                }

                Section {
                    Button {
                        showLimitEditor = true
                    } label: {
                        LabeledContent("Monthly limit", value: limitText)
                    }
                    .tint(.primary)

                    Toggle("Alert me at 90% of limit", isOn: alertBinding)
                        .disabled(spendLimitCents == nil)

                    Link("Change limit in Console", destination: Self.limitsURL)
                } header: {
                    Text("Spend limit")
                } footer: {
                    Text(spendLimitCents == nil
                        ? "Set a monthly limit to track your spend and enable 90% alerts."
                        : "Limit is tracked on this device — editing here doesn't change your actual Anthropic limit (do that in the Console). Alerts check in the background and notify you once when spend reaches 90%.")
                }

                Section {
                    Link("Credit balance & auto-reload", destination: Self.billingURL)
                } header: {
                    Text("Billing")
                } footer: {
                    Text("Credit balance and auto-reload live in the Anthropic Console; the API doesn't expose them.")
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
            .sheet(isPresented: $showLimitEditor) {
                SpendLimitEditor(
                    currentCents: spendLimitCents,
                    onSave: onSetLimit,
                    onClear: onClearLimit
                )
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

    private var limitText: String {
        guard let cents = spendLimitCents else { return "Not set" }
        return Money(cents: cents).formatted()
    }

    /// Toggling on requests notification permission and schedules the background
    /// check; we only persist `enabled = true` once permission is granted.
    private var alertBinding: Binding<Bool> {
        Binding(
            get: { spendAlertEnabled },
            set: { wantOn in
                if !wantOn {
                    onAlertEnabledChange(false)
                    SpendAlertScheduler.cancel()
                    return
                }
                Task {
                    if await SpendAlertNotifier.requestAuthorization() {
                        onAlertEnabledChange(true)
                        SpendAlertScheduler.schedule()
                    }
                }
            }
        )
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
