package studio.maximumimpact.tokencounter.providers.anthropic

import java.math.BigDecimal
import java.math.RoundingMode

/**
 * Static pricing table for Claude models. Kotlin sibling of the iOS
 * `ModelPricing` (ios/TokenTracker/Providers/Anthropic/ModelPricing.swift).
 *
 * Used to estimate intra-day cost from the `usage_report/messages` endpoint,
 * since `cost_report` only emits buckets *after* the UTC day closes (so it lags
 * by up to 24h). All rates are USD per **million tokens**, mirroring Anthropic's
 * published pricing page.
 *
 * IMPORTANT: this is a best-effort estimate. The authoritative number is the
 * `cost_report` total — once a day closes the estimate for that day is
 * discarded and replaced with the API value, so minor drift here only affects
 * today's running estimate, never historical totals.
 */
data class ModelPricing(
    /** USD per 1M base (uncached) input tokens. */
    val inputUSDPerMTok: BigDecimal,
    /** USD per 1M tokens for 5-minute cache *writes*. */
    val cacheWrite5mUSDPerMTok: BigDecimal,
    /** USD per 1M tokens for 1-hour cache *writes*. */
    val cacheWrite1hUSDPerMTok: BigDecimal,
    /** USD per 1M tokens for cache *reads* / hits / refreshes. */
    val cacheReadUSDPerMTok: BigDecimal,
    /** USD per 1M output tokens. */
    val outputUSDPerMTok: BigDecimal
) {
    companion object {
        // --- Canonical pricing constants (USD / 1M tokens) ---

        /** Opus 4.5, 4.6, 4.7 — current high-tier pricing. */
        val OPUS_4_5 = ModelPricing(
            inputUSDPerMTok = BigDecimal("5"),
            cacheWrite5mUSDPerMTok = BigDecimal("6.25"),
            cacheWrite1hUSDPerMTok = BigDecimal("10"),
            cacheReadUSDPerMTok = BigDecimal("0.50"),
            outputUSDPerMTok = BigDecimal("25")
        )

        /** Opus 4.0/4.1 — legacy high-tier pricing. */
        val OPUS_4_1 = ModelPricing(
            inputUSDPerMTok = BigDecimal("15"),
            cacheWrite5mUSDPerMTok = BigDecimal("18.75"),
            cacheWrite1hUSDPerMTok = BigDecimal("30"),
            cacheReadUSDPerMTok = BigDecimal("1.50"),
            outputUSDPerMTok = BigDecimal("75")
        )

        /** Sonnet 4.x and 3.5 Sonnet. */
        val SONNET_4 = ModelPricing(
            inputUSDPerMTok = BigDecimal("3"),
            cacheWrite5mUSDPerMTok = BigDecimal("3.75"),
            cacheWrite1hUSDPerMTok = BigDecimal("6"),
            cacheReadUSDPerMTok = BigDecimal("0.30"),
            outputUSDPerMTok = BigDecimal("15")
        )

        /** Haiku 4.5. */
        val HAIKU_4_5 = ModelPricing(
            inputUSDPerMTok = BigDecimal("1"),
            cacheWrite5mUSDPerMTok = BigDecimal("1.25"),
            cacheWrite1hUSDPerMTok = BigDecimal("2"),
            cacheReadUSDPerMTok = BigDecimal("0.10"),
            outputUSDPerMTok = BigDecimal("5")
        )

        /** Haiku 3.5 (Bedrock/Vertex only since retirement). */
        val HAIKU_3_5 = ModelPricing(
            inputUSDPerMTok = BigDecimal("0.80"),
            cacheWrite5mUSDPerMTok = BigDecimal("1"),
            cacheWrite1hUSDPerMTok = BigDecimal("1.60"),
            cacheReadUSDPerMTok = BigDecimal("0.08"),
            outputUSDPerMTok = BigDecimal("4")
        )

        /**
         * Verified against the published pricing page on 2026-05-24. Keys are
         * *prefixes* matched longest-first. Add new entries here as Anthropic
         * ships new models.
         */
        val TABLE: List<Pair<String, ModelPricing>> = listOf(
            // Opus 4.5+ family ($5 / $25 + cache tiers)
            "claude-opus-4-7" to OPUS_4_5,
            "claude-opus-4-6" to OPUS_4_5,
            "claude-opus-4-5" to OPUS_4_5,
            // Older Opus 4 (deprecated, still in cost history)
            "claude-opus-4-1" to OPUS_4_1,
            "claude-opus-4" to OPUS_4_1,
            // Sonnet family ($3 / $15)
            "claude-sonnet-4" to SONNET_4,
            "claude-3-5-sonnet" to SONNET_4,
            // Haiku family
            "claude-haiku-4-5" to HAIKU_4_5,
            "claude-3-5-haiku" to HAIKU_3_5,
            "claude-3-opus" to OPUS_4_1
        )

        /**
         * Returns pricing for the given API-reported model id, matching by
         * longest matching prefix so `claude-opus-4-7` doesn't fall through to
         * `claude-opus-4`. Null when no prefix matches (caller treats the model
         * as unpriced).
         */
        fun lookup(model: String): ModelPricing? {
            var best: Pair<Int, ModelPricing>? = null
            for ((prefix, pricing) in TABLE) {
                if (model.startsWith(prefix) && (best == null || prefix.length > best!!.first)) {
                    best = prefix.length to pricing
                }
            }
            return best?.second
        }
    }
}

/** Token counts for one (model, time-bucket) row from `usage_report/messages`. */
data class TokenUsage(
    val uncachedInputTokens: Long = 0,
    val cacheWrite5mTokens: Long = 0,
    val cacheWrite1hTokens: Long = 0,
    val cacheReadTokens: Long = 0,
    val outputTokens: Long = 0
) {
    operator fun plus(other: TokenUsage): TokenUsage = TokenUsage(
        uncachedInputTokens = uncachedInputTokens + other.uncachedInputTokens,
        cacheWrite5mTokens = cacheWrite5mTokens + other.cacheWrite5mTokens,
        cacheWrite1hTokens = cacheWrite1hTokens + other.cacheWrite1hTokens,
        cacheReadTokens = cacheReadTokens + other.cacheReadTokens,
        outputTokens = outputTokens + other.outputTokens
    )

    /**
     * Cost = sum over each lane of (tokens / 1M) × USD/MTok, as an exact
     * [BigDecimal] in dollars. We multiply tokens × rate first and divide by
     * 1M once at the end to keep the arithmetic exact (no per-lane rounding).
     */
    fun cost(pricing: ModelPricing): BigDecimal {
        val product = BigDecimal(uncachedInputTokens).multiply(pricing.inputUSDPerMTok)
            .add(BigDecimal(cacheWrite5mTokens).multiply(pricing.cacheWrite5mUSDPerMTok))
            .add(BigDecimal(cacheWrite1hTokens).multiply(pricing.cacheWrite1hUSDPerMTok))
            .add(BigDecimal(cacheReadTokens).multiply(pricing.cacheReadUSDPerMTok))
            .add(BigDecimal(outputTokens).multiply(pricing.outputUSDPerMTok))
        return product.divide(MTOK, 10, RoundingMode.HALF_EVEN)
    }

    companion object {
        val Zero = TokenUsage()
        private val MTOK = BigDecimal(1_000_000)
    }
}
