package studio.maximumimpact.tokencounter.features.dashboard

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import studio.maximumimpact.tokencounter.ui.theme.TokenCounterTheme

/**
 * v1 dashboard. Hardcoded numbers — no data layer in this PR.
 *
 * Visual contract (mirrors iOS):
 *  - White background, no Material elevation.
 *  - "TokenCounter" header, bold, top-left.
 *  - Hero MTD figure centered vertically, very large and bold.
 *  - Single line of secondary copy beneath the hero with the
 *    today-estimate.
 */
@Composable
fun DashboardScreen() {
    // Sentinel values that match the iOS demo-mode dashboard so screenshots
    // line up 1:1 across platforms. Replace with real data once the data
    // layer lands (see ADR-013).
    DashboardScreen(
        appName = "TokenCounter",
        mtdAmount = "$5,160.11",
        todayEstimate = "~$312.88 estimated for today"
    )
}

@Composable
private fun DashboardScreen(
    appName: String,
    mtdAmount: String,
    todayEstimate: String
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .systemBarsPadding()
    ) {
        // Header: simple bold wordmark, top-left. No AppBar shadow.
        Text(
            text = appName,
            style = MaterialTheme.typography.titleLarge,
            color = MaterialTheme.colorScheme.onBackground,
            modifier = Modifier
                .align(Alignment.TopStart)
                .padding(start = 20.dp, top = 16.dp)
        )

        // Hero: vertically centered MTD + secondary estimate.
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
            modifier = Modifier
                .align(Alignment.Center)
                .padding(horizontal = 24.dp)
        ) {
            Text(
                text = mtdAmount,
                style = MaterialTheme.typography.displayLarge,
                color = MaterialTheme.colorScheme.onBackground
            )
            Text(
                text = todayEstimate,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 12.dp)
            )
        }
    }
}

@Preview(showBackground = true, showSystemUi = true)
@Composable
private fun DashboardScreenPreview() {
    TokenCounterTheme {
        DashboardScreen()
    }
}
