package studio.maximumimpact.tokencounter.credentials

/**
 * Secure on-device storage for the Anthropic admin key. Kotlin sibling of the
 * iOS `KeychainStore`. The interface is kept storage-agnostic so the state
 * holder can depend on it and be tested with an in-memory fake (the real
 * [KeystoreCredentialStore] needs an Android runtime + hardware Keystore).
 */
interface CredentialStore {
    /** Persist [key], replacing any existing value. */
    suspend fun save(key: String)

    /** The stored key, or null if none is saved. */
    suspend fun load(): String?

    /** Remove the stored key. Idempotent — a no-op when nothing is stored. */
    suspend fun delete()
}
