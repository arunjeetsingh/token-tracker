package studio.maximumimpact.tokencounter.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import kotlinx.coroutines.flow.first

/**
 * Persists "the user is in demo mode because they pasted the review key."
 * Kotlin sibling of iOS `DemoMode.isPersistedActive`.
 *
 * Persisting (vs. in-memory) matters because app-store review kills and
 * relaunches the app and expects the demo state to survive. Cleared on
 * disconnect.
 */
interface DemoModeStore {
    suspend fun isActive(): Boolean
    suspend fun setActive(active: Boolean)
}

class DataStoreDemoModeStore(
    private val dataStore: DataStore<Preferences>
) : DemoModeStore {

    override suspend fun isActive(): Boolean = dataStore.data.first()[KEY] ?: false

    override suspend fun setActive(active: Boolean) {
        dataStore.edit { it[KEY] = active }
    }

    companion object {
        private val KEY = booleanPreferencesKey("demo_active")

        fun create(context: Context): DataStoreDemoModeStore =
            DataStoreDemoModeStore(context.applicationContext.appDataStore)
    }
}
