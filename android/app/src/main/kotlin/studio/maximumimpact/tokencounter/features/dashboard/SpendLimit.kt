package studio.maximumimpact.tokencounter.features.dashboard

import java.time.LocalDate
import kotlin.math.roundToInt

/**
 * Pure helpers for the spend-limit gauge — kept free of Compose/Android so they
 * can be unit-tested directly.
 */
object SpendLimit {

    /** Where the bar sits, as a fraction in 0f..1f. Zero/invalid limit → 0f. */
    fun progressFraction(spentCents: Long, limitCents: Long): Float {
        if (limitCents <= 0L) return 0f
        return (spentCents.toFloat() / limitCents.toFloat()).coerceIn(0f, 1f)
    }

    /** Percent of the limit used, rounded. NOT capped — can exceed 100. */
    fun percentUsed(spentCents: Long, limitCents: Long): Int {
        if (limitCents <= 0L) return 0
        return (spentCents.toDouble() / limitCents.toDouble() * 100.0).roundToInt()
    }

    /** Visual severity for the gauge, driven by how close spend is to the limit. */
    enum class Severity { NORMAL, APPROACHING, OVER }

    /**
     * APPROACHING at >= 80% of the limit, OVER at >= 100%. Compares the raw
     * ratio (not the rounded [percentUsed]) so a value just under a threshold —
     * e.g. 79.5% or 99.5% — doesn't cross early via display rounding.
     */
    fun severity(spentCents: Long, limitCents: Long): Severity {
        if (limitCents <= 0L) return Severity.NORMAL
        val ratio = spentCents.toDouble() / limitCents.toDouble()
        return when {
            ratio >= 1.0 -> Severity.OVER
            ratio >= 0.8 -> Severity.APPROACHING
            else -> Severity.NORMAL
        }
    }

    /**
     * When the monthly window rolls over: the 1st of the month after [today].
     * Spend is month-to-date, so the gauge "resets" at the next month boundary.
     */
    fun nextResetDate(today: LocalDate): LocalDate =
        today.withDayOfMonth(1).plusMonths(1)
}
