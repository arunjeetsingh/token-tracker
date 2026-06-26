package studio.maximumimpact.tokencounter.features.settings

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import studio.maximumimpact.tokencounter.core.Money
import studio.maximumimpact.tokencounter.features.providers.ProviderSetup
import studio.maximumimpact.tokencounter.ui.theme.TokenCounterTheme


/**
 * Settings modal. Kotlin sibling of the iOS `SettingsView` (presented as a
 * sheet). Shows the connected org + masked key, a destructive "Remove Admin
 * key" action (guarded by a confirm dialog), and an About section.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsSheet(
    orgName: String,
    maskedKey: String,
    appVersion: String,
    spendLimitCents: Long?,
    alertEnabled: Boolean,
    onEditLimit: () -> Unit,
    onAlertEnabledChange: (Boolean) -> Unit,
    onAddOrReplaceKey: () -> Unit,
    onDisconnect: () -> Unit,
    onDismiss: () -> Unit
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val uriHandler = LocalUriHandler.current
    val context = LocalContext.current
    var showConfirm by remember { mutableStateOf(false) }

    val limitSet = spendLimitCents != null
    val provider = ProviderSetup.fromApiKey(maskedKey) ?: ProviderSetup.DEFAULT

    // POST_NOTIFICATIONS is requested only when the user turns alerts on.
    val notificationPermission = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted -> if (granted) onAlertEnabledChange(true) }

    val onToggleAlert: (Boolean) -> Unit = onToggle@{ wantOn ->
        if (!wantOn) {
            onAlertEnabledChange(false)
            return@onToggle
        }
        val needsPermission = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.POST_NOTIFICATIONS
            ) != PackageManager.PERMISSION_GRANTED
        if (needsPermission) {
            notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            onAlertEnabledChange(true)
        }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = MaterialTheme.colorScheme.background
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp)
        ) {
            Text(
                text = "Settings",
                style = MaterialTheme.typography.titleLarge,
                color = MaterialTheme.colorScheme.onBackground
            )

            // Provider API key section.
            SettingsSection(title = "PROVIDER API KEY") {
                LabeledRow(label = "Provider", value = provider.displayName)
                LabeledRow(label = "Organization", value = orgName)
                LabeledRow(label = "API key", value = maskedKey, monospace = true)
                ActionRow(label = "Add or replace API key", onClick = onAddOrReplaceKey)
            }

            // Spend limit (local tracking target).
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                SettingsSection(title = "SPEND LIMIT") {
                    ActionRow(
                        label = "Monthly limit",
                        value = spendLimitCents?.let { Money(it).formatted() } ?: "Not set",
                        onClick = onEditLimit
                    )
                    SwitchRow(
                        label = "Alert me at 90% of limit",
                        checked = alertEnabled,
                        enabled = limitSet,
                        onCheckedChange = onToggleAlert
                    )
                    ActionRow(label = "Change limit in provider console", isLink = true) {
                        uriHandler.openUri(provider.limitsUrl)
                    }
                }
                Text(
                    text = if (limitSet) {
                        "Limit is tracked on this device — editing here doesn't change your " +
                            "actual provider limit. Alerts check in the background and notify you " +
                            "once when spend reaches 90%."
                    } else {
                        "Set a monthly limit to track your spend and enable 90% alerts."
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            // Billing (Console-only — not exposed by the API).
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                SettingsSection(title = "BILLING") {
                    ActionRow(label = "Credit balance & auto-reload", isLink = true) {
                        uriHandler.openUri(provider.billingUrl)
                    }
                }
                Text(
                    text = "Credit balance and auto-reload live in the provider console; " +
                        "the usage APIs don't expose them.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            // Destructive section.
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    text = "Remove API key",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(10.dp))
                        .clickable { showConfirm = true }
                        .background(MaterialTheme.colorScheme.surfaceVariant)
                        .padding(vertical = 12.dp, horizontal = 14.dp)
                )
                Text(
                    text = "Removes the API key from this device. " +
                        "You'll need to paste it again to reconnect.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            // About section.
            SettingsSection(title = "ABOUT") {
                LabeledRow(label = "App version", value = appVersion)
                Text(
                    text = "Provider API Keys",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { uriHandler.openUri(provider.adminKeysUrl) }
                        .padding(vertical = 12.dp, horizontal = 14.dp)
                )
            }
        }
    }

    if (showConfirm) {
        AlertDialog(
            onDismissRequest = { showConfirm = false },
            title = { Text("Remove the saved API key?") },
            text = {
                Text(
                    "Your API key will be removed from this device. The key itself " +
                        "is not revoked — you can revoke it in the provider console."
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        showConfirm = false
                        onDisconnect()
                    }
                ) {
                    Text("Disconnect", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { showConfirm = false }) {
                    Text("Cancel")
                }
            }
        )
    }
}

@Composable
private fun SettingsSection(
    title: String,
    content: @Composable () -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            text = title,
            style = MaterialTheme.typography.labelMedium.copy(letterSpacing = 0.5.sp),
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(10.dp))
                .background(MaterialTheme.colorScheme.surfaceVariant)
        ) {
            content()
        }
    }
}

@Composable
private fun SwitchRow(
    label: String,
    checked: Boolean,
    enabled: Boolean,
    onCheckedChange: (Boolean) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 6.dp, horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyLarge,
            color = if (enabled) {
                MaterialTheme.colorScheme.onBackground
            } else {
                MaterialTheme.colorScheme.onSurfaceVariant
            },
            modifier = Modifier.weight(1f)
        )
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            enabled = enabled
        )
    }
}

@Composable
private fun ActionRow(
    label: String,
    value: String? = null,
    isLink: Boolean = false,
    onClick: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(vertical = 12.dp, horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyLarge,
            color = if (isLink) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onBackground
        )
        if (value != null) {
            Spacer(modifier = Modifier.weight(1f))
            Text(
                text = value,
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun LabeledRow(
    label: String,
    value: String,
    monospace: Boolean = false
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 12.dp, horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onBackground
        )
        Spacer(modifier = Modifier.weight(1f))
        Text(
            text = value,
            style = if (monospace) {
                MaterialTheme.typography.bodyLarge.copy(fontFamily = FontFamily.Monospace)
            } else {
                MaterialTheme.typography.bodyLarge
            },
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Preview(showBackground = true)
@Composable
private fun SettingsSheetPreview() {
    TokenCounterTheme {
        // Preview the content directly (a real ModalBottomSheet needs a host).
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(MaterialTheme.colorScheme.background)
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp)
        ) {
            Text("Settings", style = MaterialTheme.typography.titleLarge)
            SettingsSection(title = "PROVIDER API KEY") {
                LabeledRow(label = "Provider", value = "OpenAI")
                LabeledRow(label = "Organization", value = "Personal")
                LabeledRow(label = "API key", value = "sk-admin-…w22", monospace = true)
            }
        }
    }
}
