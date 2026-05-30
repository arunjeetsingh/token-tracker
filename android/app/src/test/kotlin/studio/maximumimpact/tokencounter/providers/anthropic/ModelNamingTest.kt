package studio.maximumimpact.tokencounter.providers.anthropic

import org.junit.Assert.assertEquals
import org.junit.Test

/** Verifies model-id → pretty-name parsing matches the iOS helper. */
class ModelNamingTest {

    @Test
    fun parsesCurrentGenFamilyMajorMinor() {
        assertEquals("Claude Opus 4.7", ModelNaming.displayName("claude-opus-4-7"))
        assertEquals("Claude Opus 4.5", ModelNaming.displayName("claude-opus-4-5"))
        assertEquals("Claude Sonnet 4.5", ModelNaming.displayName("claude-sonnet-4-5"))
        assertEquals("Claude Haiku 4.5", ModelNaming.displayName("claude-haiku-4-5"))
    }

    @Test
    fun ignoresDateSuffix() {
        assertEquals("Claude Opus 4.1", ModelNaming.displayName("claude-opus-4-1-20250805"))
    }

    @Test
    fun parsesLegacyDashedFamily() {
        assertEquals("Claude Sonnet 3.5", ModelNaming.displayName("claude-3-5-sonnet-20241022"))
        assertEquals("Claude Haiku 3.5", ModelNaming.displayName("claude-3-5-haiku"))
    }

    @Test
    fun fallsBackToRawIdWhenUnrecognized() {
        assertEquals("gpt-4", ModelNaming.displayName("gpt-4"))
        assertEquals("some-random-model", ModelNaming.displayName("some-random-model"))
    }
}
