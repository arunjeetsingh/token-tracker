package studio.maximumimpact.tokencounter.credentials

import studio.maximumimpact.tokencounter.providers.ProviderKind
import studio.maximumimpact.tokencounter.providers.providerKindFor

/**
 * Secure on-device storage for provider API keys. Kotlin sibling of the iOS
 * `KeychainStore`. The interface is kept storage-agnostic so the state holder
 * can depend on it and be tested with an in-memory fake.
 */
interface CredentialStore {
    /** Persist [key], replacing the legacy/single-provider value. */
    suspend fun save(key: String)

    /** Persist [key] for [provider], replacing only that provider's value. */
    suspend fun save(provider: ProviderKind, key: String) = save(key)

    /** The stored key, or null if none is saved. */
    suspend fun load(): String?

    /** All stored provider keys. Legacy single-key stores are exposed as one provider slot. */
    suspend fun loadAll(): Map<ProviderKind, String> =
        load()?.let { mapOf(providerKindFor(it) to it) } ?: emptyMap()

    /** Remove all stored keys. Idempotent — a no-op when nothing is stored. */
    suspend fun delete()

    /** Remove the stored key for [provider]. Single-key stores fall back to clearing all. */
    suspend fun delete(provider: ProviderKind) = delete()
}
