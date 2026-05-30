package studio.maximumimpact.tokencounter.features.onboarding

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import studio.maximumimpact.tokencounter.ui.theme.TokenCounterTheme

private const val ADMIN_KEYS_URL = "https://console.anthropic.com/settings/admin-keys"
private const val ORG_URL = "https://console.anthropic.com/settings/organization"

/**
 * One-time setup flow. Kotlin sibling of the iOS `OnboardingView`.
 *
 * In this UI-only port there's no real keychain or network call — tapping
 * "Save & Connect" simply hands the entered key up via [onConnect] so the
 * host can flip the app into its loaded (demo) state.
 */
@Composable
fun OnboardingScreen(
    onConnect: (String) -> Unit,
    isConnecting: Boolean = false,
    submitError: String? = null,
    modifier: Modifier = Modifier
) {
    val uriHandler = LocalUriHandler.current
    var key by remember { mutableStateOf("") }
    var showKey by remember { mutableStateOf(false) }

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp, vertical = 24.dp),
        verticalArrangement = Arrangement.spacedBy(24.dp)
    ) {
        // Header.
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Icon(
                imageVector = Icons.Filled.Lock,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(40.dp)
            )
            Text(
                text = "One-time setup",
                style = MaterialTheme.typography.headlineMedium,
                color = MaterialTheme.colorScheme.onBackground
            )
            Text(
                text = "TokenCounter reads usage from Anthropic's Admin API. " +
                    "We need a one-time admin key — takes about 30 seconds. " +
                    "It stays on this device only.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        // Step cards.
        StepCard(
            number = 1,
            title = "Make sure you have an organization",
            detail = "Admin keys live under an Anthropic organization. " +
                "If you're on a personal account you may need to create one."
        ) {
            OutlinedButton(onClick = { uriHandler.openUri(ORG_URL) }) {
                Text("Check Organization")
            }
        }
        StepCard(
            number = 2,
            title = "Open the Admin Keys page",
            detail = "Sign in to the Anthropic Console to manage admin keys."
        ) {
            Button(onClick = { uriHandler.openUri(ADMIN_KEYS_URL) }) {
                Text("Open Admin Keys")
            }
        }
        StepCard(
            number = 3,
            title = "Create an Admin key",
            detail = "Use \"Create Key\". Give it a name like \"TokenCounter\"."
        )
        StepCard(
            number = 4,
            title = "Copy the key",
            detail = "It starts with sk-ant-admin01-…. Paste it below."
        )

        // Paste card.
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(12.dp))
                .background(MaterialTheme.colorScheme.surfaceVariant)
                .padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = "Paste your key",
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onBackground
            )
            OutlinedTextField(
                value = key,
                onValueChange = { key = it },
                singleLine = true,
                placeholder = { Text("sk-ant-admin01-…") },
                visualTransformation = if (showKey) {
                    VisualTransformation.None
                } else {
                    PasswordVisualTransformation()
                },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                trailingIcon = {
                    TextButton(onClick = { showKey = !showKey }) {
                        Text(if (showKey) "Hide" else "Show")
                    }
                },
                modifier = Modifier.fillMaxWidth()
            )
            if (submitError != null) {
                Text(
                    text = submitError,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error
                )
            }
        }

        // Submit.
        Button(
            onClick = { onConnect(key) },
            enabled = !isConnecting && key.isNotBlank(),
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(if (isConnecting) "Connecting…" else "Save & Connect")
        }

        // Security footer.
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            FooterLine(
                icon = Icons.Filled.Lock,
                text = "Stored securely on this device only."
            )
            FooterLine(
                icon = Icons.Filled.Info,
                text = "Never synced to the cloud. You can disconnect anytime in Settings."
            )
        }
    }
}

@Composable
private fun StepCard(
    number: Int,
    title: String,
    detail: String,
    action: (@Composable () -> Unit)? = null
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .padding(14.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Box(
            modifier = Modifier
                .size(32.dp)
                .clip(CircleShape)
                .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.15f)),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = number.toString(),
                style = MaterialTheme.typography.titleMedium.copy(fontFeatureSettings = "tnum"),
                color = MaterialTheme.colorScheme.primary
            )
        }
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onBackground
            )
            Text(
                text = detail,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            if (action != null) {
                Spacer(modifier = Modifier.height(4.dp))
                action()
            }
        }
    }
}

@Composable
private fun FooterLine(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    text: String
) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(16.dp)
        )
        Text(
            text = text,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Preview(showBackground = true, showSystemUi = true)
@Composable
private fun OnboardingScreenPreview() {
    TokenCounterTheme {
        OnboardingScreen(onConnect = {})
    }
}
