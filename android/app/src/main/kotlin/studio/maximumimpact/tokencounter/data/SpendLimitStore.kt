package studio.maximumimpact.tokencounter.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.longPreferencesKey
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/**
 * On-device monthly spend limit the dashboard tracks against.
 *
 * The Anthropic Admin API does not expose the org's configured spend limit (it
 * lives in the Console only), so this is a *local* target the user sets in the
 * app — the gauge renders real spend against it, but changing it here does NOT
 * change the actual Anthropic limit. Stored as whole cents; null = not set.
 */
interface SpendLimitStore {
    /** Emits the current limit in cents, or null when unset. */
    val limitCents: Flow<Long?>
    suspend fun setLimitCents(cents: Long?)
}

class DataStoreSpendLimitStore(
    private val dataStore: DataStore<Preferences>
) : SpendLimitStore {

    override val limitCents: Flow<Long?> = dataStore.data.map { it[KEY] }

    override suspend fun setLimitCents(cents: Long?) {
        dataStore.edit { prefs ->
            if (cents == null) prefs.remove(KEY) else prefs[KEY] = cents
        }
    }

    companion object {
        private val KEY = longPreferencesKey("spend_limit_cents")

        fun create(context: Context): DataStoreSpendLimitStore =
            DataStoreSpendLimitStore(context.applicationContext.appDataStore)
    }
}
