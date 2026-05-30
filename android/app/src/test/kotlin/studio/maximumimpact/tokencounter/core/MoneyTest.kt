package studio.maximumimpact.tokencounter.core

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Locks the [Money] contract: whole-cent storage, addition, and USD
 * formatting that matches the iOS demo screenshots.
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
}
