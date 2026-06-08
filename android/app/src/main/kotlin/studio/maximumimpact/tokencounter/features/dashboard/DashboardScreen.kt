package studio.maximumimpact.tokencounter.features.dashboard

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import studio.maximumimpact.tokencounter.core.DemoData
import studio.maximumimpact.tokencounter.core.Money
import studio.maximumimpact.tokencounter.core.MtdCost
import studio.maximumimpact.tokencounter.ui.theme.TokenCounterTheme
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

private val asOfFormatter: DateTimeFormatter =
    DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(Locale.US)

/** iOS systemOrange, used for the DEMO pill and unpriced-models warnings. */
private val SystemOrange = Color(0xFFFF9500)

private const val STUDIO_URL = "https://maximumimpact.studio"

/**
 * The loaded dashboard. Kotlin sibling of the iOS `DashboardView` loaded state.
 *
 * Mirrors the iOS layout:
 *  - Large "TokenCounter" title with a leading gear (settings) and trailing
 *    DEMO pill + refresh control.
 *  - Vertically-centered hero: org name, the big month-to-date figure, the
 *    "as of" line, and the today-estimate / unpriced-models disclosures.
 *  - A 30-day spend chart and the top-3 model breakdown.
 *  - A "from maximumimpact.studio" footer link pinned to the bottom.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DashboardScreen(
    orgName: String,
    report: MtdCost,
    isDemo: Boolean,
    isRefreshing: Boolean,
    spendLimitCents: Long?,
    onAdjustLimit: () -> Unit,
    onRefresh: () -> Unit,
    onOpenSettings: () -> Unit,
    modifier: Modifier = Modifier
) {
    Scaffold(
        modifier = modifier.fillMaxSize(),
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            LargeTopAppBar(
                title = {
                    Text(
                        text = "TokenCounter",
                        style = MaterialTheme.typography.titleLarge
                    )
                },
                navigationIcon = {
                    IconButton(onClick = onOpenSettings) {
                        Icon(
                            imageVector = Icons.Filled.Settings,
                            contentDescription = "Settings",
                            tint = MaterialTheme.colorScheme.primary
                        )
                    }
                },
                actions = {
                    if (isDemo) {
                        DemoPill()
                        Spacer(modifier = Modifier.width(8.dp))
                    }
                    if (isRefreshing) {
                        Box(
                            modifier = Modifier.size(48.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(20.dp),
                                strokeWidth = 2.dp,
                                color = MaterialTheme.colorScheme.primary
                            )
                        }
                    } else {
                        IconButton(onClick = onRefresh) {
                            Icon(
                                imageVector = Icons.Filled.Refresh,
                                contentDescription = "Refresh",
                                tint = MaterialTheme.colorScheme.primary
                            )
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                    scrolledContainerColor = MaterialTheme.colorScheme.background,
                    titleContentColor = MaterialTheme.colorScheme.onBackground
                )
            )
        },
        bottomBar = { StudioFooter() }
    ) { innerPadding ->
        DashboardContent(
            orgName = orgName,
            report = report,
            spendLimitCents = spendLimitCents,
            onAdjustLimit = onAdjustLimit,
            contentPadding = innerPadding
        )
    }
}

@Composable
private fun DashboardContent(
    orgName: String,
    report: MtdCost,
    spendLimitCents: Long?,
    onAdjustLimit: () -> Unit,
    contentPadding: PaddingValues
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(contentPadding)
            .verticalScroll(rememberScrollState()),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Spacer(modifier = Modifier.height(16.dp))

        // Hero block.
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp)
        ) {
            Text(
                text = orgName,
                style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Medium),
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                text = report.total.formatted(),
                style = MaterialTheme.typography.displayLarge.copy(fontFeatureSettings = "tnum"),
                color = MaterialTheme.colorScheme.onBackground,
                textAlign = TextAlign.Center
            )
            Text(
                text = "Month to date · as of ${report.asOf.toLocalTime().format(asOfFormatter)}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center
            )
            if (report.hasTodayEstimate) {
                Text(
                    text = "Includes ~${report.todayEstimatedCost.formatted()} estimated for today",
                    style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Normal),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center
                )
            }
            if (report.hasUnpricedModels) {
                Text(
                    text = "⚠️ Estimate excludes: ${report.unpricedModels.joinToString(", ")}",
                    style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Normal),
                    color = SystemOrange,
                    textAlign = TextAlign.Center
                )
            }
        }

        Spacer(modifier = Modifier.height(32.dp))

        // Data block: spend limit + chart + model breakdown.
        Column(
            verticalArrangement = Arrangement.spacedBy(24.dp),
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
        ) {
            SpendLimitCard(
                report = report,
                limitCents = spendLimitCents,
                onAdjust = onAdjustLimit
            )
            SpendBarChart(daily = report.dailySpend)
            ModelBreakdown(models = report.modelBreakdown)
        }

        Spacer(modifier = Modifier.height(24.dp))
    }
}

private val resetDateFormatter: DateTimeFormatter =
    DateTimeFormatter.ofPattern("MMM d, yyyy", Locale.US)

@Composable
private fun SpendLimitCard(
    report: MtdCost,
    limitCents: Long?,
    onAdjust: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        if (limitCents == null) {
            Text(
                text = "Set a monthly spend limit",
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onBackground
            )
            Text(
                text = "Track your spend against a target and get a heads-up as you approach it.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Button(onClick = onAdjust, modifier = Modifier.align(Alignment.Start)) {
                Text("Set limit")
            }
            return@Column
        }

        val spent = report.total.cents
        val fraction = SpendLimit.progressFraction(spent, limitCents)
        val percent = SpendLimit.percentUsed(spent, limitCents)
        val severity = SpendLimit.severity(spent, limitCents)
        val barColor = when (severity) {
            SpendLimit.Severity.OVER -> MaterialTheme.colorScheme.error
            SpendLimit.Severity.APPROACHING -> SystemOrange
            SpendLimit.Severity.NORMAL -> MaterialTheme.colorScheme.primary
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "${report.total.formatted()} spent",
                style = MaterialTheme.typography.bodyLarge.copy(
                    fontWeight = FontWeight.Medium,
                    fontFeatureSettings = "tnum"
                ),
                color = MaterialTheme.colorScheme.onBackground
            )
            Spacer(modifier = Modifier.weight(1f))
            Text(
                text = "$percent% used",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        LinearProgressIndicator(
            progress = { fraction },
            modifier = Modifier
                .fillMaxWidth()
                .height(8.dp)
                .clip(RoundedCornerShape(4.dp)),
            color = barColor,
            trackColor = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.12f)
        )

        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "${Money(limitCents).formatted()} monthly limit",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(modifier = Modifier.weight(1f))
            Text(
                text = "Resets ${SpendLimit.nextResetDate(report.finalizedThrough).format(resetDateFormatter)}",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        if (severity != SpendLimit.Severity.NORMAL) {
            Text(
                text = if (severity == SpendLimit.Severity.OVER) {
                    "Over your monthly limit"
                } else {
                    "Approaching your monthly limit"
                },
                style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Medium),
                color = barColor
            )
        }

        Row(modifier = Modifier.fillMaxWidth()) {
            Spacer(modifier = Modifier.weight(1f))
            TextButton(onClick = onAdjust) { Text("Adjust limit") }
        }
    }
}

@Composable
private fun DemoPill() {
    Text(
        text = "DEMO",
        style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold),
        color = SystemOrange,
        modifier = Modifier
            .clip(RoundedCornerShape(percent = 50))
            .background(SystemOrange.copy(alpha = 0.2f))
            .padding(horizontal = 6.dp, vertical = 2.dp)
    )
}

@Composable
private fun StudioFooter() {
    val uriHandler = LocalUriHandler.current
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(bottom = 8.dp, top = 4.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = "from maximumimpact.studio",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.clickable { uriHandler.openUri(STUDIO_URL) }
        )
    }
}

@Preview(showBackground = true, showSystemUi = true)
@Composable
private fun DashboardScreenPreview() {
    val snapshot = DemoData.snapshot()
    TokenCounterTheme {
        DashboardScreen(
            orgName = snapshot.orgName,
            report = snapshot.report,
            isDemo = true,
            isRefreshing = false,
            spendLimitCents = 1_000_000,
            onAdjustLimit = {},
            onRefresh = {},
            onOpenSettings = {}
        )
    }
}
