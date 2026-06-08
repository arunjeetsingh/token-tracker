package studio.maximumimpact.tokencounter.notifications

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import kotlinx.coroutines.flow.first
import studio.maximumimpact.tokencounter.credentials.KeystoreCredentialStore
import studio.maximumimpact.tokencounter.data.DataStoreDemoModeStore
import studio.maximumimpact.tokencounter.data.DataStoreNotificationPrefsStore
import studio.maximumimpact.tokencounter.data.DataStoreSpendLimitStore
import studio.maximumimpact.tokencounter.providers.LiveCostProvider
import studio.maximumimpact.tokencounter.providers.anthropic.isAnthropicAuthError
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
        val key = KeystoreCredentialStore.create(context).load() ?: return Result.success()

        val report = try {
            LiveCostProvider().monthToDateCost(key)
        } catch (e: Exception) {
            // 401/403 means the key is bad (revoked / wrong scope) — terminal for
            // this run, so don't hammer the API with background retries. The next
            // foreground refresh wipes the key and re-onboards. Only transient
            // (network / server) failures get a backoff retry.
            return if (e.isAnthropicAuthError()) Result.success() else Result.retry()
        }

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
