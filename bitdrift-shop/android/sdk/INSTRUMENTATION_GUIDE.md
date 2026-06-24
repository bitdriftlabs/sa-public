# bitdrift Instrumentation Guide (Android)

A step-by-step checklist for wiring up the bitdrift Capture SDK. Each step lights up a specific product feature. Follow them in order — later steps build on earlier ones.

The order is tuned for a proof-of-concept: stand up the SDK (1–3), then light up the timeline with the highest-value signals first — screen views, user identity, and network (4–6) — before layering on logs, performance, and operational features. This follows bitdrift's [Integration first steps](https://docs.bitdrift.io/product/first-steps), which instruments the user-facing journey (screen views) ahead of network. The [bd-instrumentation skill](https://blog.bitdrift.io/post/skill-that-instruments-mobile-sdk) wires network slightly earlier — either way, these three sit at the top of the value chain, right after the logger. The categories are independent, so reorder them to fit your demo.

Code examples are in Kotlin and reference the [Bitdrift Shop demo app](README.md) where each pattern is already implemented.

---

## Using this guide with bd skills

This guide is meant to be used alongside **bitdrift's agent skills**, which give an AI coding agent the operational logic to actually carry out — and verify — the steps below:

- **bd-instrumentation** — installs and instruments the Capture SDK on Android, iOS, and React Native. It detects the platform and whether the SDK is already present, then performs a fresh install or extends an existing integration. This document is the human-readable, Android-focused companion to that skill.
- **bd-docs** — fetches live bitdrift documentation at query time (the `$bd-docs` references throughout this guide point to it).
- **bd-cli** — drives the `bd` CLI for symbol/source-map uploads, workflows, session/issue queries, and key management.

The skills drive the **`bd` CLI** (also used directly for the symbol/source-map uploads in Step 12), a separate tool. Install and authenticate it first (macOS, Homebrew):

```bash
brew tap bitdriftlabs/bd
brew install bd
bd auth   # browser login; for CI/automation use --api-key <key> or the BD_API_KEY env var
```

See the [CLI Quickstart](https://docs.bitdrift.io/cli/quickstart).

Then install the skills with [skills.sh](https://skills.sh/) (requires `node`/`npm` — `brew install node`):

```bash
npx skills add bitdriftlabs/bd-skills
# update later with:
npx skills update --all
```

The skills follow the [agentskills.io](https://agentskills.io/) open standard and work with Claude Code, Cursor, Codex, Copilot, and any skills-compatible agent. See the [Agent Skills docs](https://docs.bitdrift.io/product/skills/overview).

> **Already have the skills?** Just ask your agent to do the work — e.g. *"install the bitdrift Capture SDK in this app and add screen tracking and network monitoring"* — and it will follow `bd-instrumentation`. Use this guide as the reference for what each step unlocks and how it maps to the demo app.

---

## 1. Add the dependency

Add the Capture SDK and Gradle plugin to your project. The plugin handles automatic OkHttp instrumentation and Proguard mapping uploads.

```kotlin
// build.gradle.kts (project root)
plugins {
    id("io.bitdrift.capture-plugin") version "<version>"
}

// app/build.gradle.kts
dependencies {
    implementation("io.bitdrift:capture:<version>")
}
```

**Demo:** [build.gradle.kts](build.gradle.kts), [app/build.gradle.kts](app/build.gradle.kts)

**Docs:** [SDK Quickstart](https://docs.bitdrift.io/sdk/quickstart)

**Unlocks:** Everything. No other step works without this.

> _POC criteria: the prerequisite every success criterion rides on._

---

## 2. Start the Logger

Call `Logger.start()` as early as possible in `Application.onCreate()` — before any other SDK call, before registering lifecycle callbacks, before logging anything.

```kotlin
// Application.kt
import io.bitdrift.capture.Capture.Logger
import io.bitdrift.capture.providers.session.SessionStrategy

class MyApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Logger.start(
            apiKey = BuildConfig.BITDRIFT_SDK_KEY,
            sessionStrategy = SessionStrategy.Fixed(),
        )
    }
}
```

**Demo:** [ShoppingDemoApp.kt](app/src/main/java/ai/bitdrift/shop/ShoppingDemoApp.kt)

**Docs:** [Configuration](https://docs.bitdrift.io/sdk/features/configuration), [Automatic Instrumentation](https://docs.bitdrift.io/sdk/features/automatic-instrumentation)

**Unlocks:** Instant Insights dashboards (app launches, crashes, network, resources), session timeline, all automatic instrumentation (memory pressure, battery, orientation changes, slow frames, thermal state).

> _POC criteria: helps evaluate crash detection, memory monitoring, and visual performance — these OOTB signals light up automatically._

> The SDK begins collecting device telemetry immediately after `start()`. No additional calls are needed for the built-in signals.

---

## 3. Confirm session strategy

`sessionStrategy` is a required parameter of the `Logger.start()` call above. Default to `SessionStrategy.Fixed()` — it starts a fresh session on every process launch, which is the simplest to reason about and ideal for demos and verification.

```kotlin
sessionStrategy = SessionStrategy.Fixed()  // the default choice
```

Optionally switch to `SessionStrategy.ActivityBased()` if you need sessions to persist across process restarts and rotate only after a period of inactivity (default 30 minutes, configurable) — useful for user-facing flows where one journey may span a backgrounded app.

**Demo:** [ShoppingDemoApp.kt](app/src/main/java/ai/bitdrift/shop/ShoppingDemoApp.kt) (`SessionStrategy.Fixed()` in `Logger.start()`)

**Docs:** [Session Management](https://docs.bitdrift.io/sdk/features/session-management)

**Unlocks:** Correct session grouping in Timeline. Without this, every session boundary in the dashboard is either too coarse (all data in one session) or too granular (new session on every background).

> _POC criteria: helps evaluate session management — full capture without the cost–coverage trade-off._

---

## 4. Instrument screen views

Call `Logger.logScreenView(name)` every time the user navigates to a new screen. Use a stable, snake_case name — it becomes the node label in the Sankey diagram.

**Option A — per-screen DisposableEffect** (simple, works for manual navigation):

```kotlin
// MyScreen.kt — fires when the composable enters composition
@Composable
fun MyScreen() {
    DisposableEffect(Unit) {
        Logger.logScreenView("my_screen")
        onDispose { }
    }
    // screen content
}
```

**Option B — centralized NavController listener** (preferred when using Compose Navigation, works for both user navigation and programmatic navigation):

```kotlin
// MainActivity.kt — fires once per navigate() call, independent of Compose timing
DisposableEffect(navController) {
    val listener = NavController.OnDestinationChangedListener { _, destination, _ ->
        val screenName = destinationToScreenName(destination.route ?: return@OnDestinationChangedListener)
        Logger.logScreenView(screenName)
    }
    navController.addOnDestinationChangedListener(listener)
    onDispose { navController.removeOnDestinationChangedListener(listener) }
}

// Map route templates to stable screen names
private fun destinationToScreenName(route: String): String = when (route) {
    "welcome" -> "Welcome"
    "browse"  -> "Browse"
    "productDetail/{source}/{productId}" -> "ProductDetail"
    // ...
    else -> route
}
```

The demo uses Option B. It centralizes all screen view logging in `MainActivity` via `OnDestinationChangedListener`, so screen views fire for user navigation AND simulator navigation (programmatic `NavController.navigate()`) at the same instant, without relying on Compose composition timing. `ScreenLogger` wraps `Logger.logScreenView()` and adds a local debug log.

**Demo:** [MainActivity.kt](app/src/main/java/ai/bitdrift/shop/MainActivity.kt) (`destinationToScreenName`, `OnDestinationChangedListener`), [ScreenLogger.kt](app/src/main/java/ai/bitdrift/shop/ScreenLogger.kt)

**Docs:** [Automatic Instrumentation → Screen Views](https://docs.bitdrift.io/sdk/features/automatic-instrumentation)

**Unlocks:** User Journey (Sankey) diagram in Instant Insights. Each screen appears as a node; edge thickness shows how many users flowed through that transition. This is the foundation for funnel analysis — you cannot build a Sankey without screen view events.

> _POC criteria: covers the screen-names pre-work, and helps evaluate per-screen crash analytics._

---

## 5. Identify users with Entity ID

Call `Logger.setEntityId()` whenever you know who the user is — on login, at the start of a session, or when an anonymous ID is established. The value is hashed; the plaintext is never stored.

```kotlin
// After sign-in
Logger.setEntityId(userId)

// After sign-out — clearing supported soon
```

**Demo:** [SimulationManager.kt](app/src/main/java/ai/bitdrift/shop/SimulationManager.kt) (rotates a fixed entity list so each simulated journey appears as a distinct user — see [README-refs.md#entities](README-refs.md#entities) for the full list)

**Docs:** [Entity ID (SDK)](https://docs.bitdrift.io/sdk/features/entity-id), [Entities (product)](https://docs.bitdrift.io/product/entities)

**Unlocks:** The Entities feature. In the bitdrift dashboard, search for any entity by name to see all their sessions, crashes, devices, and last location. Use **Record Next Online** to queue a session recording for their next app open. Bookmark entities to share them with your team's public bookmarks list.

> _POC criteria: helps evaluate ad-hoc debugging — retrieve any user's session on demand._

---

## 6. Capture network traffic

This is the single highest-value instrumentation after starting the logger, and it is near-automatic. Add `CaptureOkHttpEventListenerFactory` to your `OkHttpClient` and every request and response is logged with timing breakdowns (DNS, TLS, TTFB, total), status codes, and sizes.

```kotlin
// ApiClient.kt
import io.bitdrift.capture.network.okhttp.CaptureOkHttpEventListenerFactory
import okhttp3.OkHttpClient

private val client = OkHttpClient.Builder()
    .eventListenerFactory(CaptureOkHttpEventListenerFactory())
    .build()
```

If you have multiple OkHttp clients (e.g., one per API host), add the factory to each one.

**Demo:** [ApiClient.kt](app/src/main/java/ai/bitdrift/shop/ApiClient.kt)

**Docs:** [HTTP Traffic Logs](https://docs.bitdrift.io/sdk/features/http-traffic-logs)

**Unlocks:** Network tab in Instant Insights (p50/p95 latency, error rate, throughput by endpoint). Network events appear on the session Timeline alongside custom logs and screen views, so you can correlate a payment failure log with the exact HTTP 500 that caused it.

> _POC criteria: covers the networking pre-work, and helps evaluate network monitoring — unsampled latency, error rates, and throughput per endpoint._

### ⚠️ Collapse high-cardinality paths — do not skip this

When a URL path embeds a dynamic segment — user ID, product ID, session token, UUID — every request becomes a *distinct* path value. The dashboard groups network metrics by path, and bitdrift enforces **cardinality limits**: once a metric exceeds ~1,000 group-by dimensions per ~30 minutes (or 20,000 total across platform/app/version), metrics are **silently dropped** and the chart falls back or breaks. Unbounded paths are the most common way to hit this, so this step is required, not optional.

Collapse dynamic segments into a stable template with the `x-capture-path-template` request header, so `/api/products/abc123` and `/api/products/xyz789` both report as a single endpoint:

```kotlin
// Request builder — one canonical endpoint instead of one per ID
.addHeader("x-capture-path-template", "/api/products/<id>")
```

The SDK records this as `_path_template` instead of the raw path. If the header is absent the SDK attempts to auto-detect and replace high-cardinality segments with `<id>`, but explicit templates are far more reliable — **set one on every route that contains a dynamic segment.**

**Demo:** [ApiClient.kt](app/src/main/java/ai/bitdrift/shop/ApiClient.kt) (the `inventoryLookup` request deliberately floods unbounded paths to demonstrate the problem; the `x-capture-path-template` fix is shown inline)

**Docs:** [HTTP Traffic Logs → path template](https://docs.bitdrift.io/sdk/features/http-traffic-logs), [Workflow cardinality limits](https://docs.bitdrift.io/product/workflows/actions)

---

## 7. Emit structured custom logs

Use stable event names as the log message and put all variable data in fields. This enables exact matching in Workflow conditions without regex.

```kotlin
// Good: stable event name, variable data in fields
Logger.logInfo(mapOf("checkout_type" to "guest", "variant" to "A")) { "checkout_started" }
Logger.logError(mapOf("payment_method" to "card", "order_id" to orderId)) { "payment_failed" }

// Bad: variable data interpolated into the message
Logger.logInfo { "checkout started: guest, variant A" }  // can't match on fields
```

**Log level guidance:**

| Level | When to use |
|-------|-------------|
| `logTrace` / `logDebug` | Development-only noise; filtered out in production by default |
| `logInfo` | Business events: user actions, state transitions, milestones |
| `logWarning` | Degraded state: payment retry, memory pressure, slow response |
| `logError` | Failures: payment failed, API error, checkout abandoned |

**Pass Throwable to capture stack traces:**

```kotlin
try {
    ApiClient.checkout()
} catch (e: Exception) {
    Logger.logError(e, mapOf("checkout_type" to "guest")) { "checkout_failed" }
    // Adds _error and _error_details fields automatically
}
```

**Demo:** [AppLifecycleCallbacks.kt](app/src/main/java/ai/bitdrift/shop/AppLifecycleCallbacks.kt), [Screens.kt](app/src/main/java/ai/bitdrift/shop/Screens.kt), [SimulationManager.kt](app/src/main/java/ai/bitdrift/shop/SimulationManager.kt)

**Docs:** [Custom Logs](https://docs.bitdrift.io/sdk/features/custom-logs)

**Unlocks:** Workflow matching, custom metrics (count, rate, histogram of any field value), Timeline breadcrumbs, alert triggers. Every other product feature depends on structured logs as its input signal.

> _POC criteria: covers the beacon/analytics-event pre-work, and helps evaluate log forwarding & integration._

---

## 8. Attach global fields

Global fields attach to every log emitted after the call. Use them for context that is true for the duration of a session or lifecycle state — app variant, user tier, build channel.

```kotlin
// Set at startup — attached to every log in the app's lifetime
Logger.addField("app_variant", "sdk-demo")

// Set when the user signs in — attached to all subsequent logs
Logger.addField("user_id", userId)

// Remove when the user signs out or context changes
Logger.removeField("user_id")
```

For fields that must survive process restart or come from a data source outside the SDK, implement `FieldProvider`:

```kotlin
// Reads user_id from SharedPreferences on every log — survives restarts
class UserIdFieldProvider(private val context: Context) : FieldProvider {
    override fun invoke(): Fields {
        val id = context.getSharedPreferences("user_session", MODE_PRIVATE)
            .getString("user_id", null)
        return if (id.isNullOrEmpty()) emptyMap() else mapOf("user_id" to id)
    }
}

Logger.start(
    apiKey = BuildConfig.BITDRIFT_SDK_KEY,
    sessionStrategy = SessionStrategy.Fixed(),
    fieldProviders = listOf(UserIdFieldProvider(applicationContext)),
)
```

> `user_id` is a special field name: when present, it appears in the Timeline session header, making it easy to identify whose session you are viewing.

**Demo:** [ShoppingDemoApp.kt](app/src/main/java/ai/bitdrift/shop/ShoppingDemoApp.kt)

**Docs:** [Fields](https://docs.bitdrift.io/sdk/features/fields)

**Unlocks:** Dashboard filtering and slicing by any global field. For example, filter all sessions to `app_variant = "canary"` to isolate a release cohort, or filter to `user_id = "X"` to follow a specific user across sessions.

> _POC criteria: helps evaluate insights & visualization — slice dashboards by any cohort._

---

## 9. Report app launch TTI

Record the time from process start to first interactive frame. Call this once — only the first call per `Logger.start()` takes effect.

```kotlin
// Application.kt — capture process start at class-load time
val appStartUptimeMs: Long = SystemClock.uptimeMillis()
```

```kotlin
// MainActivity.kt — report after the first frame is drawn
val contentView = findViewById<View>(android.R.id.content)
contentView.post {
    val ttiMs = SystemClock.uptimeMillis() - MyApp.appStartUptimeMs
    Logger.logAppLaunchTTI(ttiMs.milliseconds)
}
```

**Demo:** [ShoppingDemoApp.kt](app/src/main/java/ai/bitdrift/shop/ShoppingDemoApp.kt) (process start), [MainActivity.kt](app/src/main/java/ai/bitdrift/shop/MainActivity.kt) (report)

**Docs:** [Automatic Instrumentation → TTI](https://docs.bitdrift.io/sdk/features/automatic-instrumentation), [Instant Insights](https://docs.bitdrift.io/product/instant-insights/overview)

**Unlocks:** App Launch TTI chart in Instant Insights → UX. p50/p95/p99 latency histograms across your whole user population.

> _POC criteria: helps evaluate event tracking — unsampled p50/p90/p99 for a key flow._

---

## 10. Measure operations with custom spans

Use spans to measure the duration of any multi-step operation. A span emits two logs — `span_type=start` and `span_type=end` — with a `_duration_ms` field on the end log.

```kotlin
import io.bitdrift.capture.LogLevel
import io.bitdrift.capture.events.span.SpanResult

// Basic span
val span = Logger.startSpan(
    name = "checkout",
    level = LogLevel.INFO,
    fields = mapOf("checkout_type" to "guest"),
)
// ... do work ...
span?.end(SpanResult.SUCCESS, mapOf("payment_method" to "card"))
// or: span?.end(SpanResult.FAILURE) / SpanResult.CANCELED
```

**Nested spans** link parent and child via `parentSpanId`, creating a waterfall hierarchy in the session timeline:

```kotlin
// Parent span — root of the shopping journey
val journeySpan = Logger.startSpan(
    name = "journey",
    level = LogLevel.INFO,
    fields = mapOf("entity" to entity),
)

// Child span — links to parent via journeySpan.id (a UUID)
val checkoutSpan = Logger.startSpan(
    name = "checkout",
    level = LogLevel.INFO,
    fields = mapOf("checkout_type" to if (isGuest) "guest" else "signin"),
    parentSpanId = journeySpan?.id,
)

// End in reverse order
checkoutSpan?.end(SpanResult.SUCCESS, mapOf("payment_method" to paymentMethod))
journeySpan?.end(SpanResult.SUCCESS)
```

`Span.end()` is idempotent — subsequent calls after the first are no-ops, so it is safe to call at multiple exit points.

For synchronous operations, use the `trackSpan` convenience wrapper. It ends the span `SUCCESS` if the block returns and `FAILURE` if it throws, and returns the block's value directly:

```kotlin
val recommendations = Logger.trackSpan("score_products", LogLevel.INFO, mapOf("product_id" to pid)) {
    RecommendationEngine.scoreProducts(catalogJson, pid)
}
```

**Demo:** [SimulationManager.kt](app/src/main/java/ai/bitdrift/shop/SimulationManager.kt) — three nested spans per journey: `journey` (root), `product_discovery` (child), `checkout` (child). [Screens.kt](app/src/main/java/ai/bitdrift/shop/Screens.kt) — `trackSpan("score_products")` around the recommendation scoring.

**Docs:** [Spans (SDK)](https://docs.bitdrift.io/sdk/features/spans), [Spans Visualization](https://docs.bitdrift.io/product/timeline/spans-visualization)

**Unlocks:** Spans Visualization in the session Timeline (waterfall chart showing each span as a duration bar). Query `_duration_ms` in Workflows to plot p50/p95 of any operation across your whole user base. Compare operation duration by user segment.

> _POC criteria: helps evaluate event tracking — precise percentile durations for critical flows like login or checkout._

---

## 11. Implement device identification for support

Surface a device code or session URL inside your app so support agents can pull the exact session from the dashboard without needing device logs or a repro case.

```kotlin
// Generate a short-lived device code (~24h TTL) and copy it to clipboard
Logger.createTemporaryDeviceCode { result ->
    when (result) {
        is CaptureResult.Success -> {
            clipboardManager.setText(AnnotatedString(result.value))
            showToast("Device code: ${result.value}")
        }
        is CaptureResult.Failure -> showToast("Could not generate code")
    }
}

// Or expose the session URL directly
val url = Logger.sessionUrl  // deep link to this session in the dashboard
```

Add a "Support Mode" toggle that attaches a `supportlog` field to every log, so support can filter the dashboard to a specific device:

```kotlin
// Toggle on/off from a settings or debug screen
Logger.addField("supportlog", "true")   // filter: supportlog = "true"
Logger.removeField("supportlog")         // back to normal
```

**Demo:** [Screens.kt](app/src/main/java/ai/bitdrift/shop/Screens.kt) (Welcome screen → device code + support log toggle)

**Docs:** [Device](https://docs.bitdrift.io/sdk/features/device)

**Unlocks:** Support teams can pull any user's session in real time without shipping debug builds or waiting for log uploads. Works in production.

> _POC criteria: helps evaluate the end-to-end debugging workflow — pull a reported session without a repro._

---

## 12. Upload symbol files for readable crash stacks

Crash stack traces are obfuscated by ProGuard/R8 in release builds. Upload the mapping file so the dashboard shows original class and method names.

The Gradle plugin (Step 1) does this for you: after a release build it exposes `bdUpload*` tasks. Run them after `assembleRelease`:

```bash
# Upload ProGuard mappings only (also: bdUploadSymbols, bdUploadSourceMap, or bdUpload for all)
API_KEY=<SDK_KEY> ./gradlew bdUploadMapping
```

If you need to upload manually with the `bd` CLI (`brew install bitdriftlabs/bd/bd`):

```bash
# Android — upload ProGuard mapping for a specific version
bd debug-files upload-proguard \
  --api-key <SDK_KEY> \
  --app-id <APP_ID> \
  --app-version "1.2.3" \
  --version-code 45 \
  mapping.txt
```

For native crashes (NDK), upload the Mach-O / ELF symbol files:

```bash
# Native symbols (iOS / Android)
bd debug-files upload \
  --api-key <SDK_KEY> \
  <FILE_OR_DIRECTORY>
```

> The `--api-key` value here is your **SDK key** (Admin → SDK Keys), not a separate API key. Also keep `-keepattributes SourceFile,LineNumberTable` in your ProGuard config on AGP versions earlier than 8.6.

**Demo:** [build.gradle.kts](build.gradle.kts) (plugin is already wired up)

**Docs:** [Issues & Crashes → Uploading Debug Information Files](https://docs.bitdrift.io/sdk/features/fatal-issues)

**Unlocks:** Human-readable stack traces in the Issues view. Without this, crash groups show obfuscated frames and cannot be matched to source locations.

> _POC criteria: helps evaluate crash detection — readable stacks with full session context._

---

## 13. New session on user logout or journey reset

Start a new session whenever the context changes enough that a new Timeline entry makes sense — typically on user logout, on a simulated journey restart, or when a distinct user flow begins.

```kotlin
// Create a clean session boundary
Logger.startNewSession()

// Then re-apply all global fields, since they are not
// persisted across session boundaries
Logger.addField("user_id", newUserId)
Logger.addField("app_variant", "sdk-demo")
```

> Global fields are session-scoped. Any field set before `startNewSession()` is NOT carried over. Re-declare everything you need on the new session.

**Demo:** [SimulationManager.kt](app/src/main/java/ai/bitdrift/shop/SimulationManager.kt) (`runSingleJourney()` — calls `startNewSession()` at the top of every simulated journey)

**Docs:** [Session Management](https://docs.bitdrift.io/sdk/features/session-management)

**Unlocks:** Clean per-user Timeline entries. Without explicit session boundaries, all journeys from the same process appear in a single session, making Timeline hard to read and Sankey analysis noisy.

> _POC criteria: helps evaluate session management — clean per-user session boundaries._

---

## 14. Forward your existing log framework

If the app already uses Timber, Log4j, or another logging framework, forward those logs to bitdrift so they appear in the session Timeline alongside your structured events. (If you already have rich app logging, bitdrift recommends doing this early — it lights up the Timeline with zero new instrumentation.)

```kotlin
// Timber tree that forwards to bitdrift
class BitdriftTree : Timber.Tree() {
    override fun log(priority: Int, tag: String?, message: String, t: Throwable?) {
        val level = when (priority) {
            Log.VERBOSE, Log.DEBUG -> LogLevel.DEBUG
            Log.INFO              -> LogLevel.INFO
            Log.WARN              -> LogLevel.WARNING
            Log.ERROR, Log.ASSERT -> LogLevel.ERROR
            else                  -> LogLevel.INFO
        }
        val fields = buildMap {
            if (tag != null) put("tag", tag)
        }
        if (t != null) {
            Logger.log(level, fields, t) { message }
        } else {
            Logger.log(level, fields) { message }
        }
    }
}

// Application.kt
Timber.plant(BitdriftTree())
```

**Docs:** [Integrations](https://docs.bitdrift.io/sdk/integrations)

**Unlocks:** All existing debug logs become searchable in Timeline and usable as Workflow match conditions — without changing any existing logging call sites.

> _POC criteria: covers the custom-logging pre-work, and helps evaluate log forwarding & integration with no new call sites._

---

## Feature coverage summary

| Step | SDK call | bitdrift feature | Docs |
|------|----------|-----------------|------|
| 1 | Gradle dependency | All features | [Quickstart](https://docs.bitdrift.io/sdk/quickstart) |
| 2 | `Logger.start()` | Instant Insights, Timeline, automatic events | [Configuration](https://docs.bitdrift.io/sdk/features/configuration) |
| 3 | `SessionStrategy` | Correct session grouping | [Session Management](https://docs.bitdrift.io/sdk/features/session-management) |
| 4 | `Logger.logScreenView()` | User Journey Sankey diagram | [Automatic Instrumentation](https://docs.bitdrift.io/sdk/features/automatic-instrumentation) |
| 5 | `Logger.setEntityId()` | Entities: per-user session history, Record Next Online | [Entity ID](https://docs.bitdrift.io/sdk/features/entity-id) |
| 6 | `CaptureOkHttpEventListenerFactory` | Network tab, request/response correlation | [HTTP Traffic Logs](https://docs.bitdrift.io/sdk/features/http-traffic-logs) |
| 7 | `Logger.logInfo/Warning/Error()` | Workflow matching, alerts, Timeline breadcrumbs | [Custom Logs](https://docs.bitdrift.io/sdk/features/custom-logs) |
| 8 | `Logger.addField()` / `FieldProvider` | Dashboard filtering, session header user_id | [Fields](https://docs.bitdrift.io/sdk/features/fields) |
| 9 | `Logger.logAppLaunchTTI()` | TTI histogram in Instant Insights → UX | [Automatic Instrumentation](https://docs.bitdrift.io/sdk/features/automatic-instrumentation) |
| 10 | `Logger.startSpan()` / `trackSpan()` | Spans waterfall, operation duration histograms | [Spans](https://docs.bitdrift.io/sdk/features/spans) |
| 11 | `Logger.createTemporaryDeviceCode()` | Support tooling, production device lookup | [Device](https://docs.bitdrift.io/sdk/features/device) |
| 12 | `bdUpload` / `bd debug-files upload-proguard` | Readable crash stacks in Issues | [Issues & Crashes](https://docs.bitdrift.io/sdk/features/fatal-issues) |
| 13 | `Logger.startNewSession()` | Clean per-user Timeline entries | [Session Management](https://docs.bitdrift.io/sdk/features/session-management) |
| 14 | Log framework forwarding | Existing logs visible in Timeline | [Integrations](https://docs.bitdrift.io/sdk/integrations) |

---

## Suggested Workflows for POC evaluation

Several features require **Workflows** — server-side rules configured in the bitdrift dashboard — to turn raw events into charts, alerts, and metrics. The SDK instrumentation is already complete; these are the matching dashboard configurations that make each step visible.

**What's automatic (no Workflow needed):**
- Instant Insights dashboards (crashes, network, memory, app launches) — light up from `Logger.start()`
- Session Timeline — all logged events appear automatically as breadcrumbs
- User Journey Sankey — built from `logScreenView()` events with no extra config
- TTI histogram in Instant Insights → UX — driven by `logAppLaunchTTI()`
- Spans waterfall in Timeline — rendered automatically from `startSpan()` / `trackSpan()`
- Entities view — populated from `setEntityId()`

**Workflows to build for custom metrics and alerts:**

| What to measure | Match condition | Action | Demonstrates |
|----------------|-----------------|--------|-------------|
| Payment failure rate | `message == "payment_failed"` | Custom metric: count, rate | Workflow matching on custom logs |
| Checkout conversion | `message == "payment_completed"` | Custom metric: count | Funnel analytics from structured events |
| Cart add rate | `message == "add_to_cart"` | Custom metric: count | User engagement tracking |
| Checkout error alert | `message == "checkout_failed"` AND rate > threshold | Alert → Slack / PagerDuty | Real-time alerting |
| Memory pressure alert | `message == "memory_pressure"` AND level high | Alert | Infrastructure health monitoring |
| Checkout span p95 | `name == "checkout"` AND `_span_type == "end"` | Custom metric: histogram of `_duration_ms` | Operation duration SLO tracking |
| Journey span p95 | `name == "journey"` AND `_span_type == "end"` | Custom metric: histogram of `_duration_ms` | End-to-end flow performance |
| Payment failure by variant | `message == "payment_failed"`, grouped by `ff_variant` | Custom metric: rate per variant | A/B cohort comparison |
| Checkout funnel by variant | `message IN ["checkout_started", "payment_completed"]`, grouped by `ff_checkout_flow` | Custom metric: count per step | Conversion rate by A/B variant |

**Log events emitted by this app** (match on `message ==`):
- `app_launched`, `app_open`, `app_close` — lifecycle
- `add_to_cart`, `add_to_wishlist` — product engagement
- `checkout_started`, `checkout_failed` — checkout funnel
- `payment_completed`, `payment_failed` — conversion and failure
- `simulation_start`, `simulation_end` — demo sim boundaries
- `memory_pressure`, `low_memory` — device health

**Span names** (match on `name ==` with `_span_type == "end"` for duration data):
- `journey` — full shopping journey root span
- `product_discovery` — Welcome → Browse/Search → ProductDetail
- `checkout` — CheckoutGuest/SignIn → Payment → Confirmation
- `score_products` — recommendation engine (slow-mode only)

**Field names for slicing and filtering:**
- `ff_variant` — active A/B variant (Control / Variant A / Variant B)
- `ff_checkout_flow` — guest / signin / random
- `ff_payment_ui` — digital / card / random
- `app_variant` — sdk-demo
- `user_id` — entity identifier (appears in Timeline session header)
- `supportlog` — true when support log mode is active

**Docs:** [Workflows](https://docs.bitdrift.io/product/workflows/overview), [Custom Metrics](https://docs.bitdrift.io/product/workflows/actions), [Alerts](https://docs.bitdrift.io/product/workflows/actions)

---

## Additional context for agents

This section is for an AI agent applying this guide to a real app (not the demo). The numbered steps above are written for a human reading the demo; the notes below cover what to discover, decide, and verify when instrumenting an arbitrary Android codebase. The `Demo:` links point at bitdrift-shop — in a target app, find the analogous file rather than editing the demo.

### Before you start — discover the target app

Search the codebase and record what you find; later decisions depend on it:

| Look for | Why it matters |
|----------|----------------|
| The `Application` subclass (`class … : Application()` + `android:name` in `AndroidManifest.xml`) | Where `Logger.start()`, global fields, and the TTI process-start timestamp go. If none exists, create one and register it in the manifest. |
| Every `OkHttpClient.Builder()` / Retrofit `client(...)` | Each client needs its own `CaptureOkHttpEventListenerFactory`. Miss one and that traffic is invisible. |
| Navigation style — Jetpack Compose (`@Composable`, `NavHost`) vs Activities/Fragments | Decides how screen views are emitted (see branches below). |
| Existing logging framework (`Timber`, `android.util.Log` wrappers, SLF4J) | If present, do Step 14 early — it lights up the Timeline with zero new call sites. |
| The SDK key (`BuildConfig.BITDRIFT_*`, `local.properties`, CI secrets) | Needed for `Logger.start()` and for symbol upload (`--api-key` / `API_KEY`). Never hardcode it. |
| Whether `io.bitdrift:capture` is already a dependency | If the SDK is already installed, skip Steps 1–2 and jump to whichever category the user asked for. |

### Decision branches

- **Screen views (Step 4):** Compose + NavController → prefer a centralized `NavController.addOnDestinationChangedListener` in the host composable (like the demo's `MainActivity`). It fires once per `navigate()` call for both user and programmatic navigation, independent of Compose composition timing. Map `destination.route` (the template, e.g. `"productDetail/{source}/{productId}"`) to a stable screen name string. Alternatively, per-screen `DisposableEffect(screenName) { Logger.logScreenView(name); onDispose {} }` works for simpler apps without programmatic navigation. Activities/Fragments → call it from `onResume()` or `ActivityLifecycleCallbacks`. Use stable snake_case names; they become Sankey node labels.
- **Entity ID (Step 5):** Set it at the real identity boundary (login / session establish), not at startup with a placeholder. Clearing supported soon.
- **Network (Step 6):** If the app uses a non-OkHttp stack (e.g. HttpURLConnection, Ktor with a non-OkHttp engine), the event-listener factory does not apply — fall back to manual `Logger.log(httpRequestInfo)` / `Logger.log(httpResponseInfo)` and consult $bd-docs (HTTP Traffic Logs) for the manual path.
- **High-cardinality paths (required, not optional):** every route with a dynamic segment (ID, slug, UUID) must get an `x-capture-path-template` header — unbounded paths blow past cardinality limits and are silently dropped (Step 6). Static paths need nothing.

### Stay on stable APIs

Use only stable SDK surface. Avoid `@ExperimentalBitdriftApi`-annotated methods (e.g. `setFeatureFlagExposure`, `getPreviousRunInfo`) — they require an explicit `@OptIn` and can change between releases. None of the steps above depend on an experimental API. If a feature the user wants is only available experimentally, confirm with the user before opting in, and check $bd-docs for the current status.

### Step dependencies (most steps are independent)

After Steps 1–2, the categories are standalone — apply only the ones the user needs, in any order. The real couplings:

- **2 requires 1.** **3 is a parameter of the `Logger.start()` call in 2** — set it there, don't add a second call.
- **13 (`startNewSession()`) invalidates 8.** Global fields are session-scoped and are NOT carried across a new session — re-apply them immediately after every `startNewSession()`.
- **12 (symbol upload) requires the Gradle plugin from 1** and a release build; it has no effect in debug.
- **9 (TTI):** only the first `logAppLaunchTTI()` per `Logger.start()` takes effect; call it once.

### Correctness rules (verified against the 0.23.x SDK)

- Call `Logger.start()` exactly once, as early as possible in `Application.onCreate()`, before any other SDK call.
- Structured logging: put the **stable event name in the message** (`{ "checkout_failed" }`) and **all variable data in `fields`**. Never interpolate variables into the message — it breaks field matching in Workflows.
- `Logger.log(level, fields, throwable) { message }` — the throwable is the **third** positional arg, after fields.
- Spans: `startSpan(...)` returns `Span?`; `parentSpanId` is a `UUID?` — pass the parent's `.id`. `span.end(...)` is idempotent (safe at multiple exit points). `trackSpan(name, level, fields) { … }` returns the block's value directly and ends SUCCESS/FAILURE automatically.
- `user_id` is a special field — when set, it surfaces in the Timeline session header.
- Symbol upload: the `--api-key` / `API_KEY` value is your **SDK key**, not a separate API key. Keep `-keepattributes SourceFile,LineNumberTable` in ProGuard config on AGP < 8.6.
- Android min API level is 23.

### Verify your work

1. **Compile** after each category — e.g. `./gradlew :app:compileDebugKotlin`. The SDK calls are non-throwing no-ops if `Logger.start()` hasn't run, so a clean compile + app launch is the first gate.
2. **Confirm data flow** in the dashboard for what you instrumented: sessions appear in Timeline (Step 2), screen views form a Sankey (Step 4), network events show on the Timeline (Step 6), TTI populates Instant Insights → UX (Step 9), spans render in the waterfall (Step 10).
3. **Run the validation checklist:** SDK dependency present & current · logger initialized early · session strategy set · network monitoring on every client · screen tracking on every screen · TTI tracked once · identity fields set after login · global fields re-applied after `startNewSession()` · ProGuard mapping upload wired for release builds.

### Adapting this guide for iOS

This guide is Android-only by design. The **concepts, ordering, and product features are identical on iOS** — only the call sites and a few API shapes differ. Don't rewrite the guide for iOS; instead read `references/ios.md` in the **bd-instrumentation** skill (authoritative, per-step) and confirm signatures via **$bd-docs**. The Android → iOS (Swift) map:

| Concept (step) | Android | iOS (Swift) |
|----------------|---------|-------------|
| Install (1) | `io.bitdrift:capture` + Gradle plugin | SPM `bitdriftlabs/capture-ios` or CocoaPods `pod 'BitdriftCapture'`; `import Capture` (module is `Capture`, not `BitdriftCapture`) |
| Start (2) | `Logger.start(...)` in `Application.onCreate()` | `Logger.start(withAPIKey:sessionStrategy:)` — SwiftUI: `@main App` `init()`; UIKit: `application(_:didFinishLaunchingWithOptions:)` |
| Session strategy (3) | `SessionStrategy.Fixed()` / `.ActivityBased(...)` | `.fixed()` / `.activityBased(...)` |
| Screen views (4) | `Logger.logScreenView(name)` in Compose `DisposableEffect` | SwiftUI: `.onAppear { Logger.logScreenView(screenName: "...") }`; UIKit: call in `viewDidAppear(_:)` |
| Entity ID (5) | `Logger.setEntityId(id)` | `Logger.setEntityID(id)` — note capital **ID** |
| Network (6) | `CaptureOkHttpEventListenerFactory` on each `OkHttpClient` | `Logger.start(...).enableIntegrations([.urlSession()])` — swizzles all `URLSession` (covers Alamofire) |
| Custom logs (7) | `Logger.logInfo(fields) { "event" }` | `Logger.logInfo("event", fields: ["k": "v"])` — message positional, `fields:` labeled |
| Global fields (8) | `Logger.addField(...)` | same |
| TTI (9) | `Logger.logAppLaunchTTI(...)` | same |
| Spans (10) | `Logger.startSpan(name, level, fields)` | `Logger.startSpan(name:level:fields:)` / `span?.end(.success)` |
| Device code (11) | `Logger.createTemporaryDeviceCode { }` | same (Swift closure) |
| Symbols (12) | ProGuard via `bdUpload*` / `bd debug-files upload-proguard` | **dSYMs** via `bd debug-files upload` or an Xcode build-phase script — not ProGuard |
| New session (13) | `Logger.startNewSession()` | same |
| Log forwarding (14) | Timber tree | `.enableIntegrations([.cocoaLumberjack()])` / `.swiftyBeaver()` on `Logger.start()` |

iOS-only gotchas:

- **Integrations are chained on `start()`** — network and log forwarding are enabled via `.enableIntegrations([...])` on the `Logger.start()` return value, not wired per-client like Android's OkHttp factory.
- **Initialize at launch** (SwiftUI `@main` `init()`, UIKit `didFinishLaunchingWithOptions`) so the SDK can observe launch system events that power OOTB signals.
- **Don't embed the SDK twice:** add `BitdriftCapture` only to targets that call `Logger.start()`. Adding it to a shared framework target the app also imports causes duplicate ObjC class symbol warnings.
- API casing/shape differs in a few spots (`setEntityID`, `logInfo` message-first) — when porting a snippet, confirm the exact signature in $bd-docs rather than transliterating the Kotlin.
- **High-cardinality paths matter on iOS too** (Step 6) — set the `x-capture-path-template` request header, or pass a template via `HTTPURLPath(value:template:)`. Same cardinality limits, same silent metric drops.
- React Native is covered in the next subsection.

### Adapting this guide for React Native

The same concepts and ordering apply. The SDK is the `@bitdrift/react-native` package wrapping the native SDKs, so you also complete the native install (`pod install` for iOS, autolinking for Android). For per-step depth read `references/react-native.md` in the **bd-instrumentation** skill and confirm signatures via **$bd-docs**. The Android → React Native (TypeScript) map:

| Concept (step) | Android | React Native (TypeScript) |
|----------------|---------|---------------------------|
| Install (1) | `io.bitdrift:capture` + Gradle plugin | `npm install @bitdrift/react-native`, then `pod install` (iOS); Android autolinks |
| Start (2) | `Logger.start(...)` in `Application.onCreate()` | `init(apiKey, SessionStrategy.Fixed)` in `App.tsx`/`index.js`, before the app renders |
| Session strategy (3) | `SessionStrategy.Fixed()` | `SessionStrategy.Fixed` (a value, not a call) / `.ActivityBased` |
| Screen views (4) | `Logger.logScreenView(name)` in Compose `DisposableEffect` | `logScreenView(routeName)` — React Navigation `onStateChange`, or Expo Router `usePathname()` |
| Entity ID (5) | `Logger.setEntityId(id)` | `setEntityId(id)` |
| Network (6) | `CaptureOkHttpEventListenerFactory` on each `OkHttpClient` | No guaranteed auto-capture — wrap `fetch` / add an interceptor using the manual HTTP logging API (check $bd-docs) |
| Custom logs (7) | `Logger.logInfo(fields) { "event" }` | `info("event", { k: "v" })` / `warning(...)` / `error(...)` |
| Global fields (8) | `Logger.addField(...)` / `FieldProvider` | `addField("user_id", id)` / `removeField(...)` |
| TTI (9) | `Logger.logAppLaunchTTI(...)` | `logAppLaunchTTI(durationMs)` — for React Navigation, in the `onReady` callback |
| Spans (10) | `Logger.startSpan(name, level, fields)` | span API — confirm name/signature in $bd-docs |
| Device code (11) | `Logger.createTemporaryDeviceCode { }` | `generateDeviceCode()`; also `getSessionURL()`, `getDeviceId()` |
| Symbols (12) | ProGuard via `bdUpload*` | **Hermes source maps** via `bd debug-files upload-source-map --source-map … --bundle …` (or `bdUploadSourceMap`); native crashes still need dSYM (iOS) / ProGuard (Android) |
| New session (13) | `Logger.startNewSession()` | confirm the JS export in $bd-docs |
| Log forwarding (14) | Timber tree | No built-in transport — wrap `console.log/warn/error` → `info()/warning()/error()`, or add a `react-native-logs` transport |

React-Native-only gotchas:

- **Two install layers:** the JS package plus the native pods/Gradle. After `npm install`, run `pod install` in `ios/`; Android autolinks. Crash symbolication needs **both** JS source maps and native symbols.
- **JS error reporting** is currently limited to Expo builds on the **New Architecture + Hermes** engine — verify the app's setup before relying on JS crash capture.
- **Network capture isn't guaranteed automatic** — unlike OkHttp/URLSession, confirm in $bd-docs whether RN auto-instruments `fetch`/XHR; otherwise wrap `fetch` or use an interceptor with the manual HTTP logging API. The Step 6 cardinality rules still apply — template dynamic path segments.
- **Session URL for support** is `getSessionURL()` (capital URL); pass it to your JS crash reporter as a custom key to link sessions.
- Functions are **top-level named exports** (`init`, `info`, `addField`, …), not methods on a `Logger` object — `import { … } from '@bitdrift/react-native'`.

### Looking things up

For live API signatures, field names, and enum values, use the **$bd-docs** skill (fetches from `docs.bitdrift.io`) rather than guessing — the per-step **Docs:** links above are the relevant pages. The SDK evolves; if a symbol named here is missing in the project's SDK version, confirm against the docs for that version before changing call sites.
