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
import studio.maximumimpact.tokencounter.providers.ProviderKind
import java.time.LocalDate
import java.time.LocalDateTime
import java.util.Locale

/** A cached dashboard report plus the org it belongs to. */
data class CachedReport(val report: MtdCost, val orgName: String)

/**
 * Persists the last successfully-loaded dashboard report for instant cold
 * launch. Kotlin sibling of the iOS `DashboardCache`.
 */
interface ReportCache {
    suspend fun load(): CachedReport?
    suspend fun loadAll(): Map<ProviderKind, CachedReport> = emptyMap()
    suspend fun save(report: MtdCost, orgName: String)
    suspend fun save(provider: ProviderKind, report: MtdCost, orgName: String) = save(report, orgName)
    suspend fun clear()
    suspend fun clear(provider: ProviderKind) = clear()
}

class DataStoreReportCache(
    private val dataStore: DataStore<Preferences>
) : ReportCache {

    override suspend fun load(): CachedReport? {
        val prefs = dataStore.data.first()
        return readSnapshot(prefs[KEY]) ?: ProviderKind.entries.firstNotNullOfOrNull { provider ->
            readSnapshot(prefs[providerKey(provider)])
        }
    }

    override suspend fun loadAll(): Map<ProviderKind, CachedReport> {
        val prefs = dataStore.data.first()
        return ProviderKind.entries.mapNotNull { provider ->
            readSnapshot(prefs[providerKey(provider)])?.let { provider to it }
        }.toMap()
    }

    override suspend fun save(report: MtdCost, orgName: String) {
        val raw = encodeSnapshot(report, orgName) ?: return
        dataStore.edit { it[KEY] = raw }
    }

    override suspend fun save(provider: ProviderKind, report: MtdCost, orgName: String) {
        val raw = encodeSnapshot(report, orgName) ?: return
        dataStore.edit { prefs ->
            prefs[providerKey(provider)] = raw
            prefs[KEY] = raw
        }
    }

    override suspend fun clear() {
        dataStore.edit { prefs ->
            prefs.remove(KEY)
            ProviderKind.entries.forEach { prefs.remove(providerKey(it)) }
        }
    }

    override suspend fun clear(provider: ProviderKind) {
        dataStore.edit { it.remove(providerKey(provider)) }
    }

    private fun readSnapshot(raw: String?): CachedReport? =
        raw?.let { runCatching { json.decodeFromString<SnapshotDto>(it).toDomain() }.getOrNull() }

    private fun encodeSnapshot(report: MtdCost, orgName: String): String? =
        runCatching { json.encodeToString(SnapshotDto.from(report, orgName)) }.getOrNull()

    companion object {
        private val KEY = stringPreferencesKey("report_snapshot_v1")
        private val json = Json { ignoreUnknownKeys = true }

        private fun providerKey(provider: ProviderKind) =
            stringPreferencesKey("report_snapshot_${provider.name.lowercase(Locale.US)}_v1")

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
