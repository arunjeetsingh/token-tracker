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
                .safeAreaInset(edge: .bottom, alignment: .center) {
                    // Only show the studio footer once the user has gotten
                    // past onboarding. While they're entering a key the
                    // footer would just be visual noise.
                    if viewModel.state != .needsCredentials {
                        studioFooter
                    }
                }
        }
        .task {
            await viewModel.bootstrap()
            await viewModel.autoRefreshLoop()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(
                maskedKey: viewModel.maskedKey,
                orgName: viewModel.state.orgName,
                onDisconnect: { await viewModel.disconnect() }
            )
        }
    }

    private var navigationTitle: String {
        viewModel.state == .needsCredentials ? "" : "TokenCounter"
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        // Settings + Refresh are visible from the moment the dashboard chrome
        // is showing, including during the very first load when the body is
        // still a spinner. Refresh is disabled while loading or refreshing
        // (and the button itself doubles as the progress indicator so the
        // user has a single, predictable place to look for "is it doing
        // anything"). Hidden only during onboarding, where they'd be moot.
        if viewModel.state != .needsCredentials {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 8) {
                    if DemoMode.isEnabled {
                        demoPill
                    }
                    refreshButton
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

    /// Refresh button that morphs into an inline progress indicator while a
    /// refresh is in flight (either the initial load or a manual tap).
    /// The user always sees *some* affordance in the toolbar slot, so there
    /// is no "did anything happen?" gap after tapping.
    private var refreshButton: some View {
        Button {
            Task { await viewModel.refresh() }
        } label: {
            if isBusy {
                ProgressView()
                    // ProgressView() defaults to ~22pt; nudge to match the
                    // 17pt SF Symbol weight of the idle state so the toolbar
                    // doesn't jump.
                    .controlSize(.small)
            } else {
                Image(systemName: "arrow.clockwise")
            }
        }
        .disabled(isBusy)
        .accessibilityLabel(isBusy ? "Refreshing" : "Refresh")
    }

    /// Either the first-ever load (state == .loading) or a manual refresh
    /// while the dashboard has cached data on screen (isRefreshing == true).
    /// `.idle` is a transient pre-bootstrap state and shouldn't count as
    /// busy from a user-facing perspective, but the refresh button is also
    /// hidden then because state == .needsCredentials hides the whole
    /// toolbar group.
    private var isBusy: Bool {
        viewModel.state == .loading || viewModel.isRefreshing
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

    /// Tappable "from maximumimpact.studio" line that lives at the bottom of
    /// the screen. Replaces the old top-of-dashboard org pill. Hidden during
    /// onboarding (no point branding an empty key form).
    private var studioFooter: some View {
        // Use the SwiftUI Link API rather than a custom Button so the system
        // applies the standard tap target + URL handling. The font is small
        // enough to read as a footer credit; the secondary color keeps it
        // from competing with the headline number.
        Link(destination: URL(string: "https://maximumimpact.studio")!) {
            Text("from maximumimpact.studio")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 8)
        .accessibilityLabel("Open maximumimpact.studio")
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
        // Layout intent: hero (org name + big number + intraday note) sits
        // slightly above visual center; chart + top-models stack fills the
        // space below. The studio attribution footer lives in safeAreaInset
        // and is separate from this hero.
        VStack(spacing: 16) {
            Spacer(minLength: 16)
            VStack(spacing: 12) {
                Text(orgName)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                AnimatedMoneyGauge(total: report.total, orgName: orgName)
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
                    SpendBarChart(data: report.dailySpend)
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

private struct AnimatedMoneyGauge: View {
    let total: Money
    let orgName: String

    @State private var needleProgress = 0.12

    private var restingProgress: Double {
        let dollars = max(0, Double(truncating: total.dollars as NSDecimalNumber))
        let scaled = min(log10(dollars + 1) / 4.0, 1)
        return 0.1 + (scaled * 0.8)
    }

    var body: some View {
        ZStack {
            SpeedometerArc(progress: 1)
                .stroke(
                    Color.secondary.opacity(0.22),
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
            SpeedometerArc(progress: needleProgress)
                .stroke(
                    Color.accentColor.opacity(0.86),
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
            SpeedometerNeedle(progress: needleProgress)
                .stroke(
                    Color.accentColor.opacity(0.68),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
            SpeedometerCap()
                .fill(Color.accentColor.opacity(0.82))

            Text(total.formatted())
                .font(.system(size: 64, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .contentTransition(.numericText(value: Double(total.cents)))
                .frame(maxWidth: 292)
                .offset(y: 28)
        }
        .frame(width: 308, height: 154)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Month to date, \(total.formatted()), for \(orgName)")
        .onAppear {
            needleProgress = restingProgress
        }
        .onChange(of: total.cents) {
            animateNeedleChange()
        }
    }

    private func animateNeedleChange() {
        let target = restingProgress
        withAnimation(.easeOut(duration: 0.24)) {
            needleProgress = 0.96
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 240_000_000)
            withAnimation(.spring(response: 0.46, dampingFraction: 0.62)) {
                needleProgress = target
            }
        }
    }
}

private struct SpeedometerArc: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width * 0.43, rect.height - 18)
        let center = CGPoint(x: rect.midX, y: rect.maxY - 12)
        let sweep = 130 * max(0, min(progress, 1))
        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(205),
            endAngle: .degrees(205 + sweep),
            clockwise: false
        )
        return path
    }
}

private struct SpeedometerNeedle: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width * 0.43, rect.height - 18)
        let center = CGPoint(x: rect.midX, y: rect.maxY - 12)
        let angle = Angle.degrees(205 + (130 * max(0, min(progress, 1)))).radians
        let tip = CGPoint(
            x: center.x + CGFloat(cos(angle)) * radius * 0.78,
            y: center.y + CGFloat(sin(angle)) * radius * 0.78
        )
        var path = Path()
        path.move(to: center)
        path.addLine(to: tip)
        return path
    }
}

private struct SpeedometerCap: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.maxY - 12)
        let cap = CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)
        return Path(ellipseIn: cap)
    }
}
