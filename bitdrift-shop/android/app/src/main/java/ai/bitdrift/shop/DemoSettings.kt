package ai.bitdrift.shop

import android.content.Context

enum class SessionMode(val id: String) {
    /** Default: the sim starts a new session at the start of every journey (what the workflows assume). */
    PER_JOURNEY("per_journey"),

    /** One session spans several journeys and background/foreground transitions, like a real user's. */
    REALISTIC("realistic");

    companion object {
        fun fromId(id: String?) = entries.firstOrNull { it.id == id } ?: PER_JOURNEY
    }
}

/**
 * Persisted demo settings (SharedPreferences store `demo_settings`, spec/faults.yaml other_persisted).
 *
 * [SessionMode] is read once at SDK start, because `SessionConfiguration` cannot change afterwards:
 * toggling it on the Advanced screen takes effect on the next launch. [activeSessionMode] is what
 * this process actually started with.
 */
object DemoSettings {
    private const val PREFS = "demo_settings"
    private const val KEY_SESSION_MODE = "session_mode"
    private const val KEY_LOSE_ORDERS = "lose_orders"

    /** Minutes of inactivity after which `realistic` mode rotates to a new session. */
    const val REALISTIC_INACTIVITY_MINUTES = 30

    @Volatile
    var activeSessionMode: SessionMode = SessionMode.PER_JOURNEY

    private fun prefs(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun sessionMode(c: Context): SessionMode = SessionMode.fromId(prefs(c).getString(KEY_SESSION_MODE, null))

    fun setSessionMode(c: Context, mode: SessionMode) {
        prefs(c).edit().putString(KEY_SESSION_MODE, mode.id).commit()
    }

    /** Demo chaos switch: makes order-confirmation lookups fail so the `order_lost` critical log can be shown. */
    fun loseOrders(c: Context): Boolean = prefs(c).getBoolean(KEY_LOSE_ORDERS, false)

    fun setLoseOrders(c: Context, on: Boolean) {
        prefs(c).edit().putBoolean(KEY_LOSE_ORDERS, on).commit()
    }
}
