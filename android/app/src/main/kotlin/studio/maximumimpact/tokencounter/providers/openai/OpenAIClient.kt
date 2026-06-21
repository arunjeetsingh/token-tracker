package studio.maximumimpact.tokencounter.providers.openai

import studio.maximumimpact.tokencounter.core.DailySpend
import studio.maximumimpact.tokencounter.core.Money
import studio.maximumimpact.tokencounter.core.ModelSpend
import studio.maximumimpact.tokencounter.core.MtdCost
import studio.maximumimpact.tokencounter.providers.anthropic.OrgIdentity
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZoneOffset

/**
 * Thin client for OpenAI's organization Costs API.
 *
 * OpenAI's costs endpoint returns closed/open daily buckets in epoch seconds and
 * amount values in USD. Unlike Anthropic, OpenAI already includes today's bucket
 * in the costs feed, so we expose the returned MTD total directly and keep
 * `todayEstimatedCost` at zero.
 */
class OpenAIClient(private val api: OpenAIApi) {

    /** Quick auth sanity check. OpenAI does not expose a cheap org-name endpoint for this scope. */
    suspend fun whoami(now: Instant = Instant.now()): OrgIdentity {
        val today = now.atOffset(ZoneOffset.UTC).toLocalDate()
        // Probe the smallest valid costs window; 401/403 bubbles up as auth failure.
        api.costs(startTime = epochSeconds(today), endTime = epochSeconds(today.plusDays(1)), limit = 1)
        return OrgIdentity(id = "openai", type = "organization", name = "OpenAI Organization")
    }

    suspend fun monthToDateCost(now: Instant = Instant.now()): MtdCost {
        val today = now.atOffset(ZoneOffset.UTC).toLocalDate()
        val startOfMonth = today.withDayOfMonth(1)
        val sparklineStart = today.minusDays(30)
        val start = minOf(startOfMonth, sparklineStart)
        val endExclusive = today.plusDays(1)

        val dailyTotals = mutableMapOf<LocalDate, Money>()
        val perLineItem = mutableMapOf<String, MutableMap<LocalDate, Money>>()

        var page: String? = null
        var guard = 0
        while (true) {
            check(++guard < 200) { "OpenAI costs pagination guard tripped" }
            val response = api.costs(
                startTime = epochSeconds(start),
                endTime = epochSeconds(endExclusive),
                page = page
            )
            for (bucket in response.data) {
                val day = Instant.ofEpochSecond(bucket.startTime).atOffset(ZoneOffset.UTC).toLocalDate()
                for (row in bucket.results) {
                    val money = Money.fromDollars(row.amount.value.toBigDecimalOrNull() ?: continue)
                    dailyTotals[day] = (dailyTotals[day] ?: Money.Zero) + money
                    val label = row.lineItem?.takeUnless { it.isBlank() }
                        ?: row.projectId?.takeUnless { it.isBlank() }
                    if (label != null) {
                        val perDay = perLineItem.getOrPut(label) { mutableMapOf() }
                        perDay[day] = (perDay[day] ?: Money.Zero) + money
                    }
                }
            }
            if (!response.hasMore || response.nextPage == null) break
            page = response.nextPage
        }

        val daily = dailyTotals
            .map { DailySpend(it.key, it.value) }
            .sortedBy { it.date }
        val finalized = daily
            .filter { !it.date.isBefore(startOfMonth) }
            .fold(Money.Zero) { acc, d -> acc + d.cost }
        val breakdown = perLineItem
            .mapNotNull { (label, perDay) ->
                val total = perDay
                    .filterKeys { !it.isBefore(startOfMonth) }
                    .values
                    .fold(Money.Zero) { acc, money -> acc + money }
                if (total.cents > 0) ModelSpend(label, displayName(label), total) else null
            }
            .sortedByDescending { it.cost.cents }

        return MtdCost(
            finalizedCost = finalized,
            todayEstimatedCost = Money.Zero,
            unpricedModels = emptyList(),
            finalizedThrough = today.plusDays(1),
            asOf = LocalDateTime.ofInstant(now, ZoneId.systemDefault()),
            dailySpend = daily,
            modelBreakdown = breakdown
        )
    }

    private fun displayName(raw: String): String = raw
        .removePrefix("model:")
        .replace('-', ' ')
        .replace('_', ' ')
        .split(' ')
        .filter { it.isNotBlank() }
        .joinToString(" ") { word ->
            when (word.lowercase()) {
                "gpt" -> "GPT"
                "api" -> "API"
                else -> word.replaceFirstChar { if (it.isLowerCase()) it.titlecase() else it.toString() }
            }
        }
        .ifBlank { raw }

    private fun epochSeconds(day: LocalDate): Long = day.atStartOfDay(ZoneOffset.UTC).toEpochSecond()
}
