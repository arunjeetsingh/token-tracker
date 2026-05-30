package studio.maximumimpact.tokencounter.features.dashboard

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import studio.maximumimpact.tokencounter.core.DailySpend
import studio.maximumimpact.tokencounter.core.DemoData
import studio.maximumimpact.tokencounter.ui.theme.AccentBlue
import studio.maximumimpact.tokencounter.ui.theme.TokenCounterTheme
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * Compact 30-day spend sparkline. Kotlin sibling of the iOS `SpendBarChart`.
 *
 * Visual contract:
 *  - 80dp tall bar area, bars bottom-aligned, equal width.
 *  - Bar spacing 2dp when >14 bars else 3dp.
 *  - Rounded (2dp) bars filled with the accent blue; selected bar full
 *    opacity, the rest 55%.
 *  - Tapping a bar toggles selection; the caption swaps between the default
 *    hint and the selected day's date + amount.
 *  - Selection resets when the number of bars changes.
 *  - Empty data renders a flat rounded placeholder.
 */
private val chartCaptionFormatter: DateTimeFormatter =
    DateTimeFormatter.ofPattern("EEE MMM d", Locale.US)

private const val CHART_HEIGHT_DP = 80f

@Composable
fun SpendBarChart(
    daily: List<DailySpend>,
    modifier: Modifier = Modifier
) {
    // Selection is keyed on the bar count so it resets if the data reshapes.
    var selectedIndex by remember(daily.size) { mutableStateOf<Int?>(null) }

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        if (daily.isEmpty()) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(CHART_HEIGHT_DP.dp)
                    .clip(RoundedCornerShape(8.dp))
                    .background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f))
            )
        } else {
            val maxCents = daily.maxOf { it.cost.cents }.coerceAtLeast(1L)
            val spacing = if (daily.size > 14) 2.dp else 3.dp

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(CHART_HEIGHT_DP.dp),
                horizontalArrangement = Arrangement.spacedBy(spacing),
                verticalAlignment = Alignment.Bottom
            ) {
                daily.forEachIndexed { index, day ->
                    val fraction = day.cost.cents.toFloat() / maxCents.toFloat()
                    val selected = selectedIndex == index
                    val description = "${day.date.format(chartCaptionFormatter)}, ${day.cost.formatted()}"
                    // The tap target is the full-height per-day slot, not the
                    // visible bar — low-spend days bottom out at 2dp, which
                    // would be an unusable (and inaccessible) tap target.
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxHeight()
                            .clickable(
                                interactionSource = remember { MutableInteractionSource() },
                                indication = null
                            ) {
                                selectedIndex = if (selected) null else index
                            }
                            .semantics { contentDescription = description },
                        contentAlignment = Alignment.BottomCenter
                    ) {
                        // Visual bar only — no interaction of its own.
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                // min 2dp so the smallest days stay visible.
                                .height((fraction * CHART_HEIGHT_DP).dp.coerceAtLeast(2.dp))
                                .clip(RoundedCornerShape(2.dp))
                                .background(AccentBlue.copy(alpha = if (selected) 1f else 0.55f))
                        )
                    }
                }
            }
        }

        val selectedDay = selectedIndex?.let { daily.getOrNull(it) }
        if (selectedDay == null) {
            Text(
                text = "Last 30 days · tap a bar for that day",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        } else {
            val tertiary = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
            Text(
                text = buildAnnotatedString {
                    append(selectedDay.date.format(chartCaptionFormatter))
                    withStyle(SpanStyle(color = tertiary)) { append(" · ") }
                    append(selectedDay.cost.formatted())
                },
                style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Medium),
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Preview(showBackground = true)
@Composable
private fun SpendBarChartPreview() {
    TokenCounterTheme {
        Box(modifier = Modifier.padding(16.dp)) {
            SpendBarChart(daily = DemoData.snapshot().report.dailySpend)
        }
    }
}
