package studio.maximumimpact.tokencounter.notifications

import android.content.Context
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

/**
 * Schedules / cancels the background spend-alert check. Driven by the persisted
 * opt-in flag: enabled while the user has alerts on, cancelled otherwise.
 */
object SpendAlertScheduler {

    private const val PERIODIC_WORK = "spend_alert_periodic"
    private const val IMMEDIATE_WORK = "spend_alert_immediate"
    private const val INTERVAL_HOURS = 6L

    fun enable(context: Context) {
        val workManager = WorkManager.getInstance(context.applicationContext)
        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()

        val periodic = PeriodicWorkRequestBuilder<SpendAlertWorker>(INTERVAL_HOURS, TimeUnit.HOURS)
            .setConstraints(constraints)
            .build()
        workManager.enqueueUniquePeriodicWork(
            PERIODIC_WORK,
            ExistingPeriodicWorkPolicy.UPDATE,
            periodic
        )

        // Run one check now so an already-high spend alerts promptly on opt-in.
        val immediate = OneTimeWorkRequestBuilder<SpendAlertWorker>()
            .setConstraints(constraints)
            .build()
        workManager.enqueueUniqueWork(IMMEDIATE_WORK, ExistingWorkPolicy.REPLACE, immediate)
    }

    fun disable(context: Context) {
        val workManager = WorkManager.getInstance(context.applicationContext)
        workManager.cancelUniqueWork(PERIODIC_WORK)
        workManager.cancelUniqueWork(IMMEDIATE_WORK)
    }
}
