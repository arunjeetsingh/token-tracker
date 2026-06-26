package studio.maximumimpact.tokencounter.features.providers

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import studio.maximumimpact.tokencounter.providers.ProviderKind

class ProviderSetupTest {

    @Test
    fun defaultSelection_prefersAnthropicForExistingUsers() {
        assertEquals(ProviderSetup.ANTHROPIC, ProviderSetup.DEFAULT)
        assertEquals(ProviderSetup.ANTHROPIC, ProviderSetup.values().first())
    }

    @Test
    fun fromProviderKind_mapsEverySupportedProvider() {
        assertEquals(ProviderSetup.ANTHROPIC, ProviderSetup.fromProviderKind(ProviderKind.ANTHROPIC))
        assertEquals(ProviderSetup.OPENAI, ProviderSetup.fromProviderKind(ProviderKind.OPENAI))
    }

    @Test
    fun fromApiKey_routesAnthropicAdminAndApiKeysToAnthropic() {
        assertEquals(ProviderSetup.ANTHROPIC, ProviderSetup.fromApiKey("  " + "sk-" + "ant-admin-" + "a".repeat(32)))
        assertEquals(ProviderSetup.ANTHROPIC, ProviderSetup.fromApiKey("sk-" + "ant-api-" + "b".repeat(32)))
    }

    @Test
    fun fromApiKey_routesOpenAIAdminProjectAndLegacyKeysToOpenAI() {
        assertEquals(ProviderSetup.OPENAI, ProviderSetup.fromApiKey("sk-admin-" + "a".repeat(32)))
        assertEquals(ProviderSetup.OPENAI, ProviderSetup.fromApiKey("sk-proj-" + "b".repeat(32)))
        assertEquals(ProviderSetup.OPENAI, ProviderSetup.fromApiKey("sk-" + "c".repeat(32)))
    }

    @Test
    fun fromApiKey_rejectsUnknownPrefix() {
        assertNull(ProviderSetup.fromApiKey("xoxb-" + "a".repeat(32)))
    }
}
