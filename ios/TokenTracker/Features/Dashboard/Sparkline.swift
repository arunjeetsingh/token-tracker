import SwiftUI

/// Stocks-app-style minimalist sparkline. No axes, no labels, no dots.
/// Pure line. Stateless — give it `[DailySpend]`, get a chart.
///
/// Width: whatever the parent gives us. Height: 80pt.
/// Y-scale: auto-fit min..max with 5% headroom above max so the line never
/// kisses the top edge.
struct Sparkline: View {
    let data: [DailySpend]

    /// Caller can override for testing or non-default looks. Default matches
    /// iOS systemBlue — the app's existing accent.
    var stroke: Color = Color(red: 0, green: 122/255, blue: 1.0)
    var lineWidth: CGFloat = 2.5
    var height: CGFloat = 80

    var body: some View {
        VStack(spacing: 4) {
            chart
                .frame(height: height)
            Text("Last 30 days")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var chart: some View {
        if data.count < 2 {
            // Empty / single-point: render a soft placeholder, don't crash.
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.tertiarySystemFill))
                .accessibilityLabel("Sparkline unavailable")
        } else {
            GeometryReader { geo in
                Path { path in
                    let points = Self.points(for: data, in: geo.size)
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(stroke, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Last 30 days spend trend")
        }
    }

    /// Maps `data` to CGPoints inside `size`. Y is inverted (SwiftUI's
    /// origin is top-left). 5% headroom above max so the line never
    /// touches the top edge.
    static func points(for data: [DailySpend], in size: CGSize) -> [CGPoint] {
        guard data.count >= 2 else { return [] }
        let costs = data.map { Double($0.cost.cents) }
        let minV = costs.min() ?? 0
        let maxV = costs.max() ?? 0
        // Add 5% headroom above max so the line breathes; if the series is
        // flat (max == min), invent a tiny range so we render mid-height
        // instead of a divide-by-zero.
        let range = max(maxV - minV, 1) * 1.05
        let stepX = data.count > 1 ? size.width / CGFloat(data.count - 1) : 0
        return data.enumerated().map { idx, point in
            let x = CGFloat(idx) * stepX
            let normalized = (Double(point.cost.cents) - minV) / range
            // 4pt top inset so the stroke radius doesn't clip on the top edge.
            let topInset: CGFloat = 4
            let usableHeight = size.height - topInset
            let y = size.height - CGFloat(normalized) * usableHeight
            return CGPoint(x: x, y: y)
        }
    }
}

#Preview {
    let cal = Calendar(identifier: .gregorian)
    let now = Date()
    let demo: [DailySpend] = (0..<30).map { i in
        let day = cal.date(byAdding: .day, value: -29 + i, to: now)!
        // Generally rising + a little noise.
        let base = 8_000 + i * 1_100
        let noise = Int.random(in: -1_500...1_500)
        return DailySpend(date: day, cost: Money(cents: Int64(max(base + noise, 1_000))))
    }
    return VStack {
        Sparkline(data: demo).padding()
        Sparkline(data: []).padding()
    }
}
