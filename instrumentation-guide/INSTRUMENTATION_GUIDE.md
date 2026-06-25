# bitdrift Instrumentation Guide

A platform-neutral, step-by-step checklist for wiring up the bitdrift Capture SDK in **any** mobile app. Each step lights up a specific product feature. Follow them in order — later steps build on earlier ones.

The order is tuned for a proof-of-concept: stand up the SDK (1–3), then light up the timeline with the highest-value signals first — screen views, user identity, and network (4–6) — before layering on logs, performance, and operational features. This follows bitdrift's [Integration first steps](https://docs.bitdrift.io/product/first-steps). The categories are independent, so reorder them to fit your app.

Code examples are shown in **Kotlin (Android)**. The same concepts, ordering, and product features apply to **iOS** and **React Native** — the call sites and a few API shapes differ. See [Adapting this guide for iOS](#adapting-this-guide-for-ios) and [Adapting this guide for React Native](#adapting-this-guide-for-react-native) at the bottom for the per-platform API maps.

---

## Using this guide with bd skills

This guide is designed to be used alongside **bitdrift's agent skills**, which give an AI coding agent the operational logic to carry out — and verify — the steps below:

- **bd-instrumentation** — installs and instruments the Capture SDK on Android, iOS, and React Native. It detects the platform and whether the SDK is already present, then performs a fresh install or extends an existing integration. This document is the human-readable companion to that skill.
- **bd-docs** — fetches live bitdrift documentation at query time (the `$bd-docs` references throughout this guide point to it).
- **bd-cli** — drives the `bd` CLI for symbol/source-map uploads, workflows, session/issue queries, and key management.

The skills drive the **`bd` CLI** (also used directly for the symbol/source-map uploads in Step 12). Install and authenticate it first (macOS, Homebrew):

```bash
brew tap bitdriftlabs/bd
brew install bd
bd auth   # browser login; for CI/automation use --api-key <key> or the BD_API_KEY env var
```

See the [CLI Quickstart](https://docs.bitdrift.io/cli/quickstart).

Then install the skills with [skills.sh](https://skills.sh/) (requires `node`/`npm`):

```bash
npx skills add bitdriftlabs/bd-skills
# update later with: npx skills update --all
```

The skills follow the [agentskills.io](https://agentskills.io/) open standard and work with Claude Code, Cursor, Codex, Copilot, and any skills-compatible agent. See the [Agent Skills docs](https://docs.bitdrift.io/product/skills/overview).

> **Already have the skills?** Just ask your agent to do the work — e.g. *"install the bitdrift Capture SDK in this app and add screen tracking and network monitoring"* — and it will follow `bd-instrumentation`. Use this guide as the reference for what each step unlocks.

---

## 1. Add the dependency

Add the Capture SDK and Gradle plugin to your project. The plugin handles automatic OkHttp instrumentation and ProGuard mapping uploads.

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

**Docs:** [SDK Quickstart](https://docs.bitdrift.io/sdk/quickstart)

**Unlocks:** Everything. No other step works without this.

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

**Docs:** [Configuration](https://docs.bitdrift.io/sdk/features/configuration), [Automatic Instrumentation](https://docs.bitdrift.io/sdk/features/automatic-instrumentation)

**Unlocks:** Instant Insights dashboards (app launches, crashes, network, resources), session timeline, all automatic instrumentation (memory pressure, battery, orientation changes, slow frames, thermal state). The SDK begins collecting device telemetry immediately after `start()`.

---

## 3. Confirm session strategy

`sessionStrategy` is a required parameter of the `Logger.start()` call above. Default to `SessionStrategy.Fixed()` — it starts a fresh session on every process launch, which is the simplest to reason about and ideal for demos and verification.

```kotlin
sessionStrategy = SessionStrategy.Fixed()  // the default choice
```

Optionally switch to `SessionStrategy.ActivityBased()` if you need sessions to persist across process restarts and rotate only after a period of inactivity (default 30 minutes, configurable) — useful for user-facing flows where one journey may span a backgrounded app.

**Docs:** [Session Management](https://docs.bitdrift.io/sdk/features/session-management)

**Unlocks:** Correct session grouping in Timeline.

---

## 4. Instrument screen views

Call `Logger.logScreenView(name)` every time the user navigates to a new screen. Use a stable, snake_case name — it becomes the node label in the Sankey diagram.

**Option A — per-screen DisposableEffect** (simple, works for manual navigation):

```kotlin
@Composable
fun MyScreen() {
    DisposableEffect(Unit) {
        Logger.logScreenView("my_screen")
        onDispose { }
    }
    // screen content
}
```

**Option B — centralized NavController listener** (preferred with Compose Navigation; works for both user and programmatic navigation):

```kotlin
DisposableEffect(navController) {
    val listener = NavController.OnDestinationChangedListener { _, destination, _ ->
        val screenName = destinationToScreenName(destination.route ?: return@OnDestinationChangedListener)
        Logger.logScreenView(screenName)
    }
    navController.addOnDestinationChangedListener(listener)
    onDispose { navController.removeOnDestinationChangedListener(listener) }
}
```

A centralized listener fires once per `navigate()` call, independent of Compose composition timing, so it captures both user and programmatic navigation. For Activities/Fragments, call `logScreenView()` from `onResume()` or `ActivityLifecycleCallbacks`.

**Docs:** [Automatic Instrumentation → Screen Views](https://docs.bitdrift.io/sdk/features/automatic-instrumentation)

**Unlocks:** User Journey (Sankey) diagram in Instant Insights. This is the foundation for funnel analysis.

---

## 5. Identify users with Entity ID

Call `Logger.setEntityId()` whenever you know who the user is — on login, at the start of a session, or when an anonymous ID is established. The value is hashed; the plaintext is never stored.

```kotlin
// After sign-in
Logger.setEntityId(userId)
```

**Docs:** [Entity ID (SDK)](https://docs.bitdrift.io/sdk/features/entity-id), [Entities (product)](https://docs.bitdrift.io/product/entities)

**Unlocks:** The Entities feature — search any entity by name to see all their sessions, crashes, devices, and last location; queue a session recording with **Record Next Online**; bookmark entities to share with your team.

---

## 6. Capture network traffic

The single highest-value instrumentation after starting the logger, and near-automatic. Add `CaptureOkHttpEventListenerFactory` to your `OkHttpClient` and every request/response is logged with timing breakdowns (DNS, TLS, TTFB, total), status codes, and sizes.

```kotlin
import io.bitdrift.capture.network.okhttp.CaptureOkHttpEventListenerFactory
import okhttp3.OkHttpClient

private val client = OkHttpClient.Builder()
    .eventListenerFactory(CaptureOkHttpEventListenerFactory())
    .build()
```

If you have multiple OkHttp clients (e.g. one per API host), add the factory to each one. If the app uses a non-OkHttp stack (HttpURLConnection, Ktor with a non-OkHttp engine), fall back to manual `Logger.log(httpRequestInfo)` / `Logger.log(httpResponseInfo)` — see $bd-docs.

**Docs:** [HTTP Traffic Logs](https://docs.bitdrift.io/sdk/features/http-traffic-logs)

**Unlocks:** Network tab in Instant Insights (p50/p95 latency, error rate, throughput by endpoint), and network events on the session Timeline alongside custom logs and screen views.

### ⚠️ Collapse high-cardinality paths — do not skip this

When a URL path embeds a dynamic segment — user ID, product ID, session token, UUID — every request becomes a *distinct* path value. The dashboard groups network metrics by path, and bitdrift enforces **cardinality limits**: once a metric exceeds ~1,000 group-by dimensions per ~30 minutes (or 20,000 total across platform/app/version), metrics are **silently dropped** and the chart breaks. Unbounded paths are the most common way to hit this, so this step is required, not optional.

Collapse dynamic segments into a stable template with the `x-capture-path-template` request header, so `/api/products/abc123` and `/api/products/xyz789` both report as one endpoint:

```kotlin
.addHeader("x-capture-path-template", "/api/products/<id>")
```

The SDK records this as `_path_template`. If the header is absent the SDK attempts auto-detection, but explicit templates are far more reliable — **set one on every route that contains a dynamic segment.**

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
| `logWarning` | Degraded state: retry, memory pressure, slow response |
| `logError` | Failures: payment failed, API error, flow abandoned |

**Pass a Throwable to capture stack traces** (the throwable is the **third** positional arg, after fields):

```kotlin
try {
    api.checkout()
} catch (e: Exception) {
    Logger.logError(e, mapOf("checkout_type" to "guest")) { "checkout_failed" }
    // Adds _error and _error_details fields automatically
}
```

**Docs:** [Custom Logs](https://docs.bitdrift.io/sdk/features/custom-logs)

**Unlocks:** Workflow matching, custom metrics (count, rate, histogram of any field value), Timeline breadcrumbs, alert triggers.

---

## 8. Attach global fields

Global fields attach to every log emitted after the call. Use them for context true for the duration of a session or lifecycle state — app variant, user tier, build channel.

```kotlin
Logger.addField("app_variant", "production")  // attached to every subsequent log
Logger.addField("user_id", userId)            // set on sign-in
Logger.removeField("user_id")                  // remove on sign-out
```

For fields that must survive process restart or come from outside the SDK, implement `FieldProvider`:

```kotlin
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

> `user_id` is a special field name: when present, it appears in the Timeline session header.

**Docs:** [Fields](https://docs.bitdrift.io/sdk/features/fields)

**Unlocks:** Dashboard filtering and slicing by any global field (e.g. isolate a release cohort by `app_variant`).

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

**Docs:** [Automatic Instrumentation → TTI](https://docs.bitdrift.io/sdk/features/automatic-instrumentation)

**Unlocks:** App Launch TTI chart in Instant Insights → UX (p50/p95/p99 across your population).

---

## 10. Measure operations with custom spans

Spans measure the duration of any multi-step operation. A span emits two logs — `span_type=start` and `span_type=end` — with a `_duration_ms` field on the end log.

```kotlin
import io.bitdrift.capture.LogLevel
import io.bitdrift.capture.events.span.SpanResult

val span = Logger.startSpan(name = "checkout", level = LogLevel.INFO, fields = mapOf("checkout_type" to "guest"))
// ... do work ...
span?.end(SpanResult.SUCCESS, mapOf("payment_method" to "card"))
// or: span?.end(SpanResult.FAILURE) / SpanResult.CANCELED
```

**Nested spans** link parent and child via `parentSpanId` (a `UUID?` — pass the parent's `.id`), creating a waterfall hierarchy in the Timeline. `Span.end()` is idempotent — safe to call at multiple exit points.

For synchronous operations, use the `trackSpan` wrapper — it ends `SUCCESS` if the block returns and `FAILURE` if it throws, and returns the block's value:

```kotlin
val result = Logger.trackSpan("score_products", LogLevel.INFO, mapOf("id" to id)) {
    engine.score(input)
}
```

**Docs:** [Spans (SDK)](https://docs.bitdrift.io/sdk/features/spans), [Spans Visualization](https://docs.bitdrift.io/product/timeline/spans-visualization)

**Unlocks:** Spans waterfall in the Timeline; query `_duration_ms` in Workflows to plot p50/p95 of any operation across your user base.

---

## 11. Implement device identification for support

Surface a device code or session URL inside your app so support agents can pull the exact session from the dashboard without device logs or a repro.

```kotlin
Logger.createTemporaryDeviceCode { result ->
    when (result) {
        is CaptureResult.Success -> { /* copy result.value to clipboard, show it */ }
        is CaptureResult.Failure -> { /* show error */ }
    }
}

val url = Logger.sessionUrl  // deep link to this session in the dashboard
```

Add a "Support Mode" toggle that attaches a `supportlog` field to every log so support can filter the dashboard to a specific device:

```kotlin
Logger.addField("supportlog", "true")   // filter: supportlog = "true"
Logger.removeField("supportlog")
```

**Docs:** [Device](https://docs.bitdrift.io/sdk/features/device)

**Unlocks:** Support teams pull any user's session in real time without shipping debug builds. Works in production.

---

## 12. Upload symbol files for readable crash stacks

Crash stack traces are obfuscated by ProGuard/R8 in release builds. Upload the mapping file so the dashboard shows original names.

The Gradle plugin (Step 1) does this for you: after a release build it exposes `bdUpload*` tasks:

```bash
# Upload ProGuard mappings (also: bdUploadSymbols, bdUploadSourceMap, or bdUpload for all)
API_KEY=<SDK_KEY> ./gradlew bdUploadMapping
```

To upload manually with the `bd` CLI:

```bash
bd debug-files upload-proguard \
  --api-key <SDK_KEY> --app-id <APP_ID> \
  --app-version "1.2.3" --version-code 45 \
  mapping.txt
```

For native crashes (NDK), upload the ELF symbol files with `bd debug-files upload <FILE_OR_DIR>`.

> The `--api-key` value here is your **SDK key** (Admin → SDK Keys), not a separate API key. Keep `-keepattributes SourceFile,LineNumberTable` in ProGuard config on AGP versions earlier than 8.6.

**Docs:** [Issues & Crashes → Uploading Debug Information Files](https://docs.bitdrift.io/sdk/features/fatal-issues)

**Unlocks:** Human-readable stack traces in the Issues view.

---

## 13. New session on user logout or journey reset

Start a new session whenever context changes enough that a new Timeline entry makes sense — user logout, journey restart, or a distinct flow boundary.

```kotlin
Logger.startNewSession()

// Re-apply all global fields — they are session-scoped and NOT carried over
Logger.addField("user_id", newUserId)
Logger.addField("app_variant", "production")
```

> Global fields are session-scoped. Any field set before `startNewSession()` is NOT carried over — re-declare everything you need.

**Docs:** [Session Management](https://docs.bitdrift.io/sdk/features/session-management)

**Unlocks:** Clean per-user Timeline entries.

---

## 14. Forward your existing log framework

If the app already uses Timber, Log4j, or another framework, forward those logs to bitdrift so they appear in the Timeline alongside your structured events. If you already have rich logging, do this early — it lights up the Timeline with zero new instrumentation.

```kotlin
class BitdriftTree : Timber.Tree() {
    override fun log(priority: Int, tag: String?, message: String, t: Throwable?) {
        val level = when (priority) {
            Log.VERBOSE, Log.DEBUG -> LogLevel.DEBUG
            Log.INFO              -> LogLevel.INFO
            Log.WARN              -> LogLevel.WARNING
            Log.ERROR, Log.ASSERT -> LogLevel.ERROR
            else                  -> LogLevel.INFO
        }
        val fields = buildMap { if (tag != null) put("tag", tag) }
        if (t != null) Logger.log(level, fields, t) { message }
        else Logger.log(level, fields) { message }
    }
}

// Application.kt
Timber.plant(BitdriftTree())
```

**Docs:** [Integrations](https://docs.bitdrift.io/sdk/integrations)

**Unlocks:** All existing debug logs become searchable in Timeline and usable as Workflow match conditions — without changing any existing call sites.

---

## Feature coverage summary

| Step | SDK call | bitdrift feature | Docs |
|------|----------|-----------------|------|
| 1 | Gradle dependency | All features | [Quickstart](https://docs.bitdrift.io/sdk/quickstart) |
| 2 | `Logger.start()` | Instant Insights, Timeline, automatic events | [Configuration](https://docs.bitdrift.io/sdk/features/configuration) |
| 3 | `SessionStrategy` | Correct session grouping | [Session Management](https://docs.bitdrift.io/sdk/features/session-management) |
| 4 | `Logger.logScreenView()` | User Journey Sankey diagram | [Automatic Instrumentation](https://docs.bitdrift.io/sdk/features/automatic-instrumentation) |
| 5 | `Logger.setEntityId()` | Entities: per-user history, Record Next Online | [Entity ID](https://docs.bitdrift.io/sdk/features/entity-id) |
| 6 | `CaptureOkHttpEventListenerFactory` | Network tab, request/response correlation | [HTTP Traffic Logs](https://docs.bitdrift.io/sdk/features/http-traffic-logs) |
| 7 | `Logger.logInfo/Warning/Error()` | Workflow matching, alerts, breadcrumbs | [Custom Logs](https://docs.bitdrift.io/sdk/features/custom-logs) |
| 8 | `Logger.addField()` / `FieldProvider` | Dashboard filtering, session header user_id | [Fields](https://docs.bitdrift.io/sdk/features/fields) |
| 9 | `Logger.logAppLaunchTTI()` | TTI histogram in Instant Insights → UX | [Automatic Instrumentation](https://docs.bitdrift.io/sdk/features/automatic-instrumentation) |
| 10 | `Logger.startSpan()` / `trackSpan()` | Spans waterfall, duration histograms | [Spans](https://docs.bitdrift.io/sdk/features/spans) |
| 11 | `Logger.createTemporaryDeviceCode()` | Support tooling, production device lookup | [Device](https://docs.bitdrift.io/sdk/features/device) |
| 12 | `bdUpload` / `bd debug-files upload-proguard` | Readable crash stacks in Issues | [Issues & Crashes](https://docs.bitdrift.io/sdk/features/fatal-issues) |
| 13 | `Logger.startNewSession()` | Clean per-user Timeline entries | [Session Management](https://docs.bitdrift.io/sdk/features/session-management) |
| 14 | Log framework forwarding | Existing logs visible in Timeline | [Integrations](https://docs.bitdrift.io/sdk/integrations) |

---

## Turning signals into metrics and alerts (Workflows)

Some features require **Workflows** — server-side rules configured in the dashboard — to turn raw events into charts, alerts, and metrics. The SDK instrumentation is the input; Workflows are the dashboard configuration.

**Automatic, no Workflow needed:** Instant Insights dashboards (crashes, network, memory, app launches) from `Logger.start()`; Session Timeline breadcrumbs; User Journey Sankey from `logScreenView()`; TTI histogram from `logAppLaunchTTI()`; Spans waterfall from `startSpan()`; Entities view from `setEntityId()`.

**Build Workflows for custom metrics and alerts** — match on your stable event names (Step 7) and span names (Step 10):

| What to measure | Match condition | Action |
|----------------|-----------------|--------|
| Event rate | `message == "<your_event>"` | Custom metric: count, rate |
| Error alerting | `message == "<error_event>"` AND rate > threshold | Alert → Slack / PagerDuty |
| Operation p95 | `name == "<span>"` AND `_span_type == "end"` | Custom metric: histogram of `_duration_ms` |
| Cohort comparison | `message == "<event>"`, grouped by a global field | Custom metric: rate per cohort |

**Docs:** [Workflows](https://docs.bitdrift.io/product/workflows/overview), [Custom Metrics & Alerts](https://docs.bitdrift.io/product/workflows/actions)

---

## Additional context for agents

This section is for an AI agent applying this guide to a real app. The numbered steps above are written for a human; the notes below cover what to discover, decide, and verify when instrumenting an arbitrary codebase.

### Before you start — discover the target app

| Look for | Why it matters |
|----------|----------------|
| The `Application` subclass (`class … : Application()` + `android:name` in `AndroidManifest.xml`) | Where `Logger.start()`, global fields, and the TTI process-start timestamp go. If none exists, create one and register it. |
| Every `OkHttpClient.Builder()` / Retrofit `client(...)` | Each client needs its own `CaptureOkHttpEventListenerFactory`. Miss one and that traffic is invisible. |
| Navigation style — Jetpack Compose (`NavHost`) vs Activities/Fragments | Decides how screen views are emitted. |
| Existing logging framework (`Timber`, `android.util.Log` wrappers, SLF4J) | If present, do Step 14 early. |
| The SDK key (`BuildConfig.BITDRIFT_*`, `local.properties`, CI secrets) | Needed for `Logger.start()` and symbol upload. Never hardcode it. |
| Whether `io.bitdrift:capture` is already a dependency | If installed, skip Steps 1–2 and jump to the category requested. |

### Decision branches

- **Screen views (Step 4):** Compose + NavController → centralized `addOnDestinationChangedListener` in the host composable. Map `destination.route` to a stable snake_case name. Simpler apps → per-screen `DisposableEffect`. Activities/Fragments → `onResume()` or `ActivityLifecycleCallbacks`.
- **Entity ID (Step 5):** set at the real identity boundary (login), not at startup with a placeholder.
- **Network (Step 6):** non-OkHttp stack → fall back to the manual HTTP logging API ($bd-docs).
- **High-cardinality paths (required):** every route with a dynamic segment needs an `x-capture-path-template` header — unbounded paths are silently dropped.

### Stay on stable APIs

Use only stable SDK surface. Avoid `@ExperimentalBitdriftApi`-annotated methods — they require explicit `@OptIn` and can change between releases. None of the steps above depend on an experimental API; if a feature is only available experimentally, confirm with the user before opting in.

### Step dependencies (most steps are independent)

After Steps 1–2 the categories are standalone — apply only the ones needed, in any order. The real couplings:

- **2 requires 1.** **3 is a parameter of the `start()` call in 2** — don't add a second call.
- **13 (`startNewSession()`) invalidates 8.** Re-apply global fields immediately after every new session.
- **12 (symbol upload) requires the Gradle plugin from 1** and a release build; no effect in debug.
- **9 (TTI):** only the first `logAppLaunchTTI()` per `Logger.start()` takes effect; call it once.

### Correctness rules

- Call `Logger.start()` exactly once, as early as possible in `Application.onCreate()`, before any other SDK call.
- Structured logging: stable event name in the **message**, all variable data in **fields**. Never interpolate variables into the message.
- `Logger.log(level, fields, throwable) { message }` — the throwable is the **third** positional arg, after fields.
- Spans: `startSpan(...)` returns `Span?`; `parentSpanId` is a `UUID?`. `span.end(...)` is idempotent. `trackSpan(...) { … }` returns the block's value.
- `user_id` is a special field — surfaces in the Timeline session header when set.
- Symbol upload: `--api-key` / `API_KEY` is your **SDK key**, not a separate API key.

### Verify your work

1. **Compile** after each category — e.g. `./gradlew :app:compileDebugKotlin`. SDK calls are non-throwing no-ops if `Logger.start()` hasn't run, so a clean compile + app launch is the first gate.
2. **Confirm data flow** in the dashboard: sessions in Timeline (Step 2), Sankey from screen views (Step 4), network events on Timeline (Step 6), TTI in Instant Insights → UX (Step 9), spans in the waterfall (Step 10).
3. **Validation checklist:** SDK dependency present & current · logger initialized early · session strategy set · network monitoring on every client · screen tracking on every screen · TTI tracked once · identity fields set after login · global fields re-applied after `startNewSession()` · ProGuard mapping upload wired for release.

### Looking things up

For live API signatures, field names, and enum values, use the **$bd-docs** skill rather than guessing. The SDK evolves; if a symbol named here is missing in the project's SDK version, confirm against the docs for that version before changing call sites.

---

## Adapting this guide for iOS

The **concepts, ordering, and product features are identical on iOS** — only the call sites and a few API shapes differ. Read `references/ios.md` in the **bd-instrumentation** skill (authoritative, per-step) and confirm signatures via **$bd-docs**. The Android → iOS (Swift) map:

| Concept (step) | Android | iOS (Swift) |
|----------------|---------|-------------|
| Install (1) | `io.bitdrift:capture` + Gradle plugin | SPM `bitdriftlabs/capture-ios` or CocoaPods `pod 'BitdriftCapture'`; `import Capture` (module is `Capture`) |
| Start (2) | `Logger.start(...)` in `Application.onCreate()` | `Logger.start(withAPIKey:sessionStrategy:)` — SwiftUI: `@main App` `init()`; UIKit: `application(_:didFinishLaunchingWithOptions:)` |
| Session strategy (3) | `SessionStrategy.Fixed()` / `.ActivityBased(...)` | `.fixed()` / `.activityBased(...)` |
| Screen views (4) | `Logger.logScreenView(name)` | SwiftUI: `.onAppear { Logger.logScreenView(screenName: "...") }`; UIKit: `viewDidAppear(_:)` |
| Entity ID (5) | `Logger.setEntityId(id)` | `Logger.setEntityID(id)` — capital **ID** |
| Network (6) | `CaptureOkHttpEventListenerFactory` per client | `Logger.start(...).enableIntegrations([.urlSession()])` — swizzles all `URLSession` (covers Alamofire) |
| Custom logs (7) | `Logger.logInfo(fields) { "event" }` | `Logger.logInfo("event", fields: ["k": "v"])` — message positional, `fields:` labeled |
| Global fields (8) | `Logger.addField(...)` | same |
| TTI (9) | `Logger.logAppLaunchTTI(...)` | same |
| Spans (10) | `Logger.startSpan(name, level, fields)` | `Logger.startSpan(name:level:fields:)` / `span?.end(.success)` |
| Device code (11) | `Logger.createTemporaryDeviceCode { }` | same (Swift closure) |
| Symbols (12) | ProGuard via `bdUpload*` | **dSYMs** via `bd debug-files upload` or an Xcode build-phase script — not ProGuard |
| New session (13) | `Logger.startNewSession()` | same |
| Log forwarding (14) | Timber tree | `.enableIntegrations([.cocoaLumberjack()])` / `.swiftyBeaver()` on `start()` |

iOS-only gotchas:

- **Integrations are chained on `start()`** — network and log forwarding via `.enableIntegrations([...])` on the `Logger.start()` return value, not per-client.
- **Initialize at launch** (SwiftUI `@main` `init()`, UIKit `didFinishLaunchingWithOptions`) so the SDK observes launch system events.
- **Don't embed the SDK twice:** add `BitdriftCapture` only to targets that call `Logger.start()`. Adding it to a shared framework the app also imports causes duplicate ObjC class symbol warnings.
- API casing/shape differs in a few spots (`setEntityID`, `logInfo` message-first) — confirm exact signatures in $bd-docs rather than transliterating Kotlin.
- **High-cardinality paths matter on iOS too** — set `x-capture-path-template` or pass a template via `HTTPURLPath(value:template:)`.

---

## Adapting this guide for React Native

The same concepts and ordering apply. The SDK is the `@bitdrift/react-native` package wrapping the native SDKs, so you also complete the native install (`pod install` for iOS, autolinking for Android). Read `references/react-native.md` in the **bd-instrumentation** skill and confirm signatures via **$bd-docs**. The Android → React Native (TypeScript) map:

| Concept (step) | Android | React Native (TypeScript) |
|----------------|---------|---------------------------|
| Install (1) | `io.bitdrift:capture` + Gradle plugin | `npm install @bitdrift/react-native`, then `pod install` (iOS); Android autolinks |
| Start (2) | `Logger.start(...)` in `Application.onCreate()` | `init(apiKey, SessionStrategy.Fixed)` in `App.tsx`/`index.js`, before the app renders |
| Session strategy (3) | `SessionStrategy.Fixed()` | `SessionStrategy.Fixed` (a value, not a call) / `.ActivityBased` |
| Screen views (4) | `Logger.logScreenView(name)` | `logScreenView(routeName)` — React Navigation `onStateChange`, or Expo Router `usePathname()` |
| Entity ID (5) | `Logger.setEntityId(id)` | `setEntityId(id)` |
| Network (6) | `CaptureOkHttpEventListenerFactory` per client | No guaranteed auto-capture — wrap `fetch` / add an interceptor using the manual HTTP logging API (check $bd-docs) |
| Custom logs (7) | `Logger.logInfo(fields) { "event" }` | `info("event", { k: "v" })` / `warning(...)` / `error(...)` |
| Global fields (8) | `Logger.addField(...)` | `addField("user_id", id)` / `removeField(...)` |
| TTI (9) | `Logger.logAppLaunchTTI(...)` | `logAppLaunchTTI(durationMs)` — for React Navigation, in the `onReady` callback |
| Spans (10) | `Logger.startSpan(name, level, fields)` | span API — confirm name/signature in $bd-docs |
| Device code (11) | `Logger.createTemporaryDeviceCode { }` | `generateDeviceCode()`; also `getSessionURL()`, `getDeviceId()` |
| Symbols (12) | ProGuard via `bdUpload*` | **Hermes source maps** via `bd debug-files upload-source-map` (or `bdUploadSourceMap`); native crashes still need dSYM (iOS) / ProGuard (Android) |
| New session (13) | `Logger.startNewSession()` | confirm the JS export in $bd-docs |
| Log forwarding (14) | Timber tree | No built-in transport — wrap `console.log/warn/error` → `info()/warning()/error()`, or add a `react-native-logs` transport |

React-Native-only gotchas:

- **Two install layers:** the JS package plus native pods/Gradle. After `npm install`, run `pod install` in `ios/`; Android autolinks. Crash symbolication needs **both** JS source maps and native symbols.
- **JS error reporting** is currently limited to builds on the **New Architecture + Hermes** engine — verify before relying on JS crash capture.
- **Network capture isn't guaranteed automatic** — confirm in $bd-docs whether RN auto-instruments `fetch`/XHR; otherwise wrap `fetch` or use an interceptor. Step 6 cardinality rules still apply.
- **Session URL for support** is `getSessionURL()` (capital URL).
- Functions are **top-level named exports** (`init`, `info`, `addField`, …), not methods on a `Logger` object — `import { … } from '@bitdrift/react-native'`.
