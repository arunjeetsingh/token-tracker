import Foundation

/// Static pricing table for Claude models. Used to estimate intra-day cost
/// from the `usage_report/messages` endpoint, since the `cost_report` endpoint
/// only emits buckets *after* the UTC day closes (so it lags by up to 24h).
///
/// All rates are USD per **million tokens**, mirroring Anthropic's published
/// pricing page (<https://platform.claude.com/docs/en/about-claude/pricing>).
///
/// IMPORTANT: This is a best-effort estimate. The authoritative number is the
/// `cost_report` total — once a day closes, the estimate for that day is
/// discarded and replaced with the API value. So minor drift in this table
/// only affects today's running estimate, not historical totals.
struct ModelPricing: Equatable {
    /// USD per 1M base (uncached) input tokens.
    let inputUSDPerMTok: Decimal
    /// USD per 1M tokens for 5-minute cache *writes*.
    let cacheWrite5mUSDPerMTok: Decimal
    /// USD per 1M tokens for 1-hour cache *writes*.
    let cacheWrite1hUSDPerMTok: Decimal
    /// USD per 1M tokens for cache *reads* / hits / refreshes.
    let cacheReadUSDPerMTok: Decimal
    /// USD per 1M output tokens.
    let outputUSDPerMTok: Decimal

    /// Verified against the published pricing page on 2026-05-24.
    /// Keys are *prefixes* matched longest-first. Add new entries here as
    /// Anthropic ships new models.
    static let table: [(prefix: String, pricing: ModelPricing)] = [
        // Opus 4.5+ family ($5 / $25 + cache tiers)
        ("claude-opus-4-7", opus4_5),
        ("claude-opus-4-6", opus4_5),
        ("claude-opus-4-5", opus4_5),
        // Older Opus 4 (deprecated, still in cost history)
        ("claude-opus-4-1", opus4_1),
        ("claude-opus-4",   opus4_1),
        // Sonnet family ($3 / $15)
        ("claude-sonnet-4", sonnet4),
        ("claude-3-5-sonnet", sonnet4),
        // Haiku family
        ("claude-haiku-4-5", haiku4_5),
        ("claude-3-5-haiku", haiku3_5),
        ("claude-3-opus",   opus4_1)
    ]

    /// Returns pricing for the given API-reported model id, matching by
    /// longest matching prefix so `claude-opus-4-7` doesn't fall through to
    /// `claude-opus-4`.
    static func lookup(_ model: String) -> ModelPricing? {
        var best: (Int, ModelPricing)?
        for entry in table where model.hasPrefix(entry.prefix) {
            if best == nil || entry.prefix.count > best!.0 {
                best = (entry.prefix.count, entry.pricing)
            }
        }
        return best?.1
    }

    // MARK: - Canonical pricing constants (USD / 1M tokens)

    /// Opus 4.5, 4.6, 4.7 — current high-tier pricing.
    static let opus4_5 = ModelPricing(
        inputUSDPerMTok: 5,
        cacheWrite5mUSDPerMTok: Decimal(string: "6.25")!, // swiftlint:disable:this force_unwrapping
        cacheWrite1hUSDPerMTok: 10,
        cacheReadUSDPerMTok: Decimal(string: "0.50")!, // swiftlint:disable:this force_unwrapping
        outputUSDPerMTok: 25
    )

    /// Opus 4.0/4.1 — legacy high-tier pricing.
    static let opus4_1 = ModelPricing(
        inputUSDPerMTok: 15,
        cacheWrite5mUSDPerMTok: Decimal(string: "18.75")!, // swiftlint:disable:this force_unwrapping
        cacheWrite1hUSDPerMTok: 30,
        cacheReadUSDPerMTok: Decimal(string: "1.50")!, // swiftlint:disable:this force_unwrapping
        outputUSDPerMTok: 75
    )

    /// Sonnet 4.x and 3.5 Sonnet.
    static let sonnet4 = ModelPricing(
        inputUSDPerMTok: 3,
        cacheWrite5mUSDPerMTok: Decimal(string: "3.75")!, // swiftlint:disable:this force_unwrapping
        cacheWrite1hUSDPerMTok: 6,
        cacheReadUSDPerMTok: Decimal(string: "0.30")!, // swiftlint:disable:this force_unwrapping
        outputUSDPerMTok: 15
    )

    /// Haiku 4.5.
    static let haiku4_5 = ModelPricing(
        inputUSDPerMTok: 1,
        cacheWrite5mUSDPerMTok: Decimal(string: "1.25")!, // swiftlint:disable:this force_unwrapping
        cacheWrite1hUSDPerMTok: 2,
        cacheReadUSDPerMTok: Decimal(string: "0.10")!, // swiftlint:disable:this force_unwrapping
        outputUSDPerMTok: 5
    )

    /// Haiku 3.5 (Bedrock/Vertex only since retirement).
    static let haiku3_5 = ModelPricing(
        inputUSDPerMTok: Decimal(string: "0.80")!, // swiftlint:disable:this force_unwrapping
        cacheWrite5mUSDPerMTok: 1,
        cacheWrite1hUSDPerMTok: Decimal(string: "1.60")!, // swiftlint:disable:this force_unwrapping
        cacheReadUSDPerMTok: Decimal(string: "0.08")!, // swiftlint:disable:this force_unwrapping
        outputUSDPerMTok: 4
    )
}

/// Token counts for one (model, time-bucket) row from `usage_report/messages`.
struct TokenUsage: Equatable {
    var uncachedInputTokens: Int
    var cacheWrite5mTokens: Int
    var cacheWrite1hTokens: Int
    var cacheReadTokens: Int
    var outputTokens: Int

    static let zero = TokenUsage(
        uncachedInputTokens: 0, cacheWrite5mTokens: 0, cacheWrite1hTokens: 0,
        cacheReadTokens: 0, outputTokens: 0
    )

    static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(
            uncachedInputTokens: lhs.uncachedInputTokens + rhs.uncachedInputTokens,
            cacheWrite5mTokens:  lhs.cacheWrite5mTokens  + rhs.cacheWrite5mTokens,
            cacheWrite1hTokens:  lhs.cacheWrite1hTokens  + rhs.cacheWrite1hTokens,
            cacheReadTokens:     lhs.cacheReadTokens     + rhs.cacheReadTokens,
            outputTokens:        lhs.outputTokens        + rhs.outputTokens
        )
    }

    /// Cost = sum over each lane of (tokens / 1M) × USD/MTok. Decimal math —
    /// no Float, no Double, no surprises.
    func cost(at pricing: ModelPricing) -> Decimal {
        let mtok = Decimal(1_000_000)
        return (Decimal(uncachedInputTokens) / mtok) * pricing.inputUSDPerMTok
             + (Decimal(cacheWrite5mTokens)  / mtok) * pricing.cacheWrite5mUSDPerMTok
             + (Decimal(cacheWrite1hTokens)  / mtok) * pricing.cacheWrite1hUSDPerMTok
             + (Decimal(cacheReadTokens)     / mtok) * pricing.cacheReadUSDPerMTok
             + (Decimal(outputTokens)        / mtok) * pricing.outputUSDPerMTok
    }
}
