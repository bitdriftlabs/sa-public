package com.example.metricdemo

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import io.bitdrift.capture.Capture.Logger
import io.bitdrift.capture.CaptureResult

private val metricColors = listOf(
    Color(0xFF2196F3), // blue   - sine
    Color(0xFFF44336), // red    - square
    Color(0xFFFF9800), // orange - sawtooth
    Color(0xFF4CAF50), // green  - triangle
    Color(0xFF9C27B0), // purple - dc
    Color(0xFF00BCD4), // cyan   - counter
)

@Composable
fun MetricsScreen(metricsViewModel: MetricsViewModel = viewModel()) {
    val metrics by metricsViewModel.metrics.collectAsState()
    var deviceCode by remember { mutableStateOf<String?>(null) }
    var deviceCodeLoading by remember { mutableStateOf(false) }
    var showDialog by remember { mutableStateOf(false) }
    val clipboard = LocalClipboardManager.current

    if (showDialog && deviceCode != null) {
        AlertDialog(
            onDismissRequest = { showDialog = false },
            title = { Text("Device Code") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        text = "Use this code in the bitdrift dashboard to stream logs from this device in real-time.",
                        style = MaterialTheme.typography.bodyMedium
                    )
                    Text(
                        text = deviceCode!!,
                        style = MaterialTheme.typography.headlineSmall.copy(
                            fontWeight = FontWeight.Bold,
                            textAlign = TextAlign.Center
                        ),
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    clipboard.setText(AnnotatedString(deviceCode!!))
                    showDialog = false
                }) { Text("Copy & Close") }
            },
            dismissButton = {
                TextButton(onClick = { showDialog = false }) { Text("Close") }
            }
        )
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .statusBarsPadding()
            .padding(horizontal = 16.dp, vertical = 12.dp)
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "Metric Demo",
                style = MaterialTheme.typography.headlineMedium.copy(fontWeight = FontWeight.Bold)
            )
            Button(
                onClick = {
                    deviceCodeLoading = true
                    Logger.createTemporaryDeviceCode { result ->
                        deviceCodeLoading = false
                        when (result) {
                            is CaptureResult.Success -> {
                                deviceCode = result.value
                                showDialog = true
                            }
                            is CaptureResult.Failure -> {
                                deviceCode = "Error: ${result.error.message}"
                                showDialog = true
                            }
                        }
                    }
                },
                enabled = !deviceCodeLoading
            ) {
                if (deviceCodeLoading) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(16.dp),
                        strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.onPrimary
                    )
                } else {
                    Text("Device Code")
                }
            }
        }

        metrics.forEachIndexed { index, metric ->
            MetricCard(metric = metric, color = metricColors[index])
        }
    }
}

@Composable
fun MetricCard(metric: MetricData, color: Color) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = color.copy(alpha = 0.08f))
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Column(modifier = Modifier.width(100.dp)) {
                Text(
                    text = metric.name,
                    style = MaterialTheme.typography.labelLarge.copy(
                        fontWeight = FontWeight.Bold,
                        color = color
                    )
                )
                Text(
                    text = "%.2f".format(metric.currentValue),
                    style = MaterialTheme.typography.headlineSmall.copy(fontWeight = FontWeight.Bold)
                )
            }

            SparklineChart(
                values = metric.history,
                color = color,
                modifier = Modifier
                    .weight(1f)
                    .height(64.dp)
            )
        }
    }
}

@Composable
fun SparklineChart(
    values: List<Float>,
    color: Color,
    modifier: Modifier = Modifier,
    yMin: Float = 0f,
    yMax: Float = 10f
) {
    Canvas(modifier = modifier) {
        listOf(0f, 5f, 10f).forEach { gridVal ->
            val y = (1f - (gridVal - yMin) / (yMax - yMin)) * size.height
            drawLine(
                color = color.copy(alpha = 0.15f),
                start = Offset(0f, y),
                end = Offset(size.width, y),
                strokeWidth = 1f
            )
        }

        if (values.size < 2) return@Canvas

        val path = Path()
        val range = (yMax - yMin).coerceAtLeast(0.001f)

        values.forEachIndexed { index, value ->
            val x = index / (values.size - 1f) * size.width
            val y = (1f - (value - yMin) / range) * size.height
            if (index == 0) path.moveTo(x, y) else path.lineTo(x, y)
        }

        drawPath(path = path, color = color, style = Stroke(width = 3f, cap = StrokeCap.Round))

        val lastY = (1f - (values.last() - yMin) / range) * size.height
        drawCircle(color = color, radius = 5f, center = Offset(size.width, lastY))
    }
}
