import SwiftUI

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(viewModel.state == .needsCredentials ? .inline : .large)
                .toolbar { toolbar }
        }
        .task { await viewModel.bootstrap() }
        .sheet(isPresented: $showSettings) {
            SettingsView(
                maskedKey: viewModel.maskedKey,
                orgName: viewModel.state.orgName,
                onDisconnect: { await viewModel.disconnect() }
            )
        }
    }

    private var navigationTitle: String {
        viewModel.state == .needsCredentials ? "" : "Token Counter"
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if viewModel.state.isLoaded {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh")
            }
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView().scaleEffect(1.4)
        case .needsCredentials:
            OnboardingView(onSubmit: { key in
                await viewModel.connect(using: key)
            })
        case .loaded(let amount, let asOf, let orgName):
            loadedView(amount: amount, asOf: asOf, orgName: orgName)
        case .failed(let message):
            errorView(message: message)
        }
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
            HStack {
                Button("Retry") { Task { await viewModel.refresh() } }
                    .buttonStyle(.bordered)
                Button("Disconnect", role: .destructive) {
                    Task { await viewModel.disconnect() }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
    }
}

#Preview {
    DashboardView()
}
