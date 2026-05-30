package studio.maximumimpact.tokencounter.data

import android.content.Context
import androidx.datastore.preferences.preferencesDataStore

/**
 * Single non-sensitive preferences store for the dashboard layer: the cached
 * report snapshot and the persisted demo-mode flag. (The admin key lives in the
 * separate, Keystore-encrypted `credentials` store — never here.)
 */
internal val Context.appDataStore by preferencesDataStore(name = "dashboard")
