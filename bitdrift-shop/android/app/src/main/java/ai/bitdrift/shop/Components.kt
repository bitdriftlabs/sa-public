package ai.bitdrift.shop

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.foundation.Image
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import org.json.JSONObject

private const val CAPTURE_SDK_VERSION = "0.23.10"

// Category color mapping
private val categoryColors = mapOf(
    "Electronics" to Color(0xFF6196F3),
    "Clothing" to Color(0xFF9C27B0),
    "Home & Garden" to Color(0xFFFF9800),
    "Sports" to Color(0xFF4CAF50)
)

private val categoryIcons = mapOf(
    "Electronics" to Icons.Default.Phone,
    "Clothing" to Icons.Default.Face,
    "Home & Garden" to Icons.Default.Home,
    "Sports" to Icons.Default.Star
)

// MARK: - Reusable Components

@Composable
fun StepIndicator(current: Int, total: Int = 7) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.padding(vertical = 8.dp)
    ) {
        repeat(total) { index ->
            val step = index + 1
            Box(
                modifier = Modifier
                    .size(12.dp)
                    .background(
                        color = if (step <= current) MaterialTheme.colorScheme.primary else Color.Gray.copy(alpha = 0.3f),
                        shape = CircleShape
                    )
            )
        }
    }
}

@Composable
fun ScreenContainer(
    screenName: String,
    title: String,
    subtitle: String,
    step: Int,
    icon: ImageVector,
    color: Color,
    imageUrl: String? = null,
    logoResId: Int? = null,
    latestSdkVersion: String? = null,
    onBack: (() -> Unit)? = null,
    onCart: (() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.SpaceBetween
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(modifier = Modifier.size(48.dp)) {
                if (onBack != null) {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.Default.ArrowBack,
                            contentDescription = "Back"
                        )
                    }
                }
            }
            Spacer(modifier = Modifier.weight(1f))
            StepIndicator(current = step)
            Spacer(modifier = Modifier.weight(1f))
            Box(modifier = Modifier.size(48.dp)) {
                if (onCart != null) {
                    IconButton(onClick = onCart) {
                        Icon(
                            imageVector = Icons.Default.ShoppingCart,
                            contentDescription = "Cart"
                        )
                    }
                }
            }
        }

        Spacer(modifier = Modifier.weight(1f))

        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            if (logoResId != null) {
                val isOutdated = latestSdkVersion != null && latestSdkVersion != CAPTURE_SDK_VERSION
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth(0.72f)
                            .background(Color(0xFF1A1A2E), shape = RoundedCornerShape(12.dp))
                            .padding(horizontal = 24.dp, vertical = 18.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Image(
                            painter = painterResource(id = logoResId),
                            contentDescription = "Bitdrift Logo",
                            contentScale = ContentScale.Fit,
                            modifier = Modifier.height(44.dp)
                        )
                    }
                    Text(
                        text = "SDK v$CAPTURE_SDK_VERSION${if (isOutdated) " ⚑" else ""}",
                        style = MaterialTheme.typography.labelMedium,
                        color = if (isOutdated) Color(0xFFF57C00) else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.85f)
                    )
                    if (isOutdated) {
                        Text(
                            text = "v$latestSdkVersion available",
                            style = MaterialTheme.typography.labelSmall,
                            color = Color(0xFFF57C00).copy(alpha = 0.75f)
                        )
                    }
                    if (BuildConfig.BITDRIFT_CAPTURE_SOURCE == "AAR") {
                        Text(
                            text = "${BuildConfig.BITDRIFT_LOCAL_AAR_NAME} [AAR]",
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.85f)
                        )
                    }
                    Text(
                        text = "App v${BuildConfig.VERSION_NAME}",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.85f)
                    )
                }
            } else if (imageUrl != null) {
                AsyncImage(
                    model = imageUrl,
                    contentDescription = title,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier
                        .size(120.dp)
                        .clip(CircleShape)
                )
            } else {
                Box(
                    modifier = Modifier
                        .size(100.dp)
                        .background(color.copy(alpha = 0.15f), shape = CircleShape),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(
                        imageVector = icon,
                        contentDescription = null,
                        tint = color,
                        modifier = Modifier.size(44.dp)
                    )
                }
            }

            Text(
                text = title,
                style = MaterialTheme.typography.headlineMedium.copy(fontWeight = FontWeight.Bold)
            )

            Text(
                text = subtitle,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(horizontal = 16.dp)
            )

            // Screens with a logo show version info grouped with the SDK version above;
            // everything else (no logo) shows the app version alone down here.
            if (logoResId == null) {
                Text(
                    text = "App v${BuildConfig.VERSION_NAME}",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.85f)
                )
            }
        }

        Spacer(modifier = Modifier.weight(1f))

        Column(
            verticalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier.fillMaxWidth()
        ) {
            content()
        }
    }
}

@Composable
fun PrimaryButton(
    title: String,
    icon: ImageVector,
    enabled: Boolean = true,
    onClick: () -> Unit
) {
    Button(
        onClick = onClick,
        enabled = enabled,
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 8.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(imageVector = icon, contentDescription = null)
                Text(title, style = MaterialTheme.typography.titleMedium)
            }
            Icon(
                imageVector = Icons.Default.KeyboardArrowRight,
                contentDescription = null
            )
        }
    }
}

@Composable
fun SecondaryButton(
    title: String,
    icon: ImageVector,
    enabled: Boolean = true,
    onClick: () -> Unit
) {
    OutlinedButton(
        onClick = onClick,
        enabled = enabled,
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
        colors = ButtonDefaults.outlinedButtonColors(
            contentColor = MaterialTheme.colorScheme.primary
        )
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 8.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(imageVector = icon, contentDescription = null)
                Text(title, style = MaterialTheme.typography.titleMedium)
            }
            Icon(
                imageVector = Icons.Default.KeyboardArrowRight,
                contentDescription = null
            )
        }
    }
}

@Composable
fun SimButton(
    title: String,
    color: Color,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    Button(
        onClick = onClick,
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
        colors = ButtonDefaults.buttonColors(containerColor = color)
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.Bold),
            textAlign = TextAlign.Center,
            maxLines = 2,
            modifier = Modifier.padding(vertical = 8.dp)
        )
    }
}

@Composable
fun SimulationOverlay(simulationManager: SimulationManager) {
    val loopFlagStatus = listOfNotNull(
        if (simulationManager.crashLoopEnabled) "Crash" else null,
        if (simulationManager.anrAEnabled) "ANR" else null,
        if (simulationManager.forceQuitEnabled) "Quit" else null
    ).let { flags ->
        if (flags.isEmpty()) "No flags" else flags.joinToString(" + ") + " enabled"
    }

    val anrEligibilityNote =
        if (simulationManager.anrAEnabled && simulationManager.activeVariant != SimVariant.VARIANT_A) {
            " (Variant A only)"
        } else {
            ""
        }

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(16.dp),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = Color.Black.copy(alpha = 0.8f))
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                CircularProgressIndicator(
                    modifier = Modifier.size(24.dp),
                    color = Color.White,
                    strokeWidth = 2.dp
                )
                Column {
                    Text(
                        text = if (simulationManager.isInfiniteMode) {
                            "Simulating ${simulationManager.currentRun}/∞"
                        } else {
                            "Simulating ${simulationManager.currentRun}/${simulationManager.totalRuns}"
                        },
                        style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold),
                        color = Color.White
                    )
                    Text(
                        text = simulationManager.activeVariant.label,
                        style = MaterialTheme.typography.bodySmall,
                        color = Color.White.copy(alpha = 0.7f)
                    )
                    Text(
                        text = "$loopFlagStatus$anrEligibilityNote",
                        style = MaterialTheme.typography.bodySmall,
                        color = Color.White.copy(alpha = 0.85f)
                    )
                }
            }
            IconButton(onClick = { simulationManager.cancel() }) {
                Icon(
                    imageVector = Icons.Default.Close,
                    contentDescription = "Cancel",
                    tint = Color.White.copy(alpha = 0.8f)
                )
            }
        }
    }
}

// Full-screen, opaque by design: fast crash mode intentionally skips all navigation
// and UI (see fireFastCrash()'s docs), so without this there is no on-device signal
// telling apart "about to crash in ~300ms-2s" from "the app is stuck." Covers
// whatever Compose is doing underneath rather than a small overlay, since the whole
// point is to be unmistakable.
@Composable
fun FastCrashModeSplash(status: SimulationManager.FastCrashStatus?) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFF1A1A2E)),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
            modifier = Modifier.padding(32.dp)
        ) {
            Icon(
                imageVector = Icons.Default.Warning,
                contentDescription = null,
                tint = Color(0xFFF44336),
                modifier = Modifier.size(56.dp)
            )
            Text(
                text = "FAST CRASH MODE",
                style = MaterialTheme.typography.headlineSmall.copy(
                    fontWeight = FontWeight.Bold,
                    color = Color.White
                )
            )
            if (status == null) {
                CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp)
                Text(
                    text = "Preparing next crash…",
                    style = MaterialTheme.typography.bodyMedium.copy(color = Color.White.copy(alpha = 0.7f))
                )
            } else {
                if (status.oomOnly) {
                    AssistChip(
                        onClick = {},
                        enabled = false,
                        label = { Text("OOM ONLY", color = Color(0xFFFF9800)) },
                        colors = AssistChipDefaults.assistChipColors(containerColor = Color(0xFFFF9800).copy(alpha = 0.15f))
                    )
                }
                Text(
                    text = "Next crash: ${status.kind}",
                    style = MaterialTheme.typography.titleMedium.copy(
                        fontWeight = FontWeight.Bold,
                        color = Color.White
                    ),
                    textAlign = TextAlign.Center
                )
                Text(
                    text = "(${status.context})",
                    style = MaterialTheme.typography.bodyMedium.copy(color = Color.White.copy(alpha = 0.7f))
                )
            }
            Text(
                text = "adb shell am force-stop ai.bitdrift.shop  to stop",
                style = MaterialTheme.typography.bodySmall.copy(
                    color = Color.White.copy(alpha = 0.4f),
                    fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace
                ),
                textAlign = TextAlign.Center
            )
        }
    }
}

@Composable
fun ProductImageRow(products: List<JSONObject>, onProductClick: (String) -> Unit = {}) {
    if (products.isEmpty()) return
    Column(
        verticalArrangement = Arrangement.spacedBy(10.dp),
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(max = 160.dp)
            .verticalScroll(rememberScrollState())
    ) {
        products.forEach { product ->
            val productId = product.optString("id", "")
            Card(
                onClick = { onProductClick(productId) },
                shape = RoundedCornerShape(12.dp),
                modifier = Modifier.fillMaxWidth()
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    AsyncImage(
                        model = product.optString("image_url", ""),
                        contentDescription = product.optString("name", ""),
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.size(64.dp)
                    )
                    Column(modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp)) {
                        Text(
                            text = product.optString("name", ""),
                            style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold),
                            maxLines = 1
                        )
                        Text(
                            text = "$${String.format("%.2f", product.optDouble("price", 0.0))}",
                            style = MaterialTheme.typography.bodySmall
                        )
                    }
                }
            }
        }
    }
}

@Composable
fun CategoryRow(categories: List<JSONObject>, onCategoryClick: (String) -> Unit = {}) {
    if (categories.isEmpty()) return
    Column(
        verticalArrangement = Arrangement.spacedBy(10.dp),
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(max = 160.dp)
            .verticalScroll(rememberScrollState())
    ) {
        categories.forEach { cat ->
            val name = cat.optString("name", "")
            val count = cat.optInt("product_count", 0)
            val color = categoryColors[name] ?: Color.Gray
            val icon = categoryIcons[name] ?: Icons.Default.List
            Card(
                onClick = { onCategoryClick(name) },
                shape = RoundedCornerShape(12.dp),
                colors = CardDefaults.cardColors(containerColor = color.copy(alpha = 0.15f)),
                modifier = Modifier.fillMaxWidth()
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.padding(12.dp)
                ) {
                    Icon(
                        imageVector = icon,
                        contentDescription = name,
                        tint = color,
                        modifier = Modifier.size(32.dp)
                    )
                    Spacer(modifier = Modifier.width(12.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = name,
                            style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold)
                        )
                        Text(
                            text = "$count items",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
                        )
                    }
                    Icon(
                        imageVector = Icons.Default.KeyboardArrowRight,
                        contentDescription = null,
                        tint = color
                    )
                }
            }
        }
    }
}

@Composable
fun RecommendedSection(
    recommendations: List<Pair<JSONObject, Double>>,
    onProductClick: (String) -> Unit
) {
    if (recommendations.isEmpty()) return
    Column(
        verticalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        Text(
            text = "Recommended for You",
            style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.Bold),
            modifier = Modifier.padding(bottom = 4.dp)
        )
        recommendations.take(3).forEach { (product, score) ->
            Card(
                onClick = { onProductClick(product.optString("id", "")) },
                shape = RoundedCornerShape(8.dp),
                modifier = Modifier.fillMaxWidth()
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.padding(8.dp)
                ) {
                    AsyncImage(
                        model = product.optString("image_url", ""),
                        contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier
                            .size(48.dp)
                            .clip(RoundedCornerShape(8.dp))
                    )
                    Column(
                        modifier = Modifier
                            .padding(start = 10.dp)
                            .weight(1f)
                    ) {
                        Text(
                            text = product.optString("name", ""),
                            style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.Bold),
                            maxLines = 1
                        )
                        Text(
                            text = "${(score * 100).toInt()}% match",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.primary
                        )
                    }
                }
            }
        }
    }
}
