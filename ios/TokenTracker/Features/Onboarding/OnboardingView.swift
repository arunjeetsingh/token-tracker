import SwiftUI
import SafariServices

/// First-launch onboarding for a provider API key. Three steps:
///
/// 1. Welcome + "why we need this".
/// 2. Open the provider console (in-app Safari) to create a key.
/// 3. Paste key (with clipboard auto-detect) → save.
///
/// The view does not own the credential; it asks `onSubmit` to persist + verify.
struct OnboardingView: View {
    /// Called when the user submits a key. Throwing means the caller surfaced
    /// an error (e.g. API auth failed) — view stays put so the user can edit.
    var onSubmit: (String) async -> Result<Void, Error>

    @State private var pendingKey: String = ""
    @State private var clipboardSuggestion: String?
    @State private var safariURL: SafariURL?
    @State private var isSubmitting = false
    @State private var submitError: String?
    @State private var revealKey = false
    @State private var selectedProvider: ProviderSetup = .openAI

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                providerPicker
                header
                steps
                pasteCard
                submitButton
                footer
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .navigationTitle("Connect Provider")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: detectClipboard)
        .sheet(item: $safariURL) { wrapper in
            SafariView(url: wrapper.url)
                .ignoresSafeArea()
                .onDisappear { detectClipboard() }
        }
    }

    // MARK: - sections

    private var providerPicker: some View {
        Picker("Provider", selection: $selectedProvider) {
            ForEach(ProviderSetup.allCases) { provider in
                Text(provider.displayName).tag(provider)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Usage provider")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "key.horizontal.fill")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
            Text("One-time setup")
                .font(.largeTitle.bold())
            Text(selectedProvider.introText)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepCard(
                number: 1,
                title: selectedProvider.organizationTitle,
                detail: selectedProvider.organizationDetail,
                action: AnyView(
                    Button {
                        safariURL = SafariURL(url: selectedProvider.organizationURL)
                    } label: {
                        Label(selectedProvider.organizationButtonTitle, systemImage: "building.2")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                )
            )
            stepCard(
                number: 2,
                title: selectedProvider.adminKeysTitle,
                detail: selectedProvider.adminKeysDetail,
                action: AnyView(
                    Button {
                        safariURL = SafariURL(url: selectedProvider.adminKeysURL)
                    } label: {
                        Label(selectedProvider.adminKeysButtonTitle, systemImage: "safari")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                )
            )
            stepCard(
                number: 3,
                title: selectedProvider.createKeyTitle,
                detail: selectedProvider.createKeyDetail
            )
            stepCard(
                number: 4,
                title: "Copy the key",
                detail: selectedProvider.copyKeyDetail
            )
        }
    }

    @ViewBuilder
    private var pasteCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Paste your key")
                .font(.headline)

            if let suggestion = clipboardSuggestion, pendingKey.isEmpty {
                Button {
                    pendingKey = suggestion
                    clipboardSuggestion = nil
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.on.clipboard.fill")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Detected key on clipboard")
                                .font(.subheadline.weight(.medium))
                            Text(AnthropicKeyValidation.masked(suggestion))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("Tap to use")
                            .font(.caption)
                            .foregroundStyle(.tint)
                    }
                    .padding(12)
                    .background(.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                Group {
                    if revealKey {
                        TextField(selectedProvider.keyPlaceholder, text: $pendingKey)
                    } else {
                        SecureField(selectedProvider.keyPlaceholder, text: $pendingKey)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.done)

                Button {
                    revealKey.toggle()
                } label: {
                    Image(systemName: revealKey ? "eye.slash" : "eye")
                }
                .accessibilityLabel(revealKey ? "Hide key" : "Show key")
            }

            if let submitError {
                Text(submitError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(.top, 4)
    }

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            HStack {
                if isSubmitting { ProgressView().tint(.white) }
                Text(isSubmitting ? "Connecting…" : "Save & Connect")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!canSubmit)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Stored in the iOS Keychain on this device only.", systemImage: "lock.shield")
            Label("Never synced to iCloud. You can disconnect anytime in Settings.", systemImage: "icloud.slash")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 8)
    }

    // MARK: - helpers

    private var trimmedKey: String {
        pendingKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        // App Reviewer Demo Mode short-circuit: the magic review key is
        // intentionally shorter than `AnthropicKeyValidation.minLength`, so
        // without this branch the "Save & Connect" button would stay disabled
        // and reviewers could never activate Demo Mode.
        !isSubmitting && (
            DemoMode.isReviewKey(trimmedKey) ||
            trimmedKey.count >= AnthropicKeyValidation.minLength
        )
    }

    private func detectClipboard() {
        guard pendingKey.isEmpty else { return }
        let pasteboard = UIPasteboard.general
        // Don't trigger the system pasteboard banner unnecessarily — only peek
        // when there's a plausible string.
        guard pasteboard.hasStrings, let candidate = pasteboard.string else {
            clipboardSuggestion = nil
            return
        }
        clipboardSuggestion = AnthropicKeyValidation.looksLikeAnthropicKey(candidate) ? candidate : nil
    }

    private func submit() async {
        submitError = nil
        isSubmitting = true
        defer { isSubmitting = false }
        let result = await onSubmit(trimmedKey)
        switch result {
        case .success:
            pendingKey = ""
        case .failure(let error):
            submitError = error.localizedDescription
        }
    }

    private func stepCard(number: Int, title: String, detail: String, action: AnyView? = nil) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(.tint.opacity(0.15))
                Text("\(number)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.tint)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(.init(detail))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let action {
                    action.padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private enum ProviderSetup: String, CaseIterable, Identifiable {
    case openAI
    case anthropic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI: return "OpenAI"
        case .anthropic: return "Anthropic"
        }
    }

    var introText: String {
        switch self {
        case .openAI:
            return "TokenCounter reads usage from OpenAI's Usage API. We need a one-time API key — takes about 30 seconds. It stays on this device only."
        case .anthropic:
            return "TokenCounter reads usage from Anthropic's Admin API. We need a one-time admin key — takes about 30 seconds. It stays on this device only."
        }
    }

    var organizationTitle: String {
        switch self {
        case .openAI: return "Make sure billing is enabled"
        case .anthropic: return "Make sure you have an organization"
        }
    }

    var organizationDetail: String {
        switch self {
        case .openAI:
            return "OpenAI usage data is available from your platform organization. Tap the button to check your project and billing settings before continuing."
        case .anthropic:
            return "Admin keys are only available on **organizational** Anthropic accounts. Tap the button to open the Organization settings page — if it says you're not in one yet, create one before continuing (it's free and takes a minute)."
        }
    }

    var organizationButtonTitle: String {
        switch self {
        case .openAI: return "Check OpenAI Settings"
        case .anthropic: return "Check Organization"
        }
    }

    var organizationURL: URL {
        switch self {
        case .openAI:
            return URL(string: "https://platform.openai.com/settings/organization/billing/overview")!  // swiftlint:disable:this force_unwrapping
        case .anthropic:
            return URL(string: "https://console.anthropic.com/settings/organization")!  // swiftlint:disable:this force_unwrapping
        }
    }

    var adminKeysTitle: String {
        switch self {
        case .openAI: return "Open the OpenAI API Keys page"
        case .anthropic: return "Open the Admin Keys page"
        }
    }

    var adminKeysDetail: String {
        switch self {
        case .openAI:
            return "Tap the button to open platform.openai.com inside this app. You'll land directly on the API Keys page."
        case .anthropic:
            return "Tap the button to open console.anthropic.com inside this app. You'll land directly on the Admin Keys page."
        }
    }

    var adminKeysButtonTitle: String {
        switch self {
        case .openAI: return "Open OpenAI API Keys"
        case .anthropic: return "Open Admin Keys"
        }
    }

    var adminKeysURL: URL {
        switch self {
        case .openAI:
            return URL(string: "https://platform.openai.com/api-keys")!  // swiftlint:disable:this force_unwrapping
        case .anthropic:
            return URL(string: "https://console.anthropic.com/settings/admin-keys")!  // swiftlint:disable:this force_unwrapping
        }
    }

    var createKeyTitle: String {
        switch self {
        case .openAI: return "Create an API key"
        case .anthropic: return "Create an Admin key"
        }
    }

    var createKeyDetail: String {
        switch self {
        case .openAI:
            return "Tap **Create new secret key**. Name it “TokenCounter”. OpenAI keys usually start with `sk-proj-…` or `sk-…`."
        case .anthropic:
            return "Tap **+ Create admin key**. Name it “TokenCounter”. (Admin keys are different from regular API keys — they start with `sk-ant-admin…` instead of `sk-ant-api…`.)"
        }
    }

    var copyKeyDetail: String {
        switch self {
        case .openAI:
            return "Tap **Copy**. Come back here and we'll auto-detect it from your clipboard."
        case .anthropic:
            return "Tap **Copy**. Come back here and we'll auto-detect it from your clipboard."
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .openAI: return "sk-proj-…"
        case .anthropic: return "sk-ant-admin…"
        }
    }
}

/// Identifiable wrapper around `URL` so we can drive `.sheet(item:)` from any
/// of the provider setup deep links the onboarding flow exposes.
struct SafariURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// Wraps `SFSafariViewController` so we can present provider setup pages
/// without leaving the app.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let controller = SFSafariViewController(url: url, configuration: config)
        controller.preferredControlTintColor = nil
        controller.dismissButtonStyle = .done
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
