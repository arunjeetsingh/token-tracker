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
         * not dollars (see iOS ADR-005). Returns null if [raw] isn't a number.
         *
         * The `×100, round, ÷100` dance mirrors the iOS implementation exactly
         * (`(dec * 100 as NSDecimalNumber).int64Value / 100`). `int64Value`
         * rounds half-up rather than truncating, so we round half-up here too —
         * otherwise the same API payload (e.g. "0.999") could yield a 1¢
         * difference across platforms.
         */
        fun fromAnthropicCentsString(raw: String): Money? {
            val dec = raw.trim().toBigDecimalOrNull() ?: return null
            val cents = dec.multiply(BigDecimal(100)).setScale(0, RoundingMode.HALF_UP).toLong() / 100
            return Money(cents)
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
