package studio.maximumimpact.tokencounter.providers.anthropic

import retrofit2.http.GET
import retrofit2.http.Query

/**
 * Retrofit interface for the subset of the Anthropic Usage & Cost Admin API we
 * need. The `x-api-key`, `anthropic-version`, and `accept` headers are injected
 * by an OkHttp interceptor (see [AnthropicClientFactory]), so they aren't
 * declared per-method here.
 *
 * `group_by[]` is a repeated query param — Retrofit emits one entry per list
 * element. `page` is nullable so it's omitted on the first request and supplied
 * as the pagination token on subsequent ones.
 */
interface AnthropicApi {

    @GET("v1/organizations/me")
    suspend fun whoami(): OrgIdentity

    @GET("v1/organizations/cost_report")
    suspend fun costReport(
        @Query("starting_at") startingAt: String,
        @Query("ending_at") endingAt: String,
        @Query("bucket_width") bucketWidth: String = "1d",
        @Query("group_by[]") groupBy: List<String> = listOf("description"),
        @Query("page") page: String? = null
    ): CostReportPage

    @GET("v1/organizations/usage_report/messages")
    suspend fun usageReport(
        @Query("starting_at") startingAt: String,
        @Query("bucket_width") bucketWidth: String = "1h",
        @Query("group_by[]") groupBy: List<String> = listOf("model"),
        @Query("limit") limit: Int = 48,
        @Query("page") page: String? = null
    ): MessagesUsagePage
}
