package studio.maximumimpact.tokencounter.credentials

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.first
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * [CredentialStore] backed by a hardware-backed Android Keystore AES-GCM key.
 *
 * The admin key is encrypted with a non-exportable Keystore key (alias
 * [KEY_ALIAS]) and only the ciphertext is persisted, in a private DataStore.
 * This mirrors the iOS Keychain wrapper: the secret never leaves the device,
 * is not included in backups (the app sets `allowBackup=false`), and is not
 * synced to the cloud.
 *
 * Blob layout: Base64( [12-byte GCM IV] || [ciphertext + 16-byte GCM tag] ).
 */
class KeystoreCredentialStore(
    private val dataStore: DataStore<Preferences>
) : CredentialStore {

    override suspend fun save(key: String) {
        val blob = encrypt(key)
        dataStore.edit { it[PREF_KEY] = blob }
    }

    override suspend fun load(): String? {
        val blob = dataStore.data.first()[PREF_KEY] ?: return null
        return runCatching { decrypt(blob) }.getOrNull()
    }

    override suspend fun delete() {
        dataStore.edit { it.remove(PREF_KEY) }
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
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val KEY_ALIAS = "tokencounter.anthropic.admin"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val GCM_IV_LENGTH = 12
        private const val GCM_TAG_BITS = 128

        private val PREF_KEY = stringPreferencesKey("anthropic_admin_key_enc")

        private val Context.credentialDataStore by preferencesDataStore(name = "credentials")

        /** Build a store backed by the app's private credentials DataStore. */
        fun create(context: Context): KeystoreCredentialStore =
            KeystoreCredentialStore(context.applicationContext.credentialDataStore)
    }
}
