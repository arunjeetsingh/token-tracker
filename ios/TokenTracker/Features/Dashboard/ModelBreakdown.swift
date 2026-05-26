import SwiftUI

/// Top-3 models by month-to-date cost. Pass the full list; the view picks
/// the top 3 and renders them in iOS Settings-style rows (name on the
/// left, dollars on the right, 1pt separator between).
///
/// Empty list -> renders nothing (no header, no placeholder). 1 or 2
/// entries -> renders only what's there.
struct ModelBreakdown: View {
    /// Full list of models sorted descending by cost. `AnthropicClient`
    /// returns them that way; the view re-sorts defensively so a
    /// caller-side mistake doesn't show a wrong order.
    let models: [ModelSpend]

    /// How many rows to show. Default 3; exposed for previews / tests.
    var topN: Int = 3

    private var topModels: [ModelSpend] {
        models
            .sorted { $0.cost.cents > $1.cost.cents }
            .prefix(topN)
            .map { $0 }
    }

    var body: some View {
        if topModels.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Top models")
                    .font(.caption)
                    .textCase(.uppercase)
                    .kerning(0.5)
                    .foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    ForEach(Array(topModels.enumerated()), id: \.offset) { idx, model in
                        row(for: model)
                        if idx < topModels.count - 1 {
                            Divider()
                                .background(Color(.separator))
                        }
                    }
                }
            }
        }
    }

    private func row(for model: ModelSpend) -> some View {
        HStack {
            Text(model.displayName)
                .font(.body)
                .foregroundStyle(.primary)
            Spacer(minLength: 12)
            Text(model.cost.formatted())
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    let demo: [ModelSpend] = [
        .init(modelId: "claude-opus-4-5",   displayName: "Claude Opus 4.5",   cost: Money(cents: 284_700)),
        .init(modelId: "claude-sonnet-4-5", displayName: "Claude Sonnet 4.5", cost: Money(cents: 156_200)),
        .init(modelId: "claude-haiku-4-5",  displayName: "Claude Haiku 4.5",  cost: Money(cents: 75_100)),
        .init(modelId: "claude-3-5-sonnet", displayName: "Claude Sonnet 3.5", cost: Money(cents: 12_400))
    ]
    return VStack(spacing: 24) {
        ModelBreakdown(models: demo).padding()
        ModelBreakdown(models: Array(demo.prefix(2))).padding()
        ModelBreakdown(models: []).padding()
    }
}
