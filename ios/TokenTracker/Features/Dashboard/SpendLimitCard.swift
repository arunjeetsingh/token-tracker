import SwiftUI

/// Spend-limit gauge shown on the loaded dashboard. Swift sibling of the
/// Android `SpendLimitCard`: renders real MTD spend against the user's local
/// target, with a near/over warning, or a "Set limit" prompt when unset.
struct SpendLimitCard: View {
    let report: MTDCost
    let limitCents: Int64?
    var onAdjust: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let limit = limitCents {
                gauge(limitCents: limit)
            } else {
                prompt
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var prompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Set a monthly spend limit")
                .font(.headline)
            Text("Track your spend against a target and get a heads-up as you approach it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Set limit", action: onAdjust)
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func gauge(limitCents limit: Int64) -> some View {
        let spent = report.total.cents
        let fraction = SpendLimit.progressFraction(spentCents: spent, limitCents: limit)
        let percent = SpendLimit.percentUsed(spentCents: spent, limitCents: limit)
        let severity = SpendLimit.severity(spentCents: spent, limitCents: limit)
        let tint = color(for: severity)

        HStack(alignment: .firstTextBaseline) {
            Text("\(report.total.formatted()) spent")
                .font(.body.weight(.medium))
                .monospacedDigit()
            Spacer()
            Text("\(percent)% used")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        ProgressView(value: fraction)
            .tint(tint)

        HStack {
            Text("\(Money(cents: limit).formatted()) monthly limit")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("Resets \(SpendLimit.nextResetDate(after: report.finalizedThrough).formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if severity != .normal {
            Text(severity == .over ? "Over your monthly limit" : "Approaching your monthly limit")
                .font(.caption.weight(.medium))
                .foregroundStyle(tint)
        }

        HStack {
            Spacer()
            Button("Adjust limit", action: onAdjust)
        }
    }

    private func color(for severity: SpendLimit.Severity) -> Color {
        switch severity {
        case .over: return .red
        case .approaching: return .orange
        case .normal: return .accentColor
        }
    }
}
