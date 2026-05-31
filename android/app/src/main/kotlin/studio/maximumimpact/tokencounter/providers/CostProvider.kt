package studio.maximumimpact.tokencounter.providers

import studio.maximumimpact.tokencounter.core.MtdCost
import studio.maximumimpact.tokencounter.providers.anthropic.AnthropicClient
import studio.maximumimpact.tokencounter.providers.anthropic.AnthropicClientFactory
import studio.maximumimpact.tokencounter.providers.anthropic.OrgIdentity

/**
 * Fetches organization identity and month-to-date cost for a given admin key.
 * Kotlin sibling of the iOS `CostProviding` protocol. The key is passed per
 * call so the view model never holds a live client; the live implementation
 * builds a throwaway [AnthropicClient] each call. Tests substitute a fake.
 */
interface CostProvider {
    suspend fun whoami(apiKey: String): OrgIdentity
    suspend fun monthToDateCost(apiKey: String): MtdCost
}

/** Production [CostProvider] backed by the real Anthropic API. */
class LiveCostProvider(
    private val baseUrl: String = AnthropicClientFactory.DEFAULT_BASE_URL
) : CostProvider {
    override suspend fun whoami(apiKey: String): OrgIdentity =
        AnthropicClient(AnthropicClientFactory.create(apiKey, baseUrl)).whoami()

    override suspend fun monthToDateCost(apiKey: String): MtdCost =
        AnthropicClient(AnthropicClientFactory.create(apiKey, baseUrl)).monthToDateCost()
}
