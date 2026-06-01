package studio.maximumimpact.tokencounter.features.dashboard

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
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
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import studio.maximumimpact.tokencounter.core.DemoData
import studio.maximumimpact.tokencounter.core.Money
import studio.maximumimpact.tokencounter.core.MtdCost
import studio.maximumimpact.tokencounter.ui.theme.TokenCounterTheme
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import kotlin.math.cos
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToLong
import kotlin.math.sin

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
            contentPadding = innerPadding
        )
    }
}

@Composable
private fun DashboardContent(
    orgName: String,
    report: MtdCost,
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
            AnimatedMoneyGauge(total = report.total, orgName = orgName)
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

        // Data block: chart + model breakdown.
        Column(
            verticalArrangement = Arrangement.spacedBy(24.dp),
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
        ) {
            SpendBarChart(daily = report.dailySpend)
            ModelBreakdown(models = report.modelBreakdown)
        }

        Spacer(modifier = Modifier.height(24.dp))
    }
}

@Composable
private fun AnimatedMoneyGauge(
    total: Money,
    orgName: String,
    modifier: Modifier = Modifier
) {
    val restingProgress = remember(total.cents) { speedometerProgress(total) }
    var needleTarget by remember { mutableFloatStateOf(restingProgress) }
    val needleProgress by animateFloatAsState(
        targetValue = needleTarget,
        animationSpec = spring(dampingRatio = 0.62f, stiffness = 260f),
        label = "speedometerNeedle"
    )
    val animatedCents by animateFloatAsState(
        targetValue = total.cents.toFloat(),
        animationSpec = tween(durationMillis = 520, easing = FastOutSlowInEasing),
        label = "headlineTotal"
    )

    LaunchedEffect(total.cents) {
        needleTarget = 0.96f
        delay(240)
        needleTarget = restingProgress
    }

    val primary = MaterialTheme.colorScheme.primary
    val onBackground = MaterialTheme.colorScheme.onBackground
    val muted = MaterialTheme.colorScheme.onSurfaceVariant
    val formatted = Money(animatedCents.roundToLong()).formatted()

    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(154.dp)
            .semantics {
                contentDescription = "Month to date, ${total.formatted()}, for $orgName"
            },
        contentAlignment = Alignment.Center
    ) {
        Canvas(modifier = Modifier.fillMaxSize()) {
            val strokeWidth = 9.dp.toPx()
            val center = Offset(size.width / 2f, size.height - 12.dp.toPx())
            val radius = min(size.width * 0.43f, size.height - 18.dp.toPx())
            val arcSize = Size(radius * 2f, radius * 2f)
            val arcTopLeft = Offset(center.x - radius, center.y - radius)
            val sweep = 130f * needleProgress.coerceIn(0f, 1f)

            drawArc(
                color = muted.copy(alpha = 0.22f),
                startAngle = 205f,
                sweepAngle = 130f,
                useCenter = false,
                topLeft = arcTopLeft,
                size = arcSize,
                style = Stroke(width = strokeWidth, cap = StrokeCap.Round)
            )
            drawArc(
                color = primary.copy(alpha = 0.86f),
                startAngle = 205f,
                sweepAngle = sweep,
                useCenter = false,
                topLeft = arcTopLeft,
                size = arcSize,
                style = Stroke(width = strokeWidth, cap = StrokeCap.Round)
            )

            val angle = Math.toRadians((205f + sweep).toDouble())
            val tip = Offset(
                x = center.x + cos(angle).toFloat() * radius * 0.78f,
                y = center.y + sin(angle).toFloat() * radius * 0.78f
            )
            drawLine(
                color = primary.copy(alpha = 0.68f),
                start = center,
                end = tip,
                strokeWidth = 3.dp.toPx(),
                cap = StrokeCap.Round
            )
            drawCircle(
                color = primary.copy(alpha = 0.82f),
                radius = 4.dp.toPx(),
                center = center
            )
        }

        Text(
            text = formatted,
            style = MaterialTheme.typography.displayLarge.copy(fontFeatureSettings = "tnum"),
            color = onBackground,
            textAlign = TextAlign.Center,
            maxLines = 1,
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .padding(bottom = 8.dp)
        )
    }
}

private fun speedometerProgress(total: Money): Float {
    val dollars = max(0.0, total.dollars.toDouble())
    val scaled = min(log10(dollars + 1.0) / 4.0, 1.0)
    return (0.1 + scaled * 0.8).toFloat()
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
            onRefresh = {},
            onOpenSettings = {}
        )
    }
}
