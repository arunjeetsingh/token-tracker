package studio.maximumimpact.tokencounter.features.dashboard

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import studio.maximumimpact.tokencounter.core.Money
import java.math.BigDecimal

/**
 * Dialog for setting the on-device monthly spend-limit *target*. The copy is
 * explicit that this only changes what TokenCounter tracks against — not the
 * real Anthropic limit (which the Admin API can't set; that's Console-only).
 */
@Composable
fun SpendLimitDialog(
    currentCents: Long?,
    onConfirm: (Long) -> Unit,
    onClear: () -> Unit,
    onDismiss: () -> Unit
) {
    var input by remember {
        mutableStateOf(currentCents?.let { Money(it).dollars.toPlainString() } ?: "")
    }
    val parsedCents = parseDollarsToCents(input)
    val showError = input.isNotBlank() && parsedCents == null

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (currentCents == null) "Set monthly spend limit" else "Edit monthly spend limit") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(
                    "TokenCounter tracks your spend against this target on this device. " +
                        "It does not change your actual Anthropic limit — change that in the Console.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                OutlinedTextField(
                    value = input,
                    onValueChange = { input = it },
                    singleLine = true,
                    prefix = { Text("$") },
                    placeholder = { Text("1,400") },
                    isError = showError,
                    supportingText = if (showError) {
                        { Text("Enter a positive dollar amount.") }
                    } else {
                        null
                    },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal)
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = { parsedCents?.let(onConfirm) },
                enabled = parsedCents != null
            ) {
                Text("Save")
            }
        },
        dismissButton = {
            if (currentCents != null) {
                TextButton(onClick = onClear) {
                    Text("Remove", color = MaterialTheme.colorScheme.error)
                }
            } else {
                TextButton(onClick = onDismiss) { Text("Cancel") }
            }
        }
    )
}

/** "$1,400" / "1400.50" / "1,400" → cents. Null when blank or not a positive number. */
internal fun parseDollarsToCents(input: String): Long? {
    val cleaned = input.trim().removePrefix("$").replace(",", "")
    if (cleaned.isEmpty()) return null
    val dollars = cleaned.toBigDecimalOrNull() ?: return null
    if (dollars <= BigDecimal.ZERO) return null
    return Money.fromDollars(dollars).cents
}
