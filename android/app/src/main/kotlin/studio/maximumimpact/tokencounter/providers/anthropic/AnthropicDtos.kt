package studio.maximumimpact.tokencounter.providers.anthropic

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Wire types for the Anthropic Usage & Cost Admin API. Kotlin siblings of the
 * iOS `AnthropicAPI` decodables. Timestamps stay as raw ISO-8601 strings here
 * and are parsed into UTC dates in [AnthropicClient]; unknown fields are
 * ignored by the JSON decoder (configured in the client factory).
 */
@Serializable
data class OrgIdentity(
    val id: String,
    val type: String,
    val name: String
)

// --- cost_report ---

@Serializable
data class CostReportPage(
    val data: List<CostBucket> = emptyList(),
    @SerialName("has_more") val hasMore: Boolean = false,
    @SerialName("next_page") val nextPage: String? = null
)

@Serializable
data class CostBucket(
    @SerialName("starting_at") val startingAt: String,
    @SerialName("ending_at") val endingAt: String? = null,
    val results: List<CostRow> = emptyList()
)

@Serializable
data class CostRow(
    val currency: String? = null,
    /** Amount in cents USD as a numeric string (e.g. "2013.9595"). */
    val amount: String,
    @SerialName("workspace_id") val workspaceId: String? = null,
    val model: String? = null,
    @SerialName("service_tier") val serviceTier: String? = null,
    @SerialName("token_type") val tokenType: String? = null,
    @SerialName("cost_type") val costType: String? = null,
    @SerialName("context_window") val contextWindow: String? = null,
    @SerialName("inference_geo") val inferenceGeo: String? = null,
    val description: String? = null
)

// --- usage_report/messages ---

@Serializable
data class MessagesUsagePage(
    val data: List<MessagesUsageBucket> = emptyList(),
    @SerialName("has_more") val hasMore: Boolean = false,
    @SerialName("next_page") val nextPage: String? = null
)

@Serializable
data class MessagesUsageBucket(
    @SerialName("starting_at") val startingAt: String,
    @SerialName("ending_at") val endingAt: String? = null,
    val results: List<MessagesUsageRow> = emptyList()
)

/**
 * One usage row. Token counts default to 0 so a row that omits a lane (or a
 * whole `cache_creation` object) still decodes cleanly.
 */
@Serializable
data class MessagesUsageRow(
    val model: String? = null,
    @SerialName("uncached_input_tokens") val uncachedInputTokens: Long = 0,
    @SerialName("cache_creation") val cacheCreation: CacheCreation = CacheCreation(),
    @SerialName("cache_read_input_tokens") val cacheReadInputTokens: Long = 0,
    @SerialName("output_tokens") val outputTokens: Long = 0
)

@Serializable
data class CacheCreation(
    @SerialName("ephemeral_5m_input_tokens") val ephemeral5mInputTokens: Long = 0,
    @SerialName("ephemeral_1h_input_tokens") val ephemeral1hInputTokens: Long = 0
)
