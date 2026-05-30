package studio.maximumimpact.tokencounter.providers.anthropic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.math.BigDecimal

/**
 * Pins the pricing table to the iOS values and verifies longest-prefix lookup
 * and the per-lane cost arithmetic.
 */
class ModelPricingTest {

    @Test
    fun lookup_prefersLongestPrefix() {
        // Exact current-gen ids resolve to the current high-tier price.
        assertEquals(ModelPricing.OPUS_4_5, ModelPricing.lookup("claude-opus-4-7"))
        assertEquals(ModelPricing.OPUS_4_5, ModelPricing.lookup("claude-opus-4-5"))
        // Opus 4.8 must price at the current Opus rate, NOT longest-prefix
        // fall through to legacy "claude-opus-4" ($15/$75) — a 3x overstatement.
        assertEquals(ModelPricing.OPUS_4_5, ModelPricing.lookup("claude-opus-4-8-20260115"))
        // 4-1 must NOT fall through to the shorter "claude-opus-4" entry.
        assertEquals(ModelPricing.OPUS_4_1, ModelPricing.lookup("claude-opus-4-1-20250805"))
        // Bare "claude-opus-4" + date suffix -> legacy Opus.
        assertEquals(ModelPricing.OPUS_4_1, ModelPricing.lookup("claude-opus-4-20250101"))
        assertEquals(ModelPricing.SONNET_4, ModelPricing.lookup("claude-sonnet-4-5"))
        assertEquals(ModelPricing.SONNET_4, ModelPricing.lookup("claude-3-5-sonnet-20241022"))
        assertEquals(ModelPricing.HAIKU_4_5, ModelPricing.lookup("claude-haiku-4-5"))
        assertEquals(ModelPricing.HAIKU_3_5, ModelPricing.lookup("claude-3-5-haiku-20241022"))
    }

    @Test
    fun lookup_returnsNullForUnknownModels() {
        assertNull(ModelPricing.lookup("gpt-4"))
        assertNull(ModelPricing.lookup(""))
    }

    @Test
    fun cost_isSumOfPerLaneRates() {
        // 1M input + 1M output on Opus 4.5 = $5 + $25 = $30.
        val usage = TokenUsage(uncachedInputTokens = 1_000_000, outputTokens = 1_000_000)
        assertEquals(0, usage.cost(ModelPricing.OPUS_4_5).compareTo(BigDecimal("30")))
    }

    @Test
    fun cost_handlesFractionalTokenAmounts() {
        // 12,345 output tokens × $25/MTok = 0.308625.
        val usage = TokenUsage(outputTokens = 12_345)
        assertEquals(0, usage.cost(ModelPricing.OPUS_4_5).compareTo(BigDecimal("0.308625")))
    }

    @Test
    fun cost_coversCacheLanes() {
        // 1M of each cache lane on Opus 4.5: 6.25 + 10 + 0.50 = 16.75.
        val usage = TokenUsage(
            cacheWrite5mTokens = 1_000_000,
            cacheWrite1hTokens = 1_000_000,
            cacheReadTokens = 1_000_000
        )
        assertEquals(0, usage.cost(ModelPricing.OPUS_4_5).compareTo(BigDecimal("16.75")))
    }

    @Test
    fun tokenUsage_addsLaneWise() {
        val a = TokenUsage(uncachedInputTokens = 10, outputTokens = 5)
        val b = TokenUsage(uncachedInputTokens = 1, cacheReadTokens = 3)
        val sum = a + b
        assertEquals(11, sum.uncachedInputTokens)
        assertEquals(5, sum.outputTokens)
        assertEquals(3, sum.cacheReadTokens)
    }
}
