package studio.maximumimpact.tokencounter.credentials

/**
 * Lightweight format check for supported provider API keys. Kotlin sibling of iOS
 * `AnthropicKeyValidation`.
 *
 * Anthropic and OpenAI keys have provider-specific `sk-` prefixes followed by
 * a long opaque URL-safe token. We do **not** try to be exact — just enough to (a) reject
 * obvious typos and (b) recognize a paste-from-clipboard worth offering as a
 * suggestion. Real validation happens when we hit the API.
 */
object AnthropicKeyValidation {

    /**
     * Loose prefixes used by clipboard auto-detect. The API call itself fails
     * fast if a key is malformed, revoked, or lacks the required scopes, and we
     * surface that error.
     */
    val clipboardPrefixes = listOf("***", "***", "sk-ant-", "sk-admin-", "sk-proj-", "sk-")

    /** Minimum total length we'll even consider — keeps obvious garbage out. */
    const val MIN_LENGTH = 32

    private val allowedChars =
        ("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_").toSet()

    /**
     * True if [candidate] looks plausibly like a supported provider key — used to decide
     * whether to surface the "Paste detected key?" affordance.
     */
    fun looksLikeAnthropicKey(candidate: String): Boolean {
        val trimmed = candidate.trim()
        if (trimmed.length !in MIN_LENGTH..256) return false
        if (clipboardPrefixes.none { trimmed.startsWith(it) }) return false
        return trimmed.all { it in allowedChars }
    }

    /** Best-effort masked rendering, e.g. `sk-ant-admin01-…XyZ9`. */
    fun masked(key: String): String {
        val trimmed = key.trim()
        if (trimmed.length <= 12) return "••••"
        return "${trimmed.take(15)}…${trimmed.takeLast(4)}"
    }
}
