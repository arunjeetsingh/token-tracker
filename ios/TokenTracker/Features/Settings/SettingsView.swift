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
    var onConnect: (String) async -> Result<Void, Error>
    var onDisconnect: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showConfirm = false
    @State private var showLimitEditor = false
    @State private var showCredentialSetup = false
    @State private var isWorking = false

    private static let anthropicLimitsURL = URL(string: "https://platform.claude.com/settings/limits")!
    private static let anthropicBillingURL = URL(string: "https://platform.claude.com/settings/billing")!
    private static let openAILimitsURL = URL(string: "https://platform.openai.com/settings/organization/limits")!
    private static let openAIBillingURL = URL(string: "https://platform.openai.com/settings/organization/billing/overview")!

    var body: some View {
        NavigationStack {
            Form {
                Section("Provider API key") {
                    LabeledContent("Provider", value: providerName)
                    LabeledContent("Organization", value: orgName ?? "—")
                    LabeledContent("API key", value: maskedKey ?? "Not set")
                        .font(.body.monospaced())

                    Button {
                        showCredentialSetup = true
                    } label: {
                        Label(maskedKey == nil ? "Add API key" : "Add or replace API key", systemImage: "key")
                    }
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

                    Link("Change limit in provider console", destination: limitsURL)
                } header: {
                    Text("Spend limit")
                } footer: {
                    Text(spendLimitCents == nil
                        ? "Set a monthly limit to track your spend and enable 90% alerts."
                        : "Limit is tracked on this device — editing here doesn't change your actual provider limit. Alerts check in the background and notify you once when spend reaches 90%.")
                }

                Section {
                    Link("Credit balance & auto-reload", destination: billingURL)
                } header: {
                    Text("Billing")
                } footer: {
                    Text("Billing and auto-reload settings live in the provider console; the usage APIs don't expose them.")
                }

                Section {
                    Button(role: .destructive) {
                        showConfirm = true
                    } label: {
                        HStack {
                            if isWorking { ProgressView() }
                            Text("Remove API key")
                        }
                    }
                    .disabled(isWorking || maskedKey == nil)
                } footer: {
                    Text("Removes the API key from this device's Keychain. You'll need to paste it again to reconnect.")
                }

                Section("About") {
                    LabeledContent("App", value: appVersion)
                    Link("Provider API Keys", destination: providerKeysURL)
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
            .sheet(isPresented: $showCredentialSetup) {
                NavigationStack {
                    OnboardingView(onSubmit: { key in
                        let result = await onConnect(key)
                        if case .success = result {
                            showCredentialSetup = false
                        }
                        return result
                    })
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Cancel") { showCredentialSetup = false }
                        }
                    }
                }
            }
            .confirmationDialog(
                "Remove the saved API key?",
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
                Text("Your API key will be removed from this device. The key itself is not revoked — you can revoke it in the provider console.")
            }
        }
    }

    private var providerName: String {
        switch providerKind {
        case .anthropic: return "Anthropic"
        case .openAI: return "OpenAI"
        case .none: return "Not connected"
        }
    }

    private var providerKind: ProviderKind? {
        guard let maskedKey else { return nil }
        return TokenTracker.providerKind(for: maskedKey)
    }

    private var limitsURL: URL {
        providerKind == .anthropic ? Self.anthropicLimitsURL : Self.openAILimitsURL
    }

    private var billingURL: URL {
        providerKind == .anthropic ? Self.anthropicBillingURL : Self.openAIBillingURL
    }

    private var providerKeysURL: URL {
        switch providerKind {
        case .anthropic:
            return URL(string: "https://console.anthropic.com/settings/admin-keys")!
        case .openAI, .none:
            return URL(string: "https://platform.openai.com/settings/organization/admin-keys")!
        }
    }

    private var limitText: String {
        guard let cents = spendLimitCents else { return "Not set" }
        return Money(cents: cents).formatted()
    }

    /// Toggling on requests notification permission; we only persist
    /// `enabled = true` once it's granted. Scheduling/cancelling the background
    /// check is driven off the opt-in flag in `DashboardView.onChange`, so it
    /// also reacts when clearing the limit turns the alert off.
    private var alertBinding: Binding<Bool> {
        Binding(
            get: { spendAlertEnabled },
            set: { wantOn in
                if !wantOn {
                    onAlertEnabledChange(false)
                    return
                }
                Task {
                    if await SpendAlertNotifier.requestAuthorization() {
                        onAlertEnabledChange(true)
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
