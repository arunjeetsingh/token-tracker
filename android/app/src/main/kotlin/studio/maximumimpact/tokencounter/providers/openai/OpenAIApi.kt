package studio.maximumimpact.tokencounter.providers.openai

import retrofit2.http.GET
import retrofit2.http.Query

/** Retrofit interface for OpenAI's organization usage/cost endpoints. */
interface OpenAIApi {
    @GET("v1/organization/costs")
    suspend fun costs(
        @Query("start_time") startTime: Long,
        @Query("end_time") endTime: Long,
        @Query("bucket_width") bucketWidth: String = "1d",
        @Query("group_by[]") groupBy: List<String> = listOf("line_item"),
        @Query("limit") limit: Int = 30,
        @Query("page") page: String? = null
    ): OpenAICostPage
}
