package studio.maximumimpact.tokencounter.credentials

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AnthropicKeyValidationTest {

    @Test
    fun looksLikeAnthropicKey_acceptsPlausibleAdminKey() {
        val key = "sk-ant-admin01-" + "a".repeat(40)
        assertTrue(AnthropicKeyValidation.looksLikeAnthropicKey(key))
    }

    @Test
    fun looksLikeAnthropicKey_acceptsPlausibleOpenAIProjectKey() {
        val key = "sk-proj-" + "a".repeat(40)
        assertTrue(AnthropicKeyValidation.looksLikeAnthropicKey(key))
    }

    @Test
    fun looksLikeAnthropicKey_acceptsPlausibleOpenAILegacyKey() {
        val key = "sk-" + "a".repeat(40)
        assertTrue(AnthropicKeyValidation.looksLikeAnthropicKey(key))
    }

    @Test
    fun looksLikeAnthropicKey_acceptsLeadingTrailingWhitespace() {
        val key = "  sk-ant-admin01-" + "Ab9_-".repeat(8) + "  "
        assertTrue(AnthropicKeyValidation.looksLikeAnthropicKey(key))
    }

    @Test
    fun looksLikeAnthropicKey_rejectsShortGarbage() {
        assertFalse(AnthropicKeyValidation.looksLikeAnthropicKey("hello"))
        assertFalse(AnthropicKeyValidation.looksLikeAnthropicKey(""))
    }

    @Test
    fun looksLikeAnthropicKey_rejectsWrongPrefix() {
        assertFalse(AnthropicKeyValidation.looksLikeAnthropicKey("xoxb-" + "a".repeat(40)))
    }

    @Test
    fun looksLikeAnthropicKey_rejectsDisallowedCharacters() {
        // A space inside the token is not URL-safe.
        val key = "sk-ant-admin01-" + "a".repeat(20) + " " + "b".repeat(20)
        assertFalse(AnthropicKeyValidation.looksLikeAnthropicKey(key))
    }

    @Test
    fun masked_showsPrefixAndLastFour() {
        assertEquals(
            "sk-ant-admin01-…XyZ9",
            AnthropicKeyValidation.masked("sk-ant-admin01-abcdefghijklXyZ9")
        )
    }

    @Test
    fun masked_hidesShortStringsEntirely() {
        assertEquals("••••", AnthropicKeyValidation.masked("short"))
    }
}
