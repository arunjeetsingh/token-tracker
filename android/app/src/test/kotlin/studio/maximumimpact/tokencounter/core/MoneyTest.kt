package studio.maximumimpact.tokencounter.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.math.BigDecimal

/**
 * Locks the [Money] contract: whole-cent storage, addition, parsing from the
 * Anthropic cents string, dollar rounding, and USD formatting.
 *
 * The default [Money.formatted] uses `Locale.US` deliberately so the dollar
 * figure renders identically to the iOS screenshots regardless of where the
 * device's locale is set.
 */
class MoneyTest {

    @Test
    fun formatted_rendersUsdWithThousandsAndCents() {
        assertEquals("$7,632.30", Money(763_230).formatted())
        assertEquals("$0.00", Money.Zero.formatted())
        assertEquals("$312.88", Money(312_88).formatted())
        assertEquals("$7,319.42", Money(731_942).formatted())
    }

    @Test
    fun plus_addsCents() {
        assertEquals(Money(763_230), Money(731_942) + Money(312_88))
    }

    @Test
    fun fromAnthropicCentsString_truncatesSubCentFractionsTowardZero() {
        // Despite the "USD" label, the value is *cents*. "2013.9595" -> 2013¢.
        assertEquals(Money(2013), Money.fromAnthropicCentsString("2013.9595"))
        assertEquals(Money(100), Money.fromAnthropicCentsString("100"))
        // Half a cent truncates to zero.
        assertEquals(Money(0), Money.fromAnthropicCentsString("0.5"))
        assertEquals(Money(0), Money.fromAnthropicCentsString("0"))
    }

    @Test
    fun fromAnthropicCentsString_returnsNullForNonNumbers() {
        assertNull(Money.fromAnthropicCentsString("not-a-number"))
        assertNull(Money.fromAnthropicCentsString(""))
    }

    @Test
    fun fromDollars_roundsToNearestCentWithBankersRounding() {
        assertEquals(Money(1981), Money.fromDollars(BigDecimal("19.8093")))
        // Banker's rounding: .005 -> nearest even cent.
        assertEquals(Money(0), Money.fromDollars(BigDecimal("0.005")))
        assertEquals(Money(2), Money.fromDollars(BigDecimal("0.015")))
        assertEquals(Money(312_88), Money.fromDollars(BigDecimal("312.88")))
    }

    @Test
    fun dollars_exposesExactDecimal() {
        assertEquals(0, Money(763_230).dollars.compareTo(BigDecimal("7632.30")))
    }
}
