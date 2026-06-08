package studio.maximumimpact.tokencounter.notifications

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate

class SpendAlertTest {

    @Test
    fun atThreshold_trueAtOrAbove90Percent() {
        assertFalse(SpendAlert.atThreshold(89_999, 100_000))
        assertTrue(SpendAlert.atThreshold(90_000, 100_000))
        assertTrue(SpendAlert.atThreshold(100_000, 100_000))
        assertTrue(SpendAlert.atThreshold(150_000, 100_000))
    }

    @Test
    fun atThreshold_guardsZeroLimit() {
        assertFalse(SpendAlert.atThreshold(90_000, 0))
        assertFalse(SpendAlert.atThreshold(90_000, -5))
    }

    @Test
    fun monthKey_isYearMonth() {
        assertEquals("2026-06", SpendAlert.monthKey(LocalDate.of(2026, 6, 6)))
        assertEquals("2026-12", SpendAlert.monthKey(LocalDate.of(2026, 12, 31)))
    }
}
