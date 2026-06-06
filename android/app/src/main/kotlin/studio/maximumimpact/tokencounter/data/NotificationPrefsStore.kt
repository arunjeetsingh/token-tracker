package studio.maximumimpact.tokencounter.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

/**
 * Persists the spend-alert opt-in and a dedupe marker so we notify at most once
 * per month. Default: alerts off (we only ask for notification permission when
 * the user turns this on).
 */
interface NotificationPrefsStore {
    /** Whether the user opted into the "90% of limit" spend alert. */
    val alertEnabled: Flow<Boolean>
    suspend fun setAlertEnabled(enabled: Boolean)

    /** "yyyy-MM" of the last month we already alerted for, or null. */
    suspend fun getLastAlertedMonth(): String?
    suspend fun setLastAlertedMonth(month: String?)
}

class DataStoreNotificationPrefsStore(
    private val dataStore: DataStore<Preferences>
) : NotificationPrefsStore {

    override val alertEnabled: Flow<Boolean> = dataStore.data.map { it[ENABLED] ?: false }

    override suspend fun setAlertEnabled(enabled: Boolean) {
        dataStore.edit { it[ENABLED] = enabled }
    }

    override suspend fun getLastAlertedMonth(): String? = dataStore.data.first()[LAST_MONTH]

    override suspend fun setLastAlertedMonth(month: String?) {
        dataStore.edit { prefs ->
            if (month == null) prefs.remove(LAST_MONTH) else prefs[LAST_MONTH] = month
        }
    }

    companion object {
        private val ENABLED = booleanPreferencesKey("spend_alert_enabled")
        private val LAST_MONTH = stringPreferencesKey("spend_alert_last_month")

        fun create(context: Context): DataStoreNotificationPrefsStore =
            DataStoreNotificationPrefsStore(context.applicationContext.appDataStore)
    }
}
