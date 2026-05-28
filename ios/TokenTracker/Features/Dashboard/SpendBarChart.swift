import SwiftUI

/// Replacement for the line-only `Sparkline`. Renders the last ~30 days of
/// finalized daily spend as a tappable bar chart. Tapping a bar selects
/// that day and surfaces "Mon Apr 28 · $42.18" below the chart. Tapping
/// the same bar again clears the selection.
///
/// Design intent:
/// - Stateless on the data side. The selected index lives in `@State`
///   inside the chart; if the parent re-renders with a different `data`,
///   the selection is reset on a count change.
/// - No labels on the axes (consistent with the rest of the dashboard's
///   minimal aesthetic). The selection caption is the only label.
/// - Accessibility: each bar is an individually-focusable element with a
///   spoken label like "Tuesday April 28, $42.18". The chart container
///   itself summarizes "Last 30 days spend".
struct SpendBarChart: View {
    let data: [DailySpend]

    /// Bar height (the chart frame). Same as the old sparkline so the
    /// dashboard layout doesn't shift.
    var height: CGFloat = 80

    /// Tinted bar color. Defaults to iOS systemBlue to match the rest of
    /// the app. Selected bar uses the accent color at full opacity; the
    /// rest fade to 55%.
    var tint: Color = Color(red: 0, green: 122/255, blue: 1.0)

    @State private var selectedIndex: Int?

    var body: some View {
        VStack(spacing: 6) {
            chart
                .frame(height: height)
            caption
        }
        // Reset selection if the data series length changes underneath
        // us (e.g. a new month rolled over). Comparing counts is cheap
        // and sufficient — `data` is sorted chronologically and the
        // sliding 30-day window keeps things stable mid-month.
        .onChange(of: data.count) { _, _ in
            selectedIndex = nil
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Last 30 days spend")
    }

    @ViewBuilder
    private var chart: some View {
        if data.isEmpty {
            // No finalized days yet (brand new org, or month just rolled
            // over). Render a soft placeholder rather than nothing.
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.tertiarySystemFill))
                .accessibilityLabel("Spend chart unavailable")
        } else {
            GeometryReader { geo in
                let maxCents = max(Double(data.map(\.cost.cents).max() ?? 0), 1)
                let spacing: CGFloat = data.count > 14 ? 2 : 3
                let barWidth = (geo.size.width - spacing * CGFloat(data.count - 1)) / CGFloat(data.count)
                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(Array(data.enumerated()), id: \.offset) { idx, point in
                        bar(
                            for: point,
                            index: idx,
                            barWidth: max(barWidth, 1),
                            chartHeight: geo.size.height,
                            maxCents: maxCents
                        )
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
            }
        }
    }

    private func bar(
        for point: DailySpend,
        index: Int,
        barWidth: CGFloat,
        chartHeight: CGFloat,
        maxCents: Double
    ) -> some View {
        // Always give bars at least 2pt of height even on $0 days so the
        // chart's baseline reads as a chart and not as empty whitespace.
        let normalized = Double(point.cost.cents) / maxCents
        let h = max(CGFloat(normalized) * chartHeight, 2)
        let isSelected = selectedIndex == index
        return RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(tint.opacity(isSelected ? 1.0 : 0.55))
            .frame(width: barWidth, height: h)
            .contentShape(Rectangle())
            .onTapGesture {
                if selectedIndex == index {
                    selectedIndex = nil
                } else {
                    selectedIndex = index
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Self.accessibilityLabel(for: point))
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(isSelected ? "selected" : "")
    }

    @ViewBuilder
    private var caption: some View {
        if let idx = selectedIndex, data.indices.contains(idx) {
            let point = data[idx]
            HStack(spacing: 6) {
                Text(Self.captionDateFormatter.string(from: point.date))
                Text("·").foregroundStyle(.tertiary)
                Text(point.cost.formatted()).monospacedDigit()
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true) // bar already announces the same content
        } else {
            Text("Last 30 days · tap a bar for that day")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    // MARK: Formatters

    /// "Mon Apr 28" — short weekday and date, no year (the chart only
    /// covers the last ~30 days so year is unambiguous).
    static let captionDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return f
    }()

    /// "Tuesday April 28" — long form for VoiceOver.
    static let accessibilityDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("EEEE MMMM d")
        return f
    }()

    static func accessibilityLabel(for point: DailySpend) -> String {
        "\(accessibilityDateFormatter.string(from: point.date)), \(point.cost.formatted())"
    }
}

#Preview {
    let cal = Calendar(identifier: .gregorian)
    let now = Date()
    let demo: [DailySpend] = (0..<30).map { i in
        let day = cal.date(byAdding: .day, value: -29 + i, to: now)!
        let base = 8_000 + i * 1_100
        let noise = Int.random(in: -1_500...1_500)
        return DailySpend(date: day, cost: Money(cents: Int64(max(base + noise, 1_000))))
    }
    return VStack(spacing: 32) {
        SpendBarChart(data: demo).padding()
        SpendBarChart(data: []).padding()
    }
}
