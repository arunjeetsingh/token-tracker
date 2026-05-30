package studio.maximumimpact.tokencounter.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate

/**
 * Pins the canned demo report to the exact same numbers the iOS
 * `DemoMode.snapshot()` produces, so screenshots line up 1:1 across the two
 * platforms. If these change, the iOS sibling must change in lockstep.
 */
class DemoDataTest {

    private val snapshot = DemoData.snapshot(today = LocalDate.of(2026, 5, 29))
    private val report = snapshot.report

    @Test
    fun orgName_isPersonal() {
        assertEquals("Personal", snapshot.orgName)
    }

    @Test
    fun finalizedAndEstimate_matchIos() {
        assertEquals(Money(731_942), report.finalizedCost)
        assertEquals("$7,319.42", report.finalizedCost.formatted())
        assertEquals(Money(312_88), report.todayEstimatedCost)
        assertEquals("$312.88", report.todayEstimatedCost.formatted())
    }

    @Test
    fun heroTotal_is7632Point30() {
        assertEquals(Money(763_230), report.total)
        assertEquals("$7,632.30", report.total.formatted())
        assertTrue(report.hasTodayEstimate)
    }

    @Test
    fun dailySpend_has30DaysSortedEndingToday() {
        assertEquals(30, report.dailySpend.size)
        // Chronological: each day is strictly after the previous.
        val dates = report.dailySpend.map { it.date }
        assertEquals(dates.sorted(), dates)
        assertEquals(LocalDate.of(2026, 5, 29), report.dailySpend.last().date)
        // Daily spend sums exactly to the finalized total.
        assertEquals(731_942L, report.dailySpend.sumOf { it.cost.cents })
    }

    @Test
    fun modelBreakdown_topThreeSumToFinalizedWithRemainderToLargest() {
        assertEquals(3, report.modelBreakdown.size)
        assertEquals(
            report.finalizedCost.cents,
            report.modelBreakdown.sumOf { it.cost.cents }
        )
        // 55 / 30 / 15 split, remainder (1¢) folded into the largest bucket.
        assertEquals("Claude Opus 4.5", report.modelBreakdown[0].displayName)
        assertEquals(Money(402_569), report.modelBreakdown[0].cost)
        assertEquals(Money(219_582), report.modelBreakdown[1].cost)
        assertEquals(Money(109_791), report.modelBreakdown[2].cost)
        // Sorted descending.
        val costs = report.modelBreakdown.map { it.cost.cents }
        assertEquals(costs.sortedDescending(), costs)
    }

    @Test
    fun reviewKey_isStable() {
        assertEquals("sk-ant-demo-2026-05-w22", DemoData.REVIEW_KEY)
    }

    @Test
    fun noUnpricedModels() {
        assertTrue(report.unpricedModels.isEmpty())
        assertTrue(!report.hasUnpricedModels)
    }
}
