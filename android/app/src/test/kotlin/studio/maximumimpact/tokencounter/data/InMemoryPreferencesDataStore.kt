package studio.maximumimpact.tokencounter.data

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.emptyPreferences
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow

/**
 * Minimal in-memory [DataStore] of [Preferences] for JVM unit tests — avoids
 * needing an Android Context or a temp file. `edit {}` routes through
 * [updateData].
 */
class InMemoryPreferencesDataStore : DataStore<Preferences> {
    private val flow = MutableStateFlow(emptyPreferences())
    override val data: Flow<Preferences> = flow

    override suspend fun updateData(transform: suspend (Preferences) -> Preferences): Preferences {
        val updated = transform(flow.value)
        flow.value = updated
        return updated
    }
}
