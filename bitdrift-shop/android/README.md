# Bitdrift Shop (Android — SDK)

**Version 3.4**

Demo Android app simulating an e-commerce shopping experience, **already instrumented with the bitdrift Capture SDK** (`io.bitdrift:capture:0.23.9` + the `io.bitdrift.capture-plugin`). It pairs with a FastAPI backend (Docker) that serves randomized products and configurable fault injection, so the app produces realistic sessions, network traffic, crashes, and performance signals out of the box.

This is community-contributed content provided for educational purposes only.

> ⚠️ **Run `./scripts/watchdog.sh` before enabling Crash Loop, ANR-A, or Force-Quit** (Advanced screen) — these modes deliberately crash, freeze, or kill the app, and without the watchdog relaunching it the emulator gets stuck. Fast Crash Mode fires too fast to stop from the UI — use `adb` instead. Details: [Crash Loop](README-refs.md#crash-loop), [ANR-A](README-refs.md#anr-a-guest-journey-testing), [Force-Quit](README-refs.md#force-quit-journey-testing).
>
> **These flags persist across restarts by design** (so each mode survives its own crash/relaunch cycle) — which means leaving one on and later starting an unrelated demo leaves it silently armed. Run `./scripts/check-demo-state.sh` (add `--reset` to clear) before starting any demo session.

> Want to instrument **your own** app instead? See [instrumentation-guide/](../../instrumentation-guide/) for a prompt-driven walkthrough.

## Quick Start

### Step 0: Configure your bitdrift credentials

Create `.local.properties` in this directory (gitignored — your real values go here, overlaying the blank `local.properties` template):

```properties
BITDRIFT_SDK_KEY=<your-sdk-key>
BITDRIFT_API_HOST=api.bitdrift.io
```

Get the SDK key from **bitdrift dashboard → Settings → SDK Keys**. The key determines which project your data lands in — crashes, sessions, and workflows only appear in the project that owns this key, scoped to the `ai.bitdrift.shop` app.

For bitdrift-internal testing against a non-production environment, point `BITDRIFT_API_HOST` at that environment instead (e.g. `api.bitdrift.dev`) — just make sure the SDK key is one issued by that same environment's dashboard.

### Optional: test a local build of the SDK

By default the app builds against the published `io.bitdrift:capture:0.23.9` Maven Central artifact. To validate an unreleased SDK build instead, set `BITDRIFT_USE_LOCAL_AAR` to the **full path** of the AAR to test, resolved in this order:

1. Command-line property: `./gradlew assembleDebug -PBITDRIFT_USE_LOCAL_AAR=/full/path/to/capture.aar`
2. `BITDRIFT_USE_LOCAL_AAR` in `.local.properties` or `local.properties`
3. `BITDRIFT_USE_LOCAL_AAR` env var
4. Unset, blank, or `false`: don't use a local AAR (published Maven Central SDK)

Every build prints which one is active, e.g. `bitdrift capture dependency: LOCAL AAR (/full/path/to/capture.aar)`. To test a different local build, point `BITDRIFT_USE_LOCAL_AAR` at the new file's path — no need to keep it named or located the same as before.

### Step 1: Start the backend

```bash
cd backend
./start-backend-docker.sh
```

Want to correlate this app's bitdrift sessions with server-side Datadog APM traces for the same requests? Swap in the Datadog-instrumented backend variant instead — see [misc-demos/backend-ddtrace/](../../misc-demos/backend-ddtrace/).

### Step 2: Run the app

Open in Android Studio and run on an emulator (API 36, 1080×2400, 2GB+ RAM). See [local config](README-refs.md#emulator-requirements) for details.

### Step 3: Generate data

On the emulator, use the Simulation buttons on the Welcome screen — tap **Sim 10** to run 10 journeys or **Sim ∞** for continuous simulation. The Sankey, crashes, network calls, spans, and session timelines populate in the dashboard in real time.

---

## What's already instrumented

Every Capture SDK feature below is wired up in this app, mapped to the call used and where it lives:

| Feature | SDK surface | Where it lives |
|---------|-------------|----------------|
| **SDK + build plugin** | `io.bitdrift:capture:0.23.9` (or a local AAR under test — see [Optional: test a local build](#optional-test-a-local-build-of-the-sdk)), `io.bitdrift.capture-plugin` | [build.gradle.kts](build.gradle.kts) |
| **Logger startup** | `Logger.start(...)` in `Application.onCreate()` | [ShoppingDemoApp.kt](app/src/main/java/ai/bitdrift/shop/ShoppingDemoApp.kt) |
| **Session strategy** | `SessionStrategy.Fixed()` | [ShoppingDemoApp.kt](app/src/main/java/ai/bitdrift/shop/ShoppingDemoApp.kt) |
| **Screen views** | `Logger.logScreenView()` via `NavController.OnDestinationChangedListener` | [MainActivity.kt](app/src/main/java/ai/bitdrift/shop/MainActivity.kt), [ScreenLogger.kt](app/src/main/java/ai/bitdrift/shop/ScreenLogger.kt) |
| **User identity** | `Logger.setEntityId("demo")` on launch, then rotated per simulated user | [ShoppingDemoApp.kt](app/src/main/java/ai/bitdrift/shop/ShoppingDemoApp.kt), [SimulationManager.kt](app/src/main/java/ai/bitdrift/shop/SimulationManager.kt) |
| **Network capture** | `CaptureOkHttpEventListenerFactory` on OkHttp | [ApiClient.kt](app/src/main/java/ai/bitdrift/shop/ApiClient.kt) |
| **Structured logs** | `Logger.logInfo/logWarning/logError` (`add_to_cart`, `checkout_started`, `payment_completed`, …) | [Screens.kt](app/src/main/java/ai/bitdrift/shop/Screens.kt), [SimulationManager.kt](app/src/main/java/ai/bitdrift/shop/SimulationManager.kt) |
| **Global fields** | `Logger.addField()` + `FieldProvider` — `user_id`, `app_variant`, `ff_*`, `supportlog` | [ShoppingDemoApp.kt](app/src/main/java/ai/bitdrift/shop/ShoppingDemoApp.kt), [SimulationManager.kt](app/src/main/java/ai/bitdrift/shop/SimulationManager.kt) |
| **App launch TTI** | `Logger.logAppLaunchTTI()` after first frame | [MainActivity.kt](app/src/main/java/ai/bitdrift/shop/MainActivity.kt) |
| **Custom spans** | `Logger.startSpan()` (`journey` → `product_discovery`, `checkout`), `Logger.trackSpan("score_products")` | [SimulationManager.kt](app/src/main/java/ai/bitdrift/shop/SimulationManager.kt), [Screens.kt](app/src/main/java/ai/bitdrift/shop/Screens.kt) |
| **Support tooling** | `Logger.createTemporaryDeviceCode()`, Support-Mode toggle | [Screens.kt](app/src/main/java/ai/bitdrift/shop/Screens.kt) |
| **Crash symbolication** | ProGuard mapping upload via `bdUpload*` tasks | [build.gradle.kts](build.gradle.kts) |
| **Session boundaries** | `Logger.startNewSession()` per simulated journey | [SimulationManager.kt](app/src/main/java/ai/bitdrift/shop/SimulationManager.kt) |

Fault scenarios built on top of this instrumentation: ANR, force-quit, crash loop (see [Crash Loop](README-refs.md#crash-loop), [foreground-background-crashes.md](workflows/foreground-background-crashes.md)) and a feature-flag-gated slow-rendering demo (see [demo-slow-rendering.md](demo-slow-rendering.md)).

## What this lights up in the dashboard

With the instrumentation above, the app feeds these bitdrift features — most with no extra configuration:

| Feature | Driven by | What it shows |
|---------|-----------|---------------|
| **Instant Insights** | Logger startup | Crash count, network p50/p95, memory pressure, app launches |
| **Session Timeline** | Every log/event/span | Full breadcrumb trail of actions, network calls, and errors |
| **User Journey Sankey** | Screen views | Screen-to-screen flow, dropout points, variant comparison |
| **TTI histogram** | App launch TTI | p50/p95/p99 app startup times |
| **Spans waterfall** | Custom spans | Operation durations for journey, discovery, and checkout |
| **Entities view** | User identity | Per-user session history, crashes, devices, location |
| **Network tab** | Network capture | Latency, errors, throughput by endpoint |

---

## Deploy workflows for evaluation

Once the app is generating data, use the **bd-cli** skill to deploy the twelve sample workflows in [`workflows/`](workflows/) — each turns the signals above into metrics, alerts, or funnels:

| Workflow | Uses | Focus |
|----------|------|-------|
| `bd-shop-01-checkout-funnel.json` | screen views, spans | User-journey Sankey, funnel metrics, A/B variant comparison |
| `bd-shop-02-payment-errors.json` | custom logs, entity ID | Log matching, error categorization, real-time alerts |
| `bd-shop-03-crash-analytics.json` | logger, symbols | Crash issue matching, readable stacks |
| `bd-shop-04-span-durations.json` | spans, global fields | Span histograms, SLO tracking, perf by variant |
| `bd-shop-05-anr-force-quit.json` | logger, fields | Android fault tracking (ANR, force-quit), variant rates |
| `bd-shop-06-crash-foreground.json` | issue-match BDRL, `app_metrics.running_state` | Crash count while the app is in the foreground |
| `bd-shop-07-crash-background.json` | issue-match BDRL, `app_metrics.running_state` | Crash count while the app is backgrounded — see [foreground-background-crashes.md](workflows/foreground-background-crashes.md) |
| `bd-shop-08-blocking-thread.json` | issue-match BDRL, `thread_details` | Lock-contention crash count grouped by blocking thread — see [advanced-crash-attribution.md](workflows/advanced-crash-attribution.md) |
| `bd-shop-09-vendor-sdk-attribution.json` | issue-match BDRL, cross-error stack frames | Crash count grouped by vendor SDK namespace — see [advanced-crash-attribution.md](workflows/advanced-crash-attribution.md) |
| `bd-shop-10-attribution-rate.json` | issue-match BDRL, `rate` chart | % of crashes attributable to a known cause — see [advanced-crash-attribution.md](workflows/advanced-crash-attribution.md) |
| `bd-shop-11-slow-rendering.json` | on-device frame detection, feature flag exposure | Zero-instrumentation dropped-frame count/histogram split by `recommendations_v2` exposure and by screen; alert on frame-drop spikes — see [demo-slow-rendering.md](demo-slow-rendering.md) |
| `bd-shop-11b-slow-rendering-manual-span.json` | custom span, feature flag exposure | Same shape as bd-shop-11, matched on a manually-instrumented span instead — illustrative comparison, no alert — see [demo-slow-rendering.md](demo-slow-rendering.md) |

## Issue (Crash) Analytics

The `issue-match` demos (06–10) run server-side against the full crash Report, not on-device
against a log line — turning crash data into a **standing, ingest-time chart** across every
crash automatically, instead of a human reading one report at a time:

- **Foreground vs. background** (06/07) — splits crash volume by app state
- **Blocking thread attribution** (08) — charts which thread was holding the lock
- **Vendor SDK attribution** (09) — charts crash share by third-party namespace
- **Attribution rate** (10) — ties 08/09 together into a single "% of crashes explained" chart

Business/engineering framing for each: [foreground-background-crashes.md](workflows/foreground-background-crashes.md), [advanced-crash-attribution.md](workflows/advanced-crash-attribution.md).

> **Prompt:** *"Deploy the bd-shop-*.json workflows to bitdrift using bd CLI and verify they transition to LIVE status."* See [`workflows/README.md`](workflows/README.md) for deploy instructions.

---

## Reference

- **[README-refs.md](README-refs.md)** — screens (18), emulator setup, local config, simulation modes, entity list, project structure
- **[../../instrumentation-guide/](../../instrumentation-guide/)** — how to instrument **any** app (prompt-driven), plus a cleanup guide
- **[workflows/README.md](workflows/README.md)** — deploy and monitor workflows via bd CLI
- **[workflows/foreground-background-crashes.md](workflows/foreground-background-crashes.md)** — foreground vs. background crash workflows: why they're separate, the BDRL behind each, and how to cross-check the split against real data
- **[workflows/advanced-crash-attribution.md](workflows/advanced-crash-attribution.md)** — blocking-thread and vendor-SDK crash attribution workflows, plus the attribution-rate chart that ties them together
- **[demo-slow-rendering.md](demo-slow-rendering.md)** — feature-flag-gated slow-rendering bug: setup, live trigger, dashboard/alert walkthrough, and how to diagnose + fix the offending code using bitdrift's output

**Simulation features:** [ANR-A](README-refs.md#anr-a-guest-journey-testing) · [Force Quit](README-refs.md#force-quit-journey-testing) · [Crash Loop](README-refs.md#crash-loop) · [Slow Rendering](demo-slow-rendering.md)

## Architecture

```
┌─────────────────────┐        HTTP (OkHttp)        ┌──────────────────────┐
│   Android Emulator   │ ◄─────────────────────────► │  FastAPI Server       │
│   (10.0.2.2:5173)    │    JSON request/response    │  (localhost:5173)     │
└─────────────────────┘                              └──────────────────────┘
```

See [project structure and requirements](README-refs.md#project-structure) for the full file tree and dependencies.
