package studio.maximumimpact.tokencounter.core

import java.math.BigDecimal
import java.math.RoundingMode
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

    /** Dollar value as an exact [BigDecimal] (cents / 100). */
    val dollars: BigDecimal get() = BigDecimal(cents).movePointLeft(2)

    /** e.g. 763230 -> "$7,632.30". */
    fun formatted(locale: Locale = Locale.US): String {
        val formatter = NumberFormat.getCurrencyInstance(locale).apply {
            currency = java.util.Currency.getInstance("USD")
        }
        return formatter.format(cents / 100.0)
    }

    companion object {
        val Zero = Money(0)

        /**
         * Construct from the Anthropic API's stringified cents value (e.g.
         * "2013.9595"). Despite the `currency: "USD"` label the value is cents,
         * not dollars (see iOS ADR-005). Fractions of a cent are truncated
         * toward zero. Returns null if [raw] isn't a number.
         */
        fun fromAnthropicCentsString(raw: String): Money? {
            val dec = raw.trim().toBigDecimalOrNull() ?: return null
            // (dec * 100).toLong() / 100 — truncate sub-cent fractions toward zero.
            val truncated = dec.multiply(BigDecimal(100)).toLong() / 100
            return Money(truncated)
        }

        /**
         * Convert a [BigDecimal] USD amount (e.g. 19.8093 dollars) to Money,
         * rounding to the nearest whole cent with banker's rounding so
         * half-cent splits don't bias a running total. Mirrors iOS `fromDollars`.
         */
        fun fromDollars(dollars: BigDecimal): Money {
            val cents = dollars.movePointRight(2).setScale(0, RoundingMode.HALF_EVEN).toLong()
            return Money(cents)
        }
    }
}
