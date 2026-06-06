package studio.maximumimpact.tokencounter.notifications

import java.time.LocalDate

/**
 * Pure decision logic for the spend alert — no Android deps, so it's unit
 * testable. The worker combines [atThreshold] with a once-per-[monthKey] dedupe.
 */
object SpendAlert {

    /** Fraction of the limit at which we notify. */
    const val THRESHOLD_FRACTION = 0.90

    /** True when spend has reached >= 90% of a positive limit. */
    fun atThreshold(spentCents: Long, limitCents: Long): Boolean {
        if (limitCents <= 0L) return false
        return spentCents.toDouble() / limitCents.toDouble() >= THRESHOLD_FRACTION
    }

    /** "yyyy-MM" used to dedupe alerts to at most once per calendar month. */
    fun monthKey(date: LocalDate): String = date.toString().substring(0, 7)
}
