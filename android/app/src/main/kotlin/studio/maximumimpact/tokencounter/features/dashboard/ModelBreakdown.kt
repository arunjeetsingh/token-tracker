package studio.maximumimpact.tokencounter.features.dashboard

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import studio.maximumimpact.tokencounter.core.DemoData
import studio.maximumimpact.tokencounter.core.ModelSpend
import studio.maximumimpact.tokencounter.ui.theme.TokenCounterTheme

/**
 * Top-3 model spend list. Kotlin sibling of the iOS `ModelBreakdown`.
 *
 * Visual contract:
 *  - "TOP MODELS" uppercase caption header, secondary color, 0.5 tracking.
 *  - Rows: model name on the left, semibold tabular cost on the right,
 *    10dp vertical padding.
 *  - Hairline separator between rows (not after the last).
 *  - Renders nothing when there are no models.
 */
@Composable
fun ModelBreakdown(
    models: List<ModelSpend>,
    modifier: Modifier = Modifier
) {
    if (models.isEmpty()) return

    val top = models.sortedByDescending { it.cost.cents }.take(3)

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Text(
            text = "TOP MODELS",
            style = MaterialTheme.typography.labelMedium.copy(letterSpacing = 0.5.sp),
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        Column(modifier = Modifier.fillMaxWidth()) {
            top.forEachIndexed { index, model ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = model.displayName,
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onBackground,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f)
                    )
                    Spacer(modifier = Modifier.width(12.dp))
                    Text(
                        text = model.cost.formatted(),
                        style = MaterialTheme.typography.bodyLarge.copy(
                            fontWeight = FontWeight.SemiBold,
                            fontFeatureSettings = "tnum"
                        ),
                        color = MaterialTheme.colorScheme.onBackground
                    )
                }
                if (index < top.lastIndex) {
                    HorizontalDivider(color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.12f))
                }
            }
        }
    }
}

@Preview(showBackground = true)
@Composable
private fun ModelBreakdownPreview() {
    TokenCounterTheme {
        Column(modifier = Modifier.padding(16.dp)) {
            ModelBreakdown(models = DemoData.snapshot().report.modelBreakdown)
        }
    }
}
