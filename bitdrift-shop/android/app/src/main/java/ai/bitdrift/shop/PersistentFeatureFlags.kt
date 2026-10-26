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

    /**
     * Flips one flag to its other value (the `flip_flag` command), persisting it and re-recording
     * the exposure and `ff_*` field so the change is visible in the running session.
     * Returns (from, to), or null when [key] is not one of the three flags.
     */
    @OptIn(ExperimentalBitdriftApi::class)
    fun flip(context: Context, key: String): Pair<String, String>? {
        val flag = flags.firstOrNull { it.key == key } ?: return null
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val from = prefs.getString(flag.key, null)?.takeIf { it in flag.values } ?: flag.values.first()
        val to = flag.values.first { it != from }
        prefs.edit().putString(flag.key, to).commit()
        RecordingLogger.setFeatureFlagExposure(flag.key, to)
        RecordingLogger.addField("ff_${flag.key}", to)
        return from to to
    }

    val flagKeys: List<String> get() = flags.map { it.key }

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
