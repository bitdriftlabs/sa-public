package ai.bitdrift.shop

import android.content.Context
import io.bitdrift.capture.experimental.ExperimentalBitdriftApi

/**
 * Exactly three install-persistent feature flags (hard cap -- do not add a fourth).
 *
 * Each flag is assigned once, on first launch, and then read back from SharedPreferences on
 * every later launch, so a device keeps the same values across restarts, crashes and new
 * sessions (unlike the `SimVariant` flags in [SimulationManager], which are per-run).
 *
 * bitdrift SDK: [apply] records every flag as both a feature flag exposure (usable as a
 * workflow/chart dimension) and an `ff_*` global field (visible on every log in the session).
 */
object PersistentFeatureFlags {
    private const val PREFS = "persistent_flags"

    private class Flag(val key: String, val values: List<String>)

    // Hard cap of 3 -- see README "Persistent feature flags".
    private val flags = listOf(
        Flag("express_checkout", listOf("enabled", "disabled")),
        Flag("product_card_layout", listOf("grid", "list")),
        Flag("free_shipping_banner", listOf("control", "treatment")),
    )

    init {
        check(flags.size <= 3) { "At most 3 persistent feature flags are allowed" }
    }

    /** Call once from `Application.onCreate()` after `Logger.start()`. */
    @OptIn(ExperimentalBitdriftApi::class)
    fun apply(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        for (flag in flags) {
            val value = prefs.getString(flag.key, null)?.takeIf { it in flag.values }
                ?: flag.values.random().also { prefs.edit().putString(flag.key, it).apply() }
            RecordingLogger.setFeatureFlagExposure(flag.key, value)
            RecordingLogger.addField("ff_${flag.key}", value)
        }
    }
}
