import SwiftUI

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @State private var pendingKey: String = ""

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Token Tracker")
                .toolbar {
                    if case .loaded = viewModel.state {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                Task { await viewModel.refresh() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .accessibilityLabel("Refresh")
                        }
                    }
                }
        }
        .task { await viewModel.bootstrap() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView().scaleEffect(1.4)
        case .needsCredentials:
            credentialsForm
        case .loaded(let amount, let asOf, let orgName):
            loadedView(amount: amount, asOf: asOf, orgName: orgName)
        case .failed(let message):
            errorView(message: message)
        }
    }

    private var credentialsForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Anthropic admin API key")
                .font(.headline)
            Text("Required to read your org's usage & cost. Stored in the iOS Keychain on this device only.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            SecureField("***", text: $pendingKey)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button {
                let trimmed = pendingKey.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                Task {
                    await viewModel.save(apiKey: trimmed)
                    pendingKey = ""
                }
            } label: {
                Text("Save & connect").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(pendingKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
    }

    private func loadedView(amount: Money, asOf: Date, orgName: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Text(orgName)
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            Text(amount.formatted())
                .font(.system(size: 64, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text("Month to date · as of \(asOf, style: .time)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Couldn’t load")
                .font(.headline)
            Text(message)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Retry") { Task { await viewModel.refresh() } }
                .buttonStyle(.bordered)
        }
        .padding()
    }
}

#Preview {
    DashboardView()
}
