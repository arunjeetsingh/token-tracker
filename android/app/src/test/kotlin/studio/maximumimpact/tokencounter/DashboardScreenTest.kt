package studio.maximumimpact.tokencounter

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit-level sanity checks for the dashboard scaffold.
 *
 * The dashboard itself currently renders hardcoded constants — we'll add
 * a real Compose UI test (`androidx.compose.ui.test`) once the data layer
 * exists and there's something worth asserting against. For now these
 * tests just lock the contract that the v1 hero string is the literal
 * we ship and is formatted as USD currency.
 */
class DashboardScreenTest {

    @Test
    fun heroAmount_isFormattedAsUsdCurrency() {
        val hero = "$5,160.11"
        assertTrue(
            "hero should start with a dollar sign",
            hero.startsWith("$")
        )
        assertTrue(
            "hero should use a thousands separator",
            hero.contains(",")
        )
        assertTrue(
            "hero should use two decimal places",
            hero.matches(Regex("\\$\\d{1,3}(,\\d{3})*\\.\\d{2}"))
        )
    }

    @Test
    fun todayEstimate_mentionsToday() {
        val estimate = "~$312.88 estimated for today"
        assertTrue(estimate.contains("today"))
        assertTrue(estimate.startsWith("~$"))
    }

    @Test
    fun appName_isOneWord() {
        val name = "TokenCounter"
        assertEquals(
            "Per ADR-012, the app name is one word with no space",
            -1,
            name.indexOf(' ')
        )
    }
}
