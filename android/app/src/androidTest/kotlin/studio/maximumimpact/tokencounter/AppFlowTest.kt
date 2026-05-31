package studio.maximumimpact.tokencounter

import android.content.Context
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.runBlocking
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import studio.maximumimpact.tokencounter.core.DemoData
import studio.maximumimpact.tokencounter.credentials.KeystoreCredentialStore
import studio.maximumimpact.tokencounter.data.DataStoreDemoModeStore
import studio.maximumimpact.tokencounter.data.DataStoreReportCache
import studio.maximumimpact.tokencounter.features.onboarding.OnboardingTestTags

/**
 * End-to-end UI flow through the real [TokenCounterApp]: onboarding → connect
 * via the review key (the demo path, so no network) → dashboard → settings →
 * disconnect → back to onboarding.
 *
 * Exercises the actual ViewModel wiring and the real on-device DataStore /
 * Keystore stores. The persisted stores are reset before each run so bootstrap
 * lands on onboarding regardless of prior state on the device.
 */
@RunWith(AndroidJUnit4::class)
class AppFlowTest {

    @get:Rule
    val composeTestRule = createComposeRule()

    private val context: Context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Before
    fun resetPersistedState() = runBlocking {
        DataStoreDemoModeStore.create(context).setActive(false)
        KeystoreCredentialStore.create(context).delete()
        DataStoreReportCache.create(context).clear()
    }

    @Test
    fun reviewKey_walksOnboardingToDashboardToDisconnect() {
        composeTestRule.setContent { TokenCounterApp() }

        // Bootstrap with no key → onboarding.
        composeTestRule.waitUntil(timeoutMillis = 5_000) {
            composeTestRule.onAllNodesWithText("One-time setup").fetchSemanticsNodes().isNotEmpty()
        }

        // Paste the review key and connect.
        composeTestRule.onNodeWithTag(OnboardingTestTags.KEY_FIELD).performTextInput(DemoData.REVIEW_KEY)
        composeTestRule.onNodeWithText("Save & Connect").performScrollTo().performClick()

        // Demo dashboard renders (org "Personal").
        composeTestRule.waitUntil(timeoutMillis = 5_000) {
            composeTestRule.onAllNodesWithText("Personal").fetchSemanticsNodes().isNotEmpty()
        }
        composeTestRule.onNodeWithText("TokenCounter").assertIsDisplayed()

        // Open settings and disconnect.
        composeTestRule.onNodeWithContentDescription("Settings").performClick()
        composeTestRule.waitUntil(timeoutMillis = 5_000) {
            composeTestRule.onAllNodesWithText("Remove Admin key").fetchSemanticsNodes().isNotEmpty()
        }
        composeTestRule.onNodeWithText("Remove Admin key").performClick()
        // Confirmation dialog → Disconnect.
        composeTestRule.onNodeWithText("Disconnect").performClick()

        // Back to onboarding.
        composeTestRule.waitUntil(timeoutMillis = 5_000) {
            composeTestRule.onAllNodesWithText("One-time setup").fetchSemanticsNodes().isNotEmpty()
        }
    }
}
