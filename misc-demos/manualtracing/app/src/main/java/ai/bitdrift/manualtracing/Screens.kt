package ai.bitdrift.manualtracing

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import io.bitdrift.capture.Capture.Logger
import io.bitdrift.capture.CaptureResult

private val Green = Color(0xFF2E7D32)
private val Red = Color(0xFFC62828)
private val Orange = Color(0xFFE65100)
private val Gray = Color(0xFF757575)
private val TracedBlue = Color(0xFF1565C0)
private val OkHttpPurple = Color(0xFF6A1B9A)
private val LogoDark = Color(0xFF0F0F1A)

@Composable
fun TracingScreen(vm: NetworkViewModel = viewModel()) {
    val results by vm.results.collectAsState()
    val isSimulatingManual by vm.isSimulatingManual.collectAsState()
    val isSimulatingOkHttp by vm.isSimulatingOkHttp.collectAsState()
    val isRunning10xManual by vm.isRunning10xManual.collectAsState()
    val isRunning10xOkHttp by vm.isRunning10xOkHttp.collectAsState()
    val manualLoopProgress by vm.manualLoopProgress.collectAsState()
    val manual10xProgress by vm.manual10xProgress.collectAsState()
    val okHttpLoopCount by vm.okHttpLoopCount.collectAsState()
    val isTracingActive by vm.isTracingActive.collectAsState()

    var deviceCode by remember { mutableStateOf<String?>(null) }
    var deviceCodeLoading by remember { mutableStateOf(false) }
    var showDeviceDialog by remember { mutableStateOf(false) }
    val clipboard = LocalClipboardManager.current

    if (showDeviceDialog && deviceCode != null) {
        AlertDialog(
            onDismissRequest = { showDeviceDialog = false },
            title = { Text("Device Code") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        "Enter this code in the bitdrift dashboard to stream logs from this device live.",
                        style = MaterialTheme.typography.bodyMedium,
                    )
                    Text(
                        deviceCode!!,
                        style = MaterialTheme.typography.headlineSmall.copy(
                            fontWeight = FontWeight.Bold,
                            fontFamily = FontFamily.Monospace,
                        ),
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    clipboard.setText(AnnotatedString(deviceCode!!))
                    showDeviceDialog = false
                }) { Text("Copy & Close") }
            },
            dismissButton = {
                TextButton(onClick = { showDeviceDialog = false }) { Text("Close") }
            },
        )
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .statusBarsPadding()
            .padding(horizontal = 16.dp),
    ) {
        // ── Logo + SDK version ────────────────────────────────────────────────────────────────
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 16.dp, bottom = 8.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(LogoDark, shape = RoundedCornerShape(12.dp))
                    .padding(horizontal = 24.dp, vertical = 14.dp),
                contentAlignment = Alignment.Center,
            ) {
                Image(
                    painter = painterResource(id = R.drawable.bitdrift_logo),
                    contentDescription = "bitdrift logo",
                    contentScale = ContentScale.Fit,
                    modifier = Modifier.height(36.dp),
                )
            }
            Text(
                "app v${BuildConfig.APP_VERSION}  ·  capture v${BuildConfig.CAPTURE_SDK_VERSION}",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.55f),
                fontFamily = FontFamily.Monospace,
            )
        }

        // ── Tracing status badge + Device Code button ─────────────────────────────────────────
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            SurfaceChip(
                label = if (isTracingActive) "Tracing Active" else "Tracing Inactive",
                color = if (isTracingActive) Green else Gray,
            )
            Button(
                onClick = {
                    deviceCodeLoading = true
                    Logger.createTemporaryDeviceCode { result ->
                        deviceCodeLoading = false
                        deviceCode = when (result) {
                            is CaptureResult.Success -> result.value
                            is CaptureResult.Failure -> "Error: ${result.error.message}"
                        }
                        showDeviceDialog = true
                    }
                },
                enabled = !deviceCodeLoading,
                shape = RoundedCornerShape(8.dp),
                contentPadding = PaddingValues(horizontal = 14.dp, vertical = 8.dp),
            ) {
                if (deviceCodeLoading) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(14.dp),
                        strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.onPrimary,
                    )
                    Spacer(Modifier.width(6.dp))
                }
                Text("Device Code", style = MaterialTheme.typography.labelLarge)
            }
        }

        // ── Loop control buttons ──────────────────────────────────────────────────────────────
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Button(
                onClick = { if (isSimulatingManual) vm.cancelManualSim() else vm.startManualSim() },
                modifier = Modifier.weight(1f),
                shape = RoundedCornerShape(10.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = if (isSimulatingManual) Red else Orange,
                ),
            ) {
                if (isSimulatingManual) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(14.dp),
                        strokeWidth = 2.dp,
                        color = LocalContentColor.current,
                    )
                } else {
                    Icon(Icons.Default.PlayArrow, contentDescription = null, modifier = Modifier.size(16.dp))
                }
                Spacer(Modifier.width(4.dp))
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        if (isSimulatingManual) "Stop" else "Loop Journey",
                        fontWeight = FontWeight.Bold,
                        fontSize = 13.sp,
                    )
                    if (isSimulatingManual && manualLoopProgress != null) {
                        val p = manualLoopProgress!!
                        Text(
                            if (p.stepIdx < 0) p.screenName
                            else "${p.screenName}  ${p.stepIdx + 1}/${p.total}",
                            fontSize = 10.sp,
                            fontFamily = FontFamily.Monospace,
                            color = LocalContentColor.current.copy(alpha = 0.85f),
                        )
                    } else {
                        Text(
                            "URLConnection",
                            fontSize = 10.sp,
                            fontFamily = FontFamily.Monospace,
                            color = LocalContentColor.current.copy(alpha = 0.8f),
                        )
                        Text(
                            "manual tracing",
                            fontSize = 10.sp,
                            fontFamily = FontFamily.Monospace,
                            color = LocalContentColor.current.copy(alpha = 0.6f),
                        )
                    }
                }
            }

            Button(
                onClick = { if (isSimulatingOkHttp) vm.cancelOkHttpSim() else vm.startOkHttpSim() },
                modifier = Modifier.weight(1f),
                shape = RoundedCornerShape(10.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = if (isSimulatingOkHttp) Red else OkHttpPurple,
                ),
            ) {
                if (isSimulatingOkHttp) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(14.dp),
                        strokeWidth = 2.dp,
                        color = LocalContentColor.current,
                    )
                } else {
                    Icon(Icons.Default.PlayArrow, contentDescription = null, modifier = Modifier.size(16.dp))
                }
                Spacer(Modifier.width(4.dp))
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        if (isSimulatingOkHttp) "Stop" else "Loop Journey",
                        fontWeight = FontWeight.Bold,
                        fontSize = 13.sp,
                    )
                    if (isSimulatingOkHttp && okHttpLoopCount > 0) {
                        Text(
                            "req $okHttpLoopCount",
                            fontSize = 10.sp,
                            fontFamily = FontFamily.Monospace,
                            color = LocalContentColor.current.copy(alpha = 0.85f),
                        )
                    } else {
                        Text(
                            "OkHttp",
                            fontSize = 10.sp,
                            fontFamily = FontFamily.Monospace,
                            color = LocalContentColor.current.copy(alpha = 0.8f),
                        )
                        Text(
                            "autoinstrumentation",
                            fontSize = 10.sp,
                            fontFamily = FontFamily.Monospace,
                            color = LocalContentColor.current.copy(alpha = 0.6f),
                        )
                    }
                }
            }
        }

        // ── Run 5x Journey buttons ───────────────────────────────────────────────────────────
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Button(
                onClick = { if (isRunning10xManual) vm.cancelManual5x() else vm.runManual5x() },
                modifier = Modifier.weight(1f),
                shape = RoundedCornerShape(10.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = if (isRunning10xManual) Red else Orange.copy(alpha = 0.75f),
                ),
            ) {
                if (isRunning10xManual) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(14.dp),
                        strokeWidth = 2.dp,
                        color = LocalContentColor.current,
                    )
                } else {
                    Icon(Icons.Default.PlayArrow, contentDescription = null, modifier = Modifier.size(16.dp))
                }
                Spacer(Modifier.width(4.dp))
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        if (isRunning10xManual) "Stop" else "Run 5x Journey",
                        fontWeight = FontWeight.Bold,
                        fontSize = 13.sp,
                    )
                    Text(
                        if (isRunning10xManual && manual10xProgress != null) {
                            val p = manual10xProgress!!
                            if (p.stepIdx < 0) p.screenName
                            else "${p.screenName}  ${p.stepIdx + 1}/${p.total}"
                        } else "URLConnection",
                        fontSize = 10.sp,
                        fontFamily = FontFamily.Monospace,
                        color = LocalContentColor.current.copy(alpha = 0.85f),
                    )
                }
            }

            Button(
                onClick = { if (isRunning10xOkHttp) vm.cancelOkHttp5x() else vm.runOkHttp5x() },
                modifier = Modifier.weight(1f),
                shape = RoundedCornerShape(10.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = if (isRunning10xOkHttp) Red else OkHttpPurple.copy(alpha = 0.75f),
                ),
            ) {
                if (isRunning10xOkHttp) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(14.dp),
                        strokeWidth = 2.dp,
                        color = LocalContentColor.current,
                    )
                } else {
                    Icon(Icons.Default.PlayArrow, contentDescription = null, modifier = Modifier.size(16.dp))
                }
                Spacer(Modifier.width(4.dp))
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        if (isRunning10xOkHttp) "Stop" else "Run 5x Journey",
                        fontWeight = FontWeight.Bold,
                        fontSize = 13.sp,
                    )
                    Text(
                        "OkHttp",
                        fontSize = 10.sp,
                        fontFamily = FontFamily.Monospace,
                        color = LocalContentColor.current.copy(alpha = 0.85f),
                    )
                }
            }
        }

        // ── Clear button ──────────────────────────────────────────────────────────────────────
        OutlinedButton(
            onClick = { vm.clearResults() },
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 10.dp),
            shape = RoundedCornerShape(10.dp),
            enabled = results.isNotEmpty() && !isSimulatingManual && !isSimulatingOkHttp,
        ) {
            Icon(Icons.Default.Clear, contentDescription = null, modifier = Modifier.size(16.dp))
            Spacer(Modifier.width(6.dp))
            Text("Clear Results")
        }

        // ── Request history (fixed scrollable panel) ──────────────────────────────────────────
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f),
        ) {
            if (results.isEmpty()) {
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        "Tap Loop URLConnection or Loop OkHttp to start firing requests.\n" +
                        "Trace headers are injected automatically when a workflow activates tracing.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f),
                        textAlign = TextAlign.Center,
                    )
                }
            } else {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                    contentPadding = PaddingValues(bottom = 16.dp),
                ) {
                    items(results) { result ->
                        RequestCard(result)
                    }
                }
            }
        }
    }
}

@Composable
private fun RequestCard(result: RequestResult) {
    val statusColor = when {
        !result.success -> Red
        result.statusCode == null -> Red
        result.statusCode in 200..299 -> Green
        result.statusCode in 300..399 -> Orange
        else -> Red
    }
    val clientColor = if (result.clientType == "OkHttp") OkHttpPurple else Orange

    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(10.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
    ) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (result.stepName != null) {
                    Text(
                        result.stepName,
                        style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Bold),
                        color = MaterialTheme.colorScheme.onSurface,
                        modifier = Modifier.weight(1f),
                    )
                } else {
                    Text(
                        result.method,
                        style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold),
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.padding(end = 6.dp),
                    )
                    Text(
                        result.url.removePrefix("https://"),
                        style = MaterialTheme.typography.bodySmall,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f),
                    )
                }
                Spacer(Modifier.width(8.dp))
                Text(
                    result.statusCode?.toString() ?: "ERR",
                    style = MaterialTheme.typography.labelLarge.copy(
                        fontWeight = FontWeight.Bold,
                        color = statusColor,
                    ),
                )
            }
            if (result.stepName != null) {
                Text(
                    "${result.method} ${result.url.removePrefix("https://")}",
                    style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.45f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }

            Row(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                SurfaceChip(label = result.clientType, color = clientColor, small = true)

                Text(
                    "${result.durationMs} ms",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                )

                if (result.clientType == "OkHttp") {
                    SurfaceChip(label = "auto", color = OkHttpPurple, small = true)
                } else if (result.traceId != null) {
                    SurfaceChip(label = "traced", color = TracedBlue, small = true)
                    Text(
                        result.traceId.take(16) + "…",
                        style = MaterialTheme.typography.bodySmall.copy(
                            fontFamily = FontFamily.Monospace,
                            fontSize = 10.sp,
                        ),
                        color = TracedBlue,
                    )
                } else {
                    Text(
                        "no trace",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.35f),
                    )
                }

                result.error?.let {
                    Text(
                        it.take(40),
                        style = MaterialTheme.typography.bodySmall,
                        color = Red,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }
    }
}

@Composable
private fun SurfaceChip(
    label: String,
    color: Color,
    modifier: Modifier = Modifier,
    small: Boolean = false,
) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(50),
        color = color.copy(alpha = 0.12f),
    ) {
        Text(
            label,
            style = if (small) MaterialTheme.typography.labelSmall else MaterialTheme.typography.labelMedium,
            color = color,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(
                horizontal = if (small) 6.dp else 10.dp,
                vertical = if (small) 2.dp else 4.dp,
            ),
        )
    }
}
