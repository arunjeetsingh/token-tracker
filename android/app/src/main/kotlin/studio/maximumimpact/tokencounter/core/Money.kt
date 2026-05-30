package studio.maximumimpact.tokencounter.core

import java.text.NumberFormat
import java.util.Locale

/**
 * USD amount with cents precision. Kotlin sibling of the iOS `Money` struct
 * (see ios/TokenTracker/Core/Money.swift). Stores whole cents to avoid float
 * drift and formats as USD currency.
 *
 * We format with [Locale.US] (rather than the device locale) so the dollar
 * figure renders identically to the iOS demo screenshots regardless of where
 * the device is set — the data is USD-denominated by Anthropic either way.
 */
@JvmInline
value class Money(val cents: Long) {

    operator fun plus(other: Money): Money = Money(cents + other.cents)

    /** e.g. 763230 -> "$7,632.30". */
    fun formatted(locale: Locale = Locale.US): String {
        val formatter = NumberFormat.getCurrencyInstance(locale).apply {
            currency = java.util.Currency.getInstance("USD")
        }
        return formatter.format(cents / 100.0)
    }

    companion object {
        val Zero = Money(0)
    }
}
