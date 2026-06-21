package studio.maximumimpact.tokencounter.providers.openai

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** Wire types for OpenAI's organization cost API. */
@Serializable
data class OpenAICostPage(
    val data: List<OpenAICostBucket> = emptyList(),
    @SerialName("has_more") val hasMore: Boolean = false,
    @SerialName("next_page") val nextPage: String? = null
)

@Serializable
data class OpenAICostBucket(
    @SerialName("start_time") val startTime: Long,
    @SerialName("end_time") val endTime: Long? = null,
    val results: List<OpenAICostResult> = emptyList()
)

@Serializable
data class OpenAICostResult(
    val amount: OpenAIAmount,
    @SerialName("line_item") val lineItem: String? = null,
    @SerialName("project_id") val projectId: String? = null
)

@Serializable
data class OpenAIAmount(
    /** Decimal USD value for this cost bucket. */
    val value: String,
    val currency: String? = null
)
