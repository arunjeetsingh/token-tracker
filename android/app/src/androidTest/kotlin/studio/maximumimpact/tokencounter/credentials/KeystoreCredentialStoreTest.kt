package studio.maximumimpact.tokencounter.credentials

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.emptyPreferences
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Instrumentation test for [KeystoreCredentialStore] — the one seam the JVM
 * unit tests can't reach, because it needs a real Android Keystore. Verifies
 * the encrypt/decrypt round-trip, deletion, that the persisted blob is actually
 * ciphertext (not the plaintext key), and the corrupt-blob recovery path.
 *
 * Backed by an in-memory [DataStore] so the test owns its storage and doesn't
 * collide with the app's real credentials store on the device.
 */
@RunWith(AndroidJUnit4::class)
class KeystoreCredentialStoreTest {

    private val key = "sk-ant-admin01-abcdefghijklmnopqrstuvwxyz0123456789"

    @Test
    fun save_thenLoad_roundTrips() = runTest {
        val store = KeystoreCredentialStore(InMemoryDataStore())
        store.save(key)
        assertEquals(key, store.load())
    }

    @Test
    fun load_returnsNullWhenNothingStored() = runTest {
        assertNull(KeystoreCredentialStore(InMemoryDataStore()).load())
    }

    @Test
    fun delete_removesTheKey() = runTest {
        val store = KeystoreCredentialStore(InMemoryDataStore())
        store.save(key)
        store.delete()
        assertNull(store.load())
    }

    @Test
    fun persistedBlob_isCiphertextNotPlaintext() = runTest {
        val backing = InMemoryDataStore()
        KeystoreCredentialStore(backing).save(key)

        val stored = backing.data.first().asMap().values.firstOrNull() as? String
        assertNotNull("expected an encrypted blob to be persisted", stored)
        assertNotEquals("the plaintext key must never be stored", key, stored)
    }

    @Test
    fun load_clearsAndReturnsNullOnCorruptBlob() = runTest {
        val backing = InMemoryDataStore()
        val store = KeystoreCredentialStore(backing)
        // Plant a value that can't be decrypted (not valid Base64 ciphertext).
        backing.edit { it[stringPreferencesKey("anthropic_admin_key_enc")] = "not-real-ciphertext" }

        // load() must not throw, must return null, and must drop the bad blob so
        // we don't retry the same failure on every launch.
        assertNull(store.load())
        assertNull(backing.data.first().asMap().values.firstOrNull())
    }

    /** Minimal in-memory Preferences DataStore (mirrors the unit-test fake). */
    private class InMemoryDataStore : DataStore<Preferences> {
        private val flow = MutableStateFlow(emptyPreferences())
        override val data: Flow<Preferences> = flow
        override suspend fun updateData(transform: suspend (Preferences) -> Preferences): Preferences {
            val updated = transform(flow.value)
            flow.value = updated
            return updated
        }
    }
}
