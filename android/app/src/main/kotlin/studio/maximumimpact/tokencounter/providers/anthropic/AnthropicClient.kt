package studio.maximumimpact.tokencounter.providers.anthropic

import android.util.Log
import studio.maximumimpact.tokencounter.core.DailySpend
import studio.maximumimpact.tokencounter.core.Money
import studio.maximumimpact.tokencounter.core.ModelSpend
import studio.maximumimpact.tokencounter.core.MtdCost
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

/**
 * Thin client for the subset of the Anthropic Usage & Cost Admin API we need.
 * Kotlin sibling of the iOS `AnthropicClient`. Single responsibility:
 * month-to-date cost.
 *
 * Why the two-source approach: Anthropic's `cost_report` emits one bucket per
 * *closed* UTC day, so today's spend doesn't appear there until 00:00 UTC
 * tomorrow. To match the Console (which shows today live) we estimate today
 * ourselves from `usage_report/messages` × the public pricing table.
 *
 * All date-window math is in UTC because cost_report buckets are UTC-anchored.
 */
class AnthropicClient(private val api: AnthropicApi) {

    /** GET /v1/organizations/me — quick auth sanity check + org name. */
    suspend fun whoami(): OrgIdentity = api.whoami()

    /** Aggregated cost_report result: daily totals + a per-(model, day) split. */
    data class CostDetail(
        val daily: List<DailySpend>,
        /** modelId -> per-day costs (sorted by date asc). */
        val perModel: Map<String, List<DailySpend>>
    )

    /** Returned by [todayEstimatedCost]. */
    data class TodayEstimate(
        val cost: Money,
        /** Model ids seen in usage that had no pricing entry (estimate is a lower bound). */
        val unpricedModels: List<String>
    )

    /**
     * Combined month-to-date result: `cost_report` for finalized days +
     * `usage_report/messages` × pricing for today's partial day.
     */
    suspend fun monthToDateCost(now: Instant = Instant.now()): MtdCost {
        val today = now.atOffset(ZoneOffset.UTC).toLocalDate()
        val startOfMonth = today.withDayOfMonth(1)
        // Sparkline window: trailing 30 days of finalized data (may dip into the
        // previous month — exactly what "last 30 days" wants). The hero number
        // stays MTD-only via the startOfMonth filter below.
        val sparklineStart = today.minusDays(30)

        val detail = if (today.isAfter(sparklineStart)) {
            costDetail(start = sparklineStart, endExclusive = today)
        } else {
            CostDetail(daily = emptyList(), perModel = emptyMap())
        }

        // Hero MTD finalized = sum of daily buckets within this calendar month.
        val finalized = detail.daily
            .filter { !it.date.isBefore(startOfMonth) }
            .fold(Money.Zero) { acc, d -> acc + d.cost }

        // Model breakdown: also restricted to in-month for hero consistency.
        val modelBreakdown = detail.perModel
            .mapNotNull { (modelId, perDay) ->
                val total = perDay
                    .filter { !it.date.isBefore(startOfMonth) }
                    .fold(Money.Zero) { acc, d -> acc + d.cost }
                if (total.cents > 0) {
                    ModelSpend(modelId, ModelNaming.displayName(modelId), total)
                } else {
                    null
                }
            }
            .sortedByDescending { it.cost.cents }

        val todayEstimate = todayEstimatedCost(now)

        return MtdCost(
            finalizedCost = finalized,
            todayEstimatedCost = todayEstimate.cost,
            unpricedModels = todayEstimate.unpricedModels,
            finalizedThrough = today,
            asOf = LocalDateTime.ofInstant(now, ZoneId.systemDefault()),
            dailySpend = detail.daily,
            modelBreakdown = modelBreakdown
        )
    }

    /**
     * Pulls `cost_report` for [start, endExclusive) (UTC days), grouped by
     * description, and folds the paginated response into daily totals + a
     * per-model daily split. cost_report only accepts `description` /
     * `workspace_id` for group_by; each description row carries its `model`, so
     * we get the per-model split for free. Rows with a null/empty model (e.g.
     * web_search) still count toward the daily total but are dropped from the
     * per-model breakdown.
     */
    suspend fun costDetail(start: LocalDate, endExclusive: LocalDate): CostDetail {
        val dailyTotals = mutableMapOf<LocalDate, Money>()
        val perModel = mutableMapOf<String, MutableMap<LocalDate, Money>>()

        var page: String? = null
        var guard = 0
        while (true) {
            check(++guard < 200) { "cost_report pagination guard tripped" }
            val response = api.costReport(
                startingAt = isoInstant(start),
                endingAt = isoInstant(endExclusive),
                page = page
            )
            for (bucket in response.data) {
                val day = parseUtcDate(bucket.startingAt) ?: continue
                for (row in bucket.results) {
                    val money = Money.fromAnthropicCentsString(row.amount) ?: continue
                    dailyTotals[day] = (dailyTotals[day] ?: Money.Zero) + money
                    val model = row.model
                    if (!model.isNullOrEmpty()) {
                        val perDay = perModel.getOrPut(model) { mutableMapOf() }
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
        val perModelSorted = perModel.mapValues { (_, dayMap) ->
            dayMap.map { DailySpend(it.key, it.value) }.sortedBy { it.date }
        }
        return CostDetail(daily = daily, perModel = perModelSorted)
    }

    /**
     * Estimates today's cost from `usage_report/messages` (hourly, grouped by
     * model) × the local pricing table. Models with no pricing entry are
     * reported back so the caller can flag the estimate as incomplete.
     */
    suspend fun todayEstimatedCost(now: Instant = Instant.now()): TodayEstimate {
        val startOfToday = now.atOffset(ZoneOffset.UTC).toLocalDate()
        val perModel = mutableMapOf<String, TokenUsage>()

        var page: String? = null
        var guard = 0
        while (true) {
            check(++guard < 50) { "usage_report pagination guard tripped" }
            val response = api.usageReport(startingAt = isoInstant(startOfToday), page = page)
            for (bucket in response.data) {
                for (row in bucket.results) {
                    val key = row.model ?: ""
                    val inc = TokenUsage(
                        uncachedInputTokens = row.uncachedInputTokens,
                        cacheWrite5mTokens = row.cacheCreation.ephemeral5mInputTokens,
                        cacheWrite1hTokens = row.cacheCreation.ephemeral1hInputTokens,
                        cacheReadTokens = row.cacheReadInputTokens,
                        outputTokens = row.outputTokens
                    )
                    perModel[key] = (perModel[key] ?: TokenUsage.Zero) + inc
                }
            }
            if (!response.hasMore || response.nextPage == null) break
            page = response.nextPage
        }

        var totalDollars = BigDecimal.ZERO
        val unpriced = mutableListOf<String>()
        for ((model, usage) in perModel) {
            val pricing = ModelPricing.lookup(model)
            if (pricing == null) {
                if (model.isNotEmpty()) unpriced.add(model)
                continue
            }
            totalDollars = totalDollars.add(usage.cost(pricing))
        }

        return TodayEstimate(
            cost = Money.fromDollars(totalDollars),
            unpricedModels = unpriced.sorted()
        )
    }

    private companion object {
        private const val TAG = "AnthropicClient"

        /** ISO-8601 instant string for the start (00:00 UTC) of [day]. */
        fun isoInstant(day: LocalDate): String =
            DateTimeFormatter.ISO_INSTANT.format(day.atStartOfDay(ZoneOffset.UTC).toInstant())

        /**
         * Parse an API timestamp ("2026-05-29T00:00:00Z" or with offset) to its
         * UTC date. Returns null (and logs) for an unrecognized format so one
         * odd bucket doesn't crash the load — but the gap is visible in logs
         * rather than silently dropping a day from the sparkline.
         */
        fun parseUtcDate(raw: String): LocalDate? {
            try {
                return Instant.parse(raw).atOffset(ZoneOffset.UTC).toLocalDate()
            } catch (_: Exception) {
                // Fall through to the offset parser.
            }
            try {
                return OffsetDateTime.parse(raw).atZoneSameInstant(ZoneOffset.UTC).toLocalDate()
            } catch (_: Exception) {
                Log.w(TAG, "Unparseable cost_report timestamp '$raw'; dropping the bucket.")
                return null
            }
        }
    }
}
