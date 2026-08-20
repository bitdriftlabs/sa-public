package ai.bitdrift.shop

import android.os.SystemClock
import io.bitdrift.capture.Capture.Logger
import io.bitdrift.capture.LogLevel
import io.bitdrift.capture.events.span.Span
import io.bitdrift.capture.events.span.SpanResult
import java.util.UUID
import kotlin.coroutines.cancellation.CancellationException

/**
 * Span helpers the SDK's own `Logger.trackSpan` doesn't cover, plus the cold-start
 * phase breakdown. Mirrors the iOS app's `CaptureBridge`/`ColdStartSpans`, so both
 * platforms emit the same span names into the same `bd-shop-*` workflows.
 *
 * Why not just use `Logger.trackSpan`? Three gaps, all of which matter here:
 *
 *  1. **No `parentSpanId`.** `Logger.startSpan` takes one, but `trackSpan` doesn't
 *     forward it, so nothing wrapped in it can nest under a journey/checkout span.
 *  2. **Not suspend-capable.** Its `block` is `() -> T`, so it cannot wrap a
 *     `LaunchedEffect` body or anything else that suspends — which is every
 *     screen-load and journey-phase span in this app.
 *  3. **Maps every throwable to FAILURE**, including `CancellationException`. On
 *     Android that is the common case, not an edge case: `LaunchedEffect(key)`
 *     cancels its coroutine whenever the key changes or the composable leaves the
 *     composition, so ordinary scrolling would record a stream of "failed" spans
 *     whose partial durations then skew every latency histogram.
 */
object CaptureBridge {

    /**
     * Process start as **epoch** millis, for back-dating the cold-start root span.
     *
     * `ShoppingDemoApp.appStartUptimeMs` is `SystemClock.uptimeMillis()` — monotonic
     * since boot, which is the right clock for the TTI *duration* it was added for,
     * but the wrong domain for a span start time: the SDK feeds a custom
     * `startTimeMs` into `LogAttributesOverrides.OccurredAt(occurredAtTimestampMs)`,
     * an epoch timestamp. Passing uptime straight through would stamp the span's
     * start log somewhere in 1970. Converting here keeps the value anchored to the
     * same instant while putting it in the domain the SDK actually wants.
     *
     * (No iOS equivalent of this trap: `CaptureBridge.processStart` there is already
     * a wall-clock `Date`.)
     */
    val processStartEpochMs: Long by lazy {
        System.currentTimeMillis() - (SystemClock.uptimeMillis() - ShoppingDemoApp.appStartUptimeMs)
    }

    /**
     * `suspend` counterpart of `Logger.trackSpan`, with parent nesting and
     * cancellation mapping. SUCCESS on return, CANCELED on cancellation, FAILURE on
     * anything else; the span is handed to [block] so its own children can nest
     * under it by passing `span?.id` down.
     */
    suspend fun <T> trackSpanSuspend(
        name: String,
        fields: Map<String, String>? = null,
        parentSpanId: UUID? = null,
        block: suspend (Span?) -> T,
    ): T {
        val span = Logger.startSpan(name, LogLevel.INFO, fields, null, parentSpanId)
        try {
            val result = block(span)
            span?.end(SpanResult.SUCCESS)
            return result
        } catch (e: CancellationException) {
            // Not a failure, and its partial duration would skew a latency histogram
            // if recorded as one. Rethrown unchanged so structured concurrency still
            // sees the cancellation.
            span?.end(SpanResult.CANCELED)
            throw e
        } catch (e: Throwable) {
            span?.end(SpanResult.FAILURE)
            throw e
        }
    }

    /**
     * Non-suspending variant, for synchronous work that still needs to nest under a
     * parent span (which `Logger.trackSpan` cannot do).
     */
    fun <T> trackSpanNested(
        name: String,
        fields: Map<String, String>? = null,
        parentSpanId: UUID? = null,
        block: (Span?) -> T,
    ): T {
        val span = Logger.startSpan(name, LogLevel.INFO, fields, null, parentSpanId)
        try {
            val result = block(span)
            span?.end(SpanResult.SUCCESS)
            return result
        } catch (e: CancellationException) {
            span?.end(SpanResult.CANCELED)
            throw e
        } catch (e: Throwable) {
            span?.end(SpanResult.FAILURE)
            throw e
        }
    }
}

/**
 * Breaks cold start into a span waterfall instead of the single opaque number
 * `Logger.logAppLaunchTTI` reports: an `app_cold_start` root with a child span per
 * phase, so a regression can be attributed to SDK init vs. Compose standing the
 * activity up vs. the demo's own prefs bookkeeping.
 *
 * Same span names and shape as the iOS app's `ColdStartSpans`, so `bd-shop-20`
 * charts both platforms.
 *
 * Custom-duration caveat, identical to iOS: `Span.end` only honours a custom
 * duration when **both** `startTimeMs` (at creation) and `endTimeMs` (at end) are
 * supplied — see `Span.end`, which falls back to the default clock unless both are
 * present. So [finish] must pass `endTimeMs` explicitly even though [beginRoot]
 * already supplied a custom start.
 *
 * All three entry points are idempotent: the Compose `LaunchedEffect` that drives
 * [advanceToStateRestore]/[finish] lives inside the Welcome nav destination and
 * therefore re-runs on every navigation back to Welcome, not just at launch.
 * Nulling the references as they close keeps a second pass a no-op instead of
 * emitting a bogus second cold start.
 */
object ColdStartSpans {
    private var root: Span? = null
    private var currentPhase: Span? = null

    /**
     * Opens `app_cold_start` (back-dated to process start) and its `sdk_init` child,
     * then opens `scene_render`. Must be the **last** statement of
     * `ShoppingDemoApp.onCreate()`: everything that method did — `Logger.start`,
     * `setEntityId`, `addField`, the crash-loop handler install — is what `sdk_init`
     * measures, and no span can exist before the SDK it measures has started.
     */
    fun beginRoot() {
        if (root != null) return
        val startedAt = CaptureBridge.processStartEpochMs
        root = Logger.startSpan("app_cold_start", LogLevel.INFO, null, startedAt, null)

        // Both endpoints are already known here (process start, and now), so this one
        // is opened and closed in a single call rather than left open.
        val now = System.currentTimeMillis()
        Logger.startSpan("app_cold_start.sdk_init", LogLevel.INFO, null, startedAt, root?.id)
            ?.end(SpanResult.SUCCESS, null, now)

        // Opens for real, now — Compose standing up the activity and reaching the
        // startup LaunchedEffect needs no back-dating.
        currentPhase = Logger.startSpan("app_cold_start.scene_render", LogLevel.INFO, null, null, root?.id)
    }

    /**
     * Ends `scene_render`, opens `state_restore`. Call as the **first** statement of
     * the startup `LaunchedEffect` in `MainActivity`, before any prefs are read:
     * everything after that point is demo flag/prefs bookkeeping, which belongs to
     * `state_restore` rather than to render time.
     */
    fun advanceToStateRestore() {
        if (root == null) return
        currentPhase?.end(SpanResult.SUCCESS)
        currentPhase = Logger.startSpan("app_cold_start.state_restore", LogLevel.INFO, null, null, root?.id)
    }

    /**
     * Ends `state_restore` and the root together. Call on whichever path the startup
     * sequence takes — including before the fast-crash early return — but after the
     * resume-branch restoration, since that prefs reading/clearing is still state
     * restoration. Not after the auto-start retry loop: waiting for the sim to spin
     * up is the app running, not starting.
     */
    fun finish() {
        val open = root ?: return
        currentPhase?.end(SpanResult.SUCCESS)
        currentPhase = null
        // Custom start time was supplied, so a custom end time is required too or the
        // duration silently reverts to the default clock (see the class doc).
        open.end(SpanResult.SUCCESS, null, System.currentTimeMillis())
        root = null
    }
}
