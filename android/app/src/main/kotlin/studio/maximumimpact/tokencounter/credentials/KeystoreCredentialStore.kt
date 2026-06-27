package studio.maximumimpact.tokencounter.credentials

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.first
import studio.maximumimpact.tokencounter.providers.ProviderKind
import studio.maximumimpact.tokencounter.providers.providerKindFor
import java.security.KeyStore
import java.util.Locale
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * [CredentialStore] backed by an Android Keystore AES-GCM key.
 *
 * Provider keys are encrypted with a non-exportable Keystore key (alias
 * [KEY_ALIAS]) and only ciphertext is persisted, in a private DataStore. The
 * legacy single-key slot is still read for migration/back-compat, while new
 * writes use provider-specific slots so Anthropic and OpenAI can coexist.
 */
class KeystoreCredentialStore(
    private val dataStore: DataStore<Preferences>
) : CredentialStore {

    override suspend fun save(key: String) {
        save(providerKindFor(key), key)
    }

    override suspend fun save(provider: ProviderKind, key: String) {
        val blob = encrypt(key)
        dataStore.edit { prefs ->
            prefs[providerKey(provider)] = blob
            // Keep the legacy slot updated so older app builds can still read at
            // least one connected provider if the user rolls back.
            prefs[PREF_KEY] = blob
        }
    }

    override suspend fun load(): String? {
        val all = loadAll()
        if (all.isNotEmpty()) return all.values.first()
        val blob = dataStore.data.first()[PREF_KEY] ?: return null
        return decryptOrClear(blob, clear = { delete() })
    }

    override suspend fun loadAll(): Map<ProviderKind, String> {
        val prefs = dataStore.data.first()
        val providerKeys = ProviderKind.entries.mapNotNull { provider ->
            val blob = prefs[providerKey(provider)] ?: return@mapNotNull null
            decryptOrClear(blob, clear = { delete(provider) })?.let { provider to it }
        }.toMap()
        if (providerKeys.isNotEmpty()) return providerKeys

        // Migration/back-compat path for the old single-key slot.
        val legacy = prefs[PREF_KEY]?.let { decryptOrClear(it, clear = { delete() }) }
        return legacy?.let { mapOf(providerKindFor(it) to it) } ?: emptyMap()
    }

    override suspend fun delete() {
        dataStore.edit { prefs ->
            prefs.remove(PREF_KEY)
            ProviderKind.entries.forEach { prefs.remove(providerKey(it)) }
        }
    }

    override suspend fun delete(provider: ProviderKind) {
        dataStore.edit { prefs ->
            prefs.remove(providerKey(provider))
            // If the legacy slot points at the same provider being removed, clear
            // it so a deleted provider cannot come back on the next migration read.
            prefs[PREF_KEY]?.let { blob ->
                decryptOrNull(blob)?.let { key ->
                    if (providerKindFor(key) == provider) prefs.remove(PREF_KEY)
                }
            }
        }
    }

    // --- crypto ---

    private fun encrypt(plaintext: String): String {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
        val iv = cipher.iv
        val ciphertext = cipher.doFinal(plaintext.toByteArray(Charsets.UTF_8))
        val combined = iv + ciphertext
        return Base64.encodeToString(combined, Base64.NO_WRAP)
    }

    private fun decrypt(blob: String): String {
        val combined = Base64.decode(blob, Base64.NO_WRAP)
        val iv = combined.copyOfRange(0, GCM_IV_LENGTH)
        val ciphertext = combined.copyOfRange(GCM_IV_LENGTH, combined.size)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, getOrCreateKey(), GCMParameterSpec(GCM_TAG_BITS, iv))
        return String(cipher.doFinal(ciphertext), Charsets.UTF_8)
    }

    private suspend fun decryptOrClear(blob: String, clear: suspend () -> Unit): String? =
        try {
            decrypt(blob)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to decrypt stored provider key; clearing it.", e)
            clear()
            null
        }

    private fun decryptOrNull(blob: String): String? = runCatching { decrypt(blob) }.getOrNull()

    private fun getOrCreateKey(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        (keyStore.getEntry(KEY_ALIAS, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }

        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        val spec = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .build()
        generator.init(spec)
        return generator.generateKey()
    }

    companion object {
        private const val TAG = "CredentialStore"
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val KEY_ALIAS = "tokencounter.anthropic.admin"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val GCM_IV_LENGTH = 12
        private const val GCM_TAG_BITS = 128

        private val PREF_KEY = stringPreferencesKey("anthropic_admin_key_enc")

        private fun providerKey(provider: ProviderKind) =
            stringPreferencesKey("provider_${provider.name.lowercase(Locale.US)}_key_enc")

        private val Context.credentialDataStore by preferencesDataStore(name = "credentials")

        /** Build a store backed by the app's private credentials DataStore. */
        fun create(context: Context): KeystoreCredentialStore =
            KeystoreCredentialStore(context.applicationContext.credentialDataStore)
    }
}
