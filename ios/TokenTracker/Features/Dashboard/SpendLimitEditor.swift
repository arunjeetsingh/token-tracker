import SwiftUI

/// Sheet for setting the on-device monthly spend-limit *target*. The copy is
/// explicit that this changes only what TokenCounter tracks against — not the
/// real Anthropic limit (Console-only). Swift sibling of the Android
/// `SpendLimitDialog`.
struct SpendLimitEditor: View {
    let currentCents: Int64?
    var onSave: (Int64) -> Void
    var onClear: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(currentCents: Int64?, onSave: @escaping (Int64) -> Void, onClear: @escaping () -> Void) {
        self.currentCents = currentCents
        self.onSave = onSave
        self.onClear = onClear
        _text = State(initialValue: currentCents.map { Self.dollarsString(fromCents: $0) } ?? "")
    }

    private var parsedCents: Int64? { Self.parseDollarsToCents(text) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("$")
                            .foregroundStyle(.secondary)
                        TextField("1,400", text: $text)
                            .keyboardType(.decimalPad)
                    }
                } footer: {
                    Text("TokenCounter tracks your spend against this target on this device. It doesn't change your actual Anthropic limit — change that in the Console.")
                }

                if currentCents != nil {
                    Section {
                        Button("Remove limit", role: .destructive) {
                            onClear()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(currentCents == nil ? "Set spend limit" : "Edit spend limit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        if let cents = parsedCents {
                            onSave(cents)
                            dismiss()
                        }
                    }
                    .disabled(parsedCents == nil)
                }
            }
        }
    }

    /// "$1,400" / "1400.50" / "1,400" → cents. Nil when blank or not positive.
    static func parseDollarsToCents(_ input: String) -> Int64? {
        let cleaned = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        guard !cleaned.isEmpty, let dollars = Decimal(string: cleaned), dollars > 0 else { return nil }
        return Money.fromDollars(dollars).cents
    }

    private static func dollarsString(fromCents cents: Int64) -> String {
        let dollars = Decimal(cents) / 100
        return NSDecimalNumber(decimal: dollars).stringValue
    }
}
