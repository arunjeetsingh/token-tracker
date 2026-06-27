package studio.maximumimpact.tokencounter.core

import java.time.LocalDate
import java.time.LocalDateTime

/** One day's finalized spend. Kotlin sibling of iOS `DailySpend`. */
data class DailySpend(
    val date: LocalDate,
    val cost: Money
)

/**
 * One model's contribution to the month-to-date spend. Sorted descending by
 * cost. The dashboard renders the top N. Kotlin sibling of iOS `ModelSpend`.
 */
data class ModelSpend(
    val modelId: String,
    val displayName: String,
    val cost: Money
)

/**
 * Composite month-to-date number shown on the dashboard. Kotlin sibling of
 * iOS `MTDCost`. [total] is the headline figure; the rest let the UI disclose
 * the finalized-vs-estimate gap honestly.
 */
data class MtdCost(
    val finalizedCost: Money,
    val todayEstimatedCost: Money,
    /** Models seen today that had no pricing entry; non-empty => lower bound. */
    val unpricedModels: List<String>,
    /** Start-of-today that splits finalized days from today's estimate. */
    val finalizedThrough: LocalDate,
    /** When the report was generated. */
    val asOf: LocalDateTime,
    /** Last ~30 days of finalized daily spend, sorted chronologically. */
    val dailySpend: List<DailySpend>,
    /** Per-model contribution, sorted descending. UI renders the top 3. */
    val modelBreakdown: List<ModelSpend>
) {
    val total: Money get() = finalizedCost + todayEstimatedCost
    val hasTodayEstimate: Boolean get() = todayEstimatedCost.cents > 0
    val hasUnpricedModels: Boolean get() = unpricedModels.isNotEmpty()
}


fun combineMtdCosts(reports: Collection<MtdCost>): MtdCost {
    require(reports.isNotEmpty()) { "At least one report is required" }
    return MtdCost(
        finalizedCost = Money(reports.sumOf { it.finalizedCost.cents }),
        todayEstimatedCost = Money(reports.sumOf { it.todayEstimatedCost.cents }),
        unpricedModels = reports.flatMap { it.unpricedModels }.distinct().sorted(),
        finalizedThrough = reports.minOf { it.finalizedThrough },
        asOf = reports.maxOf { it.asOf },
        dailySpend = reports.flatMap { it.dailySpend }
            .groupBy { it.date }
            .map { (date, rows) -> DailySpend(date, Money(rows.sumOf { it.cost.cents })) }
            .sortedBy { it.date },
        modelBreakdown = reports.flatMap { it.modelBreakdown }
            .groupBy { it.modelId to it.displayName }
            .map { (model, rows) -> ModelSpend(model.first, model.second, Money(rows.sumOf { it.cost.cents })) }
            .sortedByDescending { it.cost.cents }
    )
}
