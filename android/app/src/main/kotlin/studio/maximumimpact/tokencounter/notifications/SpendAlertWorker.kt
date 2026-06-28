package studio.maximumimpact.tokencounter.notifications

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import kotlinx.coroutines.flow.first
import studio.maximumimpact.tokencounter.core.MtdCost
import studio.maximumimpact.tokencounter.core.combineMtdCosts
import studio.maximumimpact.tokencounter.credentials.KeystoreCredentialStore
import studio.maximumimpact.tokencounter.data.DataStoreDemoModeStore
import studio.maximumimpact.tokencounter.data.DataStoreNotificationPrefsStore
import studio.maximumimpact.tokencounter.data.DataStoreSpendLimitStore
import studio.maximumimpact.tokencounter.providers.LiveCostProvider
import studio.maximumimpact.tokencounter.providers.isProviderAuthError
import kotlin.math.roundToInt

/**
 * Periodic background check that posts a local notification when month-to-date
 * spend reaches [SpendAlert.THRESHOLD_FRACTION] of the user's local limit.
 *
 * Re-reads all preconditions each run (the toggle, limit, and key can change
 * between schedules) and dedupes to once per calendar month. There's no backend
 * to push from — this is the app checking its own usage on a schedule.
 */
class SpendAlertWorker(
    appContext: Context,
    params: WorkerParameters
) : CoroutineWorker(appContext, params) {

    override suspend fun doWork(): Result {
        val context = applicationContext
        val prefs = DataStoreNotificationPrefsStore.create(context)

        // Opt-in gate.
        if (!prefs.alertEnabled.first()) return Result.success()
        // Need a limit to compare against.
        val limitCents = DataStoreSpendLimitStore.create(context).limitCents.first()
            ?: return Result.success()
        // Demo mode never wrote a real key — nothing to fetch.
        if (DataStoreDemoModeStore.create(context).isActive()) return Result.success()
        val keys = KeystoreCredentialStore.create(context).loadAll().values.filter { it.isNotBlank() }
        if (keys.isEmpty()) return Result.success()

        val reports = mutableListOf<MtdCost>()
        var sawTransientFailure = false
        val provider = LiveCostProvider()
        for (key in keys) {
            val report = try {
                provider.monthToDateCost(key)
            } catch (e: Exception) {
                // A bad key or transient outage for one provider should not abort the whole
                // multi-provider check; combine whatever succeeds this run.
                if (!e.isProviderAuthError()) sawTransientFailure = true
                continue
            }
            reports += report
        }
        if (reports.isEmpty()) return if (sawTransientFailure) Result.retry() else Result.success()

        val report = combineMtdCosts(reports)

        val spentCents = report.total.cents
        if (!SpendAlert.atThreshold(spentCents, limitCents)) return Result.success()

        // Once per month.
        val month = SpendAlert.monthKey(report.finalizedThrough)
        if (prefs.getLastAlertedMonth() == month) return Result.success()

        val percent = (spentCents.toDouble() / limitCents.toDouble() * 100.0).roundToInt()
        SpendAlertNotifier.notifySpendApproaching(context, report.total.formatted(), percent)
        prefs.setLastAlertedMonth(month)
        return Result.success()
    }
}
