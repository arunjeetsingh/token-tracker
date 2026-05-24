import SwiftUI
import SafariServices

/// First-launch onboarding for the Anthropic admin key. Three steps:
///
/// 1. Welcome + "why we need this".
/// 2. Open Anthropic console (in-app Safari) to create a key.
/// 3. Paste key (with clipboard auto-detect) → save.
///
/// The view does not own the credential; it asks `onSubmit` to persist + verify.
struct OnboardingView: View {
    /// Called when the user submits a key. Throwing means the caller surfaced
    /// an error (e.g. API auth failed) — view stays put so the user can edit.
    var onSubmit: (String) async -> Result<Void, Error>

    @State private var pendingKey: String = ""
    @State private var clipboardSuggestion: String?
    @State private var showSafari = false
    @State private var isSubmitting = false
    @State private var submitError: String?
    @State private var revealKey = false

    private let consoleURL = URL(string: "https://console.anthropic.com/settings/keys")!  // swiftlint:disable:this force_unwrapping

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                steps
                pasteCard
                submitButton
                footer
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .navigationTitle("Connect Anthropic")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: detectClipboard)
        .sheet(isPresented: $showSafari) {
            SafariView(url: consoleURL)
                .ignoresSafeArea()
                .onDisappear { detectClipboard() }
        }
    }

    // MARK: - sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "key.horizontal.fill")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
            Text("One-time setup")
                .font(.largeTitle.bold())
            Text("Token Counter reads usage from Anthropic's Admin API. We need a one-time admin key — takes about 30 seconds. It stays on this device only.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepCard(
                number: 1,
                title: "Open Anthropic Console",
                detail: "Tap the button to sign in to console.anthropic.com inside this app.",
                action: AnyView(
                    Button {
                        showSafari = true
                    } label: {
                        Label("Open Console", systemImage: "safari")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                )
            )
            stepCard(
                number: 2,
                title: "Create an Admin key",
                detail: "Go to **Settings → API Keys → Admin Keys → Create Key**. Name it “Token Counter”."
            )
            stepCard(
                number: 3,
                title: "Copy the key",
                detail: "Tap **Copy**. It starts with `sk-ant-admin01-…` — come back here and we'll auto-detect it."
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
                        TextField("sk-ant-admin01-…", text: $pendingKey)
                    } else {
                        SecureField("sk-ant-admin01-…", text: $pendingKey)
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
        !isSubmitting && trimmedKey.count >= AnthropicKeyValidation.minLength
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

/// Wraps `SFSafariViewController` so we can present the Anthropic console
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
