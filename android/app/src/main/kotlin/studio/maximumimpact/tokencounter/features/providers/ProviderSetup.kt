package studio.maximumimpact.tokencounter.features.providers

import studio.maximumimpact.tokencounter.providers.ProviderKind

/**
 * User-facing setup copy and console links for each supported usage provider.
 *
 * Provider dispatch is still driven by the saved key prefix; this enum only keeps
 * onboarding and Settings instructions provider-neutral and in sync across the
 * Android UI.
 */
enum class ProviderSetup(val providerKind: ProviderKind) {
    ANTHROPIC(ProviderKind.ANTHROPIC),
    OPENAI(ProviderKind.OPENAI);

    val displayName: String
        get() = when (this) {
            ANTHROPIC -> "Anthropic"
            OPENAI -> "OpenAI"
        }

    val introText: String
        get() = when (this) {
            ANTHROPIC -> "TokenCounter reads usage from Anthropic's Admin API. " +
                "We need a one-time admin key — takes about 30 seconds. It stays on this device only."
            OPENAI -> "TokenCounter reads usage from OpenAI's organization Costs API. " +
                "We need a one-time admin key — takes about 30 seconds. It stays on this device only."
        }

    val organizationTitle: String
        get() = when (this) {
            ANTHROPIC -> "Make sure you have an organization"
            OPENAI -> "Make sure billing is enabled"
        }

    val organizationDetail: String
        get() = when (this) {
            ANTHROPIC -> "Admin keys are only available on organizational Anthropic accounts. " +
                "If you're on a personal account you may need to create one."
            OPENAI -> "OpenAI usage data is available from your platform organization. " +
                "Check your organization billing settings before continuing."
        }

    val organizationButtonTitle: String
        get() = when (this) {
            ANTHROPIC -> "Check Organization"
            OPENAI -> "Check OpenAI Settings"
        }

    val organizationUrl: String
        get() = when (this) {
            ANTHROPIC -> "https://console.anthropic.com/settings/organization"
            OPENAI -> "https://platform.openai.com/settings/organization/billing/overview"
        }

    val adminKeysTitle: String
        get() = when (this) {
            ANTHROPIC -> "Open the Admin Keys page"
            OPENAI -> "Open the Admin Keys page"
        }

    val adminKeysDetail: String
        get() = when (this) {
            ANTHROPIC -> "Open console.anthropic.com to manage Anthropic admin keys."
            OPENAI -> "Open platform.openai.com to manage organization admin keys."
        }

    val adminKeysButtonTitle: String
        get() = when (this) {
            ANTHROPIC -> "Open Admin Keys"
            OPENAI -> "Open OpenAI Admin Keys"
        }

    val adminKeysUrl: String
        get() = when (this) {
            ANTHROPIC -> "https://console.anthropic.com/settings/admin-keys"
            OPENAI -> "https://platform.openai.com/settings/organization/admin-keys"
        }

    val createKeyTitle: String
        get() = when (this) {
            ANTHROPIC -> "Create an Admin key"
            OPENAI -> "Create an Admin key"
        }

    val createKeyDetail: String
        get() = when (this) {
            ANTHROPIC -> "Use \"Create Key\". Give it a name like \"TokenCounter\". " +
                "Admin keys are different from regular API keys — they start with sk-ant-admin…."
            OPENAI -> "Create an organization admin key and name it \"TokenCounter\". " +
                "Admin keys are different from regular project keys — they start with sk-admin…."
        }

    val copyKeyDetail: String
        get() = when (this) {
            ANTHROPIC -> "It starts with sk-ant-admin…. Paste it below."
            OPENAI -> "It starts with sk-admin…. Paste it below."
        }

    val keyPlaceholder: String
        get() = when (this) {
            ANTHROPIC -> "sk-ant-admin…"
            OPENAI -> "sk-admin…"
        }

    val limitsUrl: String
        get() = when (this) {
            ANTHROPIC -> "https://platform.claude.com/settings/limits"
            OPENAI -> "https://platform.openai.com/settings/organization/limits"
        }

    val billingUrl: String
        get() = when (this) {
            ANTHROPIC -> "https://platform.claude.com/settings/billing"
            OPENAI -> "https://platform.openai.com/settings/organization/billing/overview"
        }

    companion object {
        fun fromProviderKind(kind: ProviderKind): ProviderSetup = when (kind) {
            ProviderKind.ANTHROPIC -> ANTHROPIC
            ProviderKind.OPENAI -> OPENAI
        }

        fun fromApiKey(apiKey: String): ProviderSetup? {
            val trimmed = apiKey.trim()
            return when {
                trimmed.startsWith("sk-ant-") -> ANTHROPIC
                trimmed.startsWith("sk-admin-") ||
                    trimmed.startsWith("sk-proj-") ||
                    trimmed.startsWith("sk-") -> OPENAI
                else -> null
            }
        }
    }
}
