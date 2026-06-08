package studio.maximumimpact.tokencounter.features.dashboard

import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.LocalDate

class SpendLimitTest {

    @Test
    fun progressFraction_isClampedAndGuardsZeroLimit() {
        assertEquals(0.5f, SpendLimit.progressFraction(50_000, 100_000), 0.0001f)
        // Over the limit clamps to a full bar.
        assertEquals(1f, SpendLimit.progressFraction(150_000, 100_000), 0.0001f)
        // Zero / negative limit can't divide → empty bar, no crash.
        assertEquals(0f, SpendLimit.progressFraction(50_000, 0), 0.0001f)
    }

    @Test
    fun percentUsed_isNotCapped() {
        assertEquals(50, SpendLimit.percentUsed(50_000, 100_000))
        assertEquals(150, SpendLimit.percentUsed(150_000, 100_000))
        assertEquals(0, SpendLimit.percentUsed(50_000, 0))
    }

    @Test
    fun severity_crossesAt80And100Percent() {
        assertEquals(SpendLimit.Severity.NORMAL, SpendLimit.severity(50_000, 100_000))
        assertEquals(SpendLimit.Severity.APPROACHING, SpendLimit.severity(85_000, 100_000))
        assertEquals(SpendLimit.Severity.OVER, SpendLimit.severity(100_000, 100_000))
        assertEquals(SpendLimit.Severity.OVER, SpendLimit.severity(120_000, 100_000))
        assertEquals(SpendLimit.Severity.NORMAL, SpendLimit.severity(120_000, 0))
    }

    @Test
    fun severity_usesRawRatioNotRoundedPercent() {
        // 79.5% rounds to 80 for display but must NOT flip to APPROACHING.
        assertEquals(SpendLimit.Severity.NORMAL, SpendLimit.severity(79_500, 100_000))
        // Exactly 80% is APPROACHING.
        assertEquals(SpendLimit.Severity.APPROACHING, SpendLimit.severity(80_000, 100_000))
        // 99.5% rounds to 100 for display but must stay APPROACHING, not OVER.
        assertEquals(SpendLimit.Severity.APPROACHING, SpendLimit.severity(99_500, 100_000))
        // Exactly 100% is OVER.
        assertEquals(SpendLimit.Severity.OVER, SpendLimit.severity(100_000, 100_000))
    }

    @Test
    fun nextResetDate_isFirstOfFollowingMonth() {
        assertEquals(LocalDate.of(2026, 7, 1), SpendLimit.nextResetDate(LocalDate.of(2026, 6, 6)))
        // Year rollover.
        assertEquals(LocalDate.of(2027, 1, 1), SpendLimit.nextResetDate(LocalDate.of(2026, 12, 15)))
    }
}
