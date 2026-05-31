package studio.maximumimpact.tokencounter.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import kotlinx.coroutines.flow.first
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import studio.maximumimpact.tokencounter.core.DailySpend
import studio.maximumimpact.tokencounter.core.Money
import studio.maximumimpact.tokencounter.core.ModelSpend
import studio.maximumimpact.tokencounter.core.MtdCost
import java.time.LocalDate
import java.time.LocalDateTime

/** A cached dashboard report plus the org it belongs to. */
data class CachedReport(val report: MtdCost, val orgName: String)

/**
 * Persists the last successfully-loaded dashboard report for instant cold
 * launch. Kotlin sibling of the iOS `DashboardCache`.
 *
 * Like iOS: this is non-sensitive (totals, daily series, model breakdown), so
 * it lives in plain DataStore (not the Keystore). It is *not* consulted in demo
 * mode. Any decode failure is treated as a cache miss — a stale or partial blob
 * is never worse than none, since the UI always shows the report's "as of" time.
 */
interface ReportCache {
    suspend fun load(): CachedReport?
    suspend fun save(report: MtdCost, orgName: String)
    suspend fun clear()
}

class DataStoreReportCache(
    private val dataStore: DataStore<Preferences>
) : ReportCache {

    override suspend fun load(): CachedReport? {
        val raw = dataStore.data.first()[KEY] ?: return null
        return runCatching { json.decodeFromString<SnapshotDto>(raw).toDomain() }.getOrNull()
    }

    override suspend fun save(report: MtdCost, orgName: String) {
        val raw = runCatching { json.encodeToString(SnapshotDto.from(report, orgName)) }.getOrNull() ?: return
        dataStore.edit { it[KEY] = raw }
    }

    override suspend fun clear() {
        dataStore.edit { it.remove(KEY) }
    }

    companion object {
        private val KEY = stringPreferencesKey("report_snapshot_v1")
        private val json = Json { ignoreUnknownKeys = true }

        fun create(context: Context): DataStoreReportCache =
            DataStoreReportCache(context.applicationContext.appDataStore)
    }
}

// --- serialization DTOs (kept separate so the domain models stay plain) ---

@Serializable
private data class SnapshotDto(
    val finalizedCents: Long,
    val todayEstimatedCents: Long,
    val unpricedModels: List<String>,
    val finalizedThrough: String,
    val asOf: String,
    val dailySpend: List<DailyDto>,
    val modelBreakdown: List<ModelDto>,
    val orgName: String
) {
    fun toDomain() = CachedReport(
        report = MtdCost(
            finalizedCost = Money(finalizedCents),
            todayEstimatedCost = Money(todayEstimatedCents),
            unpricedModels = unpricedModels,
            finalizedThrough = LocalDate.parse(finalizedThrough),
            asOf = LocalDateTime.parse(asOf),
            dailySpend = dailySpend.map { DailySpend(LocalDate.parse(it.date), Money(it.cents)) },
            modelBreakdown = modelBreakdown.map { ModelSpend(it.modelId, it.displayName, Money(it.cents)) }
        ),
        orgName = orgName
    )

    companion object {
        fun from(report: MtdCost, orgName: String) = SnapshotDto(
            finalizedCents = report.finalizedCost.cents,
            todayEstimatedCents = report.todayEstimatedCost.cents,
            unpricedModels = report.unpricedModels,
            finalizedThrough = report.finalizedThrough.toString(),
            asOf = report.asOf.toString(),
            dailySpend = report.dailySpend.map { DailyDto(it.date.toString(), it.cost.cents) },
            modelBreakdown = report.modelBreakdown.map { ModelDto(it.modelId, it.displayName, it.cost.cents) },
            orgName = orgName
        )
    }
}

@Serializable
private data class DailyDto(val date: String, val cents: Long)

@Serializable
private data class ModelDto(val modelId: String, val displayName: String, val cents: Long)
