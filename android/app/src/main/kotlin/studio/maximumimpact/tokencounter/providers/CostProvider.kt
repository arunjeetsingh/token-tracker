package studio.maximumimpact.tokencounter.providers

import studio.maximumimpact.tokencounter.core.MtdCost
import studio.maximumimpact.tokencounter.providers.anthropic.AnthropicClient
import studio.maximumimpact.tokencounter.providers.anthropic.AnthropicClientFactory
import studio.maximumimpact.tokencounter.providers.anthropic.OrgIdentity
import studio.maximumimpact.tokencounter.providers.anthropic.isAnthropicAuthError
import studio.maximumimpact.tokencounter.providers.openai.OpenAIClient
import studio.maximumimpact.tokencounter.providers.openai.OpenAIClientFactory
import studio.maximumimpact.tokencounter.providers.openai.isOpenAIAuthError

/**
 * Fetches organization identity and month-to-date cost for a given provider key.
 * Kotlin sibling of the iOS `CostProviding` protocol. The key is passed per
 * call so the view model never holds a live client; the live implementation
 * builds a throwaway provider client each call. Tests substitute a fake.
 */
interface CostProvider {
    suspend fun whoami(apiKey: String): OrgIdentity
    suspend fun monthToDateCost(apiKey: String): MtdCost
}

enum class ProviderKind { ANTHROPIC, OPENAI }

fun providerKindFor(apiKey: String): ProviderKind =
    if (apiKey.trim().startsWith("sk-ant-")) ProviderKind.ANTHROPIC else ProviderKind.OPENAI

/** Production [CostProvider] backed by Anthropic or OpenAI based on the key prefix. */
class LiveCostProvider(
    private val anthropicBaseUrl: String = AnthropicClientFactory.DEFAULT_BASE_URL,
    private val openAIBaseUrl: String = OpenAIClientFactory.DEFAULT_BASE_URL
) : CostProvider {
    override suspend fun whoami(apiKey: String): OrgIdentity = when (providerKindFor(apiKey)) {
        ProviderKind.ANTHROPIC -> AnthropicClient(AnthropicClientFactory.create(apiKey, anthropicBaseUrl)).whoami()
        ProviderKind.OPENAI -> OpenAIClient(OpenAIClientFactory.create(apiKey, openAIBaseUrl)).whoami()
    }

    override suspend fun monthToDateCost(apiKey: String): MtdCost = when (providerKindFor(apiKey)) {
        ProviderKind.ANTHROPIC -> AnthropicClient(AnthropicClientFactory.create(apiKey, anthropicBaseUrl)).monthToDateCost()
        ProviderKind.OPENAI -> OpenAIClient(OpenAIClientFactory.create(apiKey, openAIBaseUrl)).monthToDateCost()
    }
}

fun Throwable.isProviderAuthError(): Boolean = isAnthropicAuthError() || isOpenAIAuthError()
