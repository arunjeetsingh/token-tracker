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
                HStack(spacing: 8) {
                    if DemoMode.isEnabled {
                        demoPill
                    }
                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh")
                }
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

    // Small, understated "DEMO" indicator so reviewers (and ourselves)
    // can see at a glance that the dashboard is showing canned data.
    // Apple wants transparency, not a billboard — hence caption2 + pill.
    private var demoPill: some View {
        Text("DEMO")
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.2))
            .foregroundStyle(.orange)
            .clipShape(Capsule())
            .accessibilityLabel("Demo mode")
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
        case .loaded(let report, let orgName):
            loadedView(report: report, orgName: orgName)
        case .failed(let message):
            errorView(message: message)
        }
    }

    private func loadedView(report: MTDCost, orgName: String) -> some View {
        // Layout intent: hero (org pill + big number + intraday note) sits
        // slightly above visual center; sparkline + top-models stack fills
        // the space below. This is deliberate — PR #23's screenshot showed
        // "mostly empty space"; ADR-011 explains why we fill it.
        VStack(spacing: 16) {
            Spacer(minLength: 16)
            VStack(spacing: 12) {
                Text(orgName)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(report.total.formatted())
                    .font(.system(size: 64, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("Month to date · as of \(report.asOf, style: .time)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if report.hasTodayEstimate {
                    Text("Includes ~\(report.todayEstimatedCost.formatted()) estimated for today")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if report.hasUnpricedModels {
                    Text("⚠️ Estimate excludes: \(report.unpricedModels.joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }
            VStack(spacing: 24) {
                if !report.dailySpend.isEmpty {
                    Sparkline(data: report.dailySpend)
                }
                if !report.modelBreakdown.isEmpty {
                    ModelBreakdown(models: report.modelBreakdown)
                }
            }
            .padding(.horizontal)
            Spacer(minLength: 24)
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
