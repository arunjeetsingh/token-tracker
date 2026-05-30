package studio.maximumimpact.tokencounter.providers.anthropic

/**
 * Best-effort pretty names for Anthropic model ids that appear in the
 * cost/usage reports (e.g. `claude-opus-4-7` -> `Claude Opus 4.7`). Kotlin
 * sibling of iOS `AnthropicClient.displayName(forModelId:)`.
 *
 * When the id doesn't match a known pattern we fall back to the raw id so the
 * UI never silently drops a row.
 */
object ModelNaming {

    private data class Family(val key: String, val label: String)

    private val families = listOf(
        Family("opus", "Claude Opus"),
        Family("sonnet", "Claude Sonnet"),
        Family("haiku", "Claude Haiku")
    )

    fun displayName(modelId: String): String {
        val lower = modelId.lowercase()
        for (fam in families) {
            // claude-<fam>-X-Y...
            val prefix = "claude-${fam.key}-"
            if (lower.startsWith(prefix)) {
                val rest = lower.removePrefix(prefix)
                val parts = rest.split("-").take(2)
                if (parts.size == 2 && parts[0].isInt() && parts[1].isInt()) {
                    return "${fam.label} ${parts[0]}.${parts[1]}"
                }
                if (parts.isNotEmpty() && parts[0].isInt()) {
                    return "${fam.label} ${parts[0]}"
                }
            }
            // claude-3-5-sonnet etc.
            if (lower.contains("-${fam.key}")) {
                val stripped = lower.removePrefix("claude-")
                val segs = stripped.split("-")
                val famIdx = segs.indexOf(fam.key)
                if (famIdx >= 2 && segs[famIdx - 2].isInt() && segs[famIdx - 1].isInt()) {
                    return "${fam.label} ${segs[famIdx - 2]}.${segs[famIdx - 1]}"
                }
                if (famIdx >= 1 && segs[famIdx - 1].isInt()) {
                    return "${fam.label} ${segs[famIdx - 1]}"
                }
            }
        }
        return modelId
    }

    private fun String.isInt(): Boolean = isNotEmpty() && toIntOrNull() != null
}
