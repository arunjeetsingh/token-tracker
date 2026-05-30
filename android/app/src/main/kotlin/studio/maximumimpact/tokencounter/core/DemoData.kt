package studio.maximumimpact.tokencounter.core

import java.time.LocalDate
import java.time.LocalDateTime

/**
 * Canned month-to-date report for UI demonstration / screenshots. Mirrors the
 * iOS `DemoMode.snapshot()` (ios/TokenTracker/Core/DemoMode.swift) value-for-
 * value so the two platforms render the same numbers:
 *   - finalized daily spend sums to $7,319.42
 *   - today's estimate is $312.88
 *   - hero total (finalized + today) is $7,632.30
 *   - top-3 models split ~55% / 30% / 15% of the finalized total
 *   - org name "Personal"
 *
 * No network, no keys — purely local sample data while the real data layer is
 * still to come (see ADR-013).
 */
object DemoData {

    /** Magic key a reviewer can paste in onboarding to enter demo mode. */
    const val REVIEW_KEY = "sk-ant-demo-2026-05-w22"

    /**
     * Returns true if [candidate], after trimming whitespace/newlines and
     * lowercasing, equals [REVIEW_KEY]. Case-insensitive because mobile
     * keyboards love to autocorrect/auto-capitalize pasted strings. Mirrors
     * iOS `DemoMode.isReviewKey`.
     */
    fun isReviewKey(candidate: String): Boolean {
        val normalized = candidate.trim().lowercase()
        return normalized.isNotEmpty() && normalized == REVIEW_KEY
    }

    /** 30 days of canned daily spend in cents — noisy but trending up. */
    private val dailyCents = longArrayOf(
        10_523, 11_247, 12_891, 9_856, 14_203, 15_672, 13_941, 16_808, 18_234, 17_456,
        19_872, 21_034, 20_156, 22_890, 24_561, 23_445, 26_012, 27_889, 25_678, 29_234,
        31_456, 30_123, 32_890, 34_567, 33_245, 35_678, 37_234, 36_012, 38_901, 40_234
    )

    data class Snapshot(val orgName: String, val report: MtdCost)

    fun snapshot(today: LocalDate = LocalDate.now(), now: LocalDateTime = LocalDateTime.now()): Snapshot {
        val todayEstimate = Money(312_88)

        val daily = dailyCents.mapIndexed { idx, c ->
            // Last element maps to `today`; earlier elements walk backwards.
            val date = today.minusDays((dailyCents.size - 1 - idx).toLong())
            DailySpend(date = date, cost = Money(c))
        }

        val finalizedSum = dailyCents.sum()
        val finalized = Money(finalizedSum)

        // Top-3 models: ~55% / 30% / 15%. Use integer cent arithmetic and give
        // the rounding remainder to the largest bucket so the three sum exactly
        // to the finalized total (matches the iOS implementation).
        val opusCents = (finalizedSum * 0.55).toLong()
        val sonnetCents = (finalizedSum * 0.30).toLong()
        val haikuCents = (finalizedSum * 0.15).toLong()
        val remainder = finalizedSum - (opusCents + sonnetCents + haikuCents)
        val modelBreakdown = listOf(
            ModelSpend("claude-opus-4-5", "Claude Opus 4.5", Money(opusCents + remainder)),
            ModelSpend("claude-sonnet-4-5", "Claude Sonnet 4.5", Money(sonnetCents)),
            ModelSpend("claude-haiku-4-5", "Claude Haiku 4.5", Money(haikuCents))
        )

        val report = MtdCost(
            finalizedCost = finalized,
            todayEstimatedCost = todayEstimate,
            unpricedModels = emptyList(),
            finalizedThrough = today,
            asOf = now,
            dailySpend = daily,
            modelBreakdown = modelBreakdown
        )
        return Snapshot(orgName = "Personal", report = report)
    }
}
