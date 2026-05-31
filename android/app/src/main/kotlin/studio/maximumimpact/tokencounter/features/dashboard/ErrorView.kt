package studio.maximumimpact.tokencounter.features.dashboard

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import studio.maximumimpact.tokencounter.ui.theme.TokenCounterTheme

private val SystemOrange = Color(0xFFFF9500)

/**
 * Shown for [DashboardState.Failed] when there's no cached data to fall back
 * on. Kotlin sibling of the iOS dashboard `errorView`: warning glyph, a short
 * headline, the underlying message, and Retry / Disconnect actions.
 */
@Composable
fun ErrorView(
    message: String,
    onRetry: () -> Unit,
    onDisconnect: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(
            imageVector = Icons.Filled.Warning,
            contentDescription = null,
            tint = SystemOrange,
            modifier = Modifier.size(40.dp)
        )
        Text(
            text = "Couldn't load",
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onBackground,
            modifier = Modifier.padding(top = 12.dp)
        )
        Text(
            text = message,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(top = 8.dp)
        )
        Row(
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier.padding(top = 24.dp)
        ) {
            Button(onClick = onRetry) {
                Text("Retry")
            }
            OutlinedButton(
                onClick = onDisconnect,
                colors = ButtonDefaults.outlinedButtonColors(
                    contentColor = MaterialTheme.colorScheme.error
                )
            ) {
                Text("Disconnect")
            }
        }
    }
}

@Preview(showBackground = true, showSystemUi = true)
@Composable
private fun ErrorViewPreview() {
    TokenCounterTheme {
        ErrorView(
            message = "HTTP 500: the server had a problem.",
            onRetry = {},
            onDisconnect = {}
        )
    }
}
