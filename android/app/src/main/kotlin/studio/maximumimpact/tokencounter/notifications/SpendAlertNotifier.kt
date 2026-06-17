package studio.maximumimpact.tokencounter.notifications

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import studio.maximumimpact.tokencounter.MainActivity
import studio.maximumimpact.tokencounter.R

/** Builds and posts the local "spend approaching limit" notification. */
object SpendAlertNotifier {

    const val CHANNEL_ID = "spend_alerts"
    private const val NOTIFICATION_ID = 4201
    private const val TAG = "SpendAlertNotifier"

    /** Idempotent — creates the channel if it doesn't exist (minSdk 26). */
    fun ensureChannel(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) == null) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Spend alerts",
                    NotificationManager.IMPORTANCE_DEFAULT
                ).apply {
                    description = "Alerts when your monthly spend approaches your limit."
                }
            )
        }
    }

    /**
     * Posts the alert. No-ops if POST_NOTIFICATIONS isn't granted (API 33+) —
     * the toggle requests it on opt-in, but a later revocation shouldn't crash
     * the background worker.
     */
    fun notifySpendApproaching(context: Context, spentFormatted: String, percent: Int) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.POST_NOTIFICATIONS
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        ensureChannel(context)

        val openApp = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            0,
            openApp,
            PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_spend_alert)
            .setContentTitle("Spend at $percent% of your limit")
            .setContentText("$spentFormatted spent so far this month.")
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()

        try {
            NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification)
        } catch (e: SecurityException) {
            // Permission can be revoked between the explicit check and notify().
            Log.w(TAG, "Unable to post spend alert because notification permission was revoked.", e)
        }
    }
}
