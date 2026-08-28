# Bitdrift Shop (Android — SDK)

**Version 5.0**

Demo Android app simulating an e-commerce shopping experience, **already instrumented with the bitdrift Capture SDK** (`io.bitdrift:capture:0.23.10` + the `io.bitdrift.capture-plugin`). It pairs with a FastAPI backend (Docker) that serves randomized products and configurable fault injection, so the app produces realistic sessions, network traffic, crashes, and performance signals out of the box.

For the no-SDK comparison target, see [`android-clean/`](../android-clean/). It
keeps the shopping flow and fault scenarios without Capture SDK configuration or
generated observability artifacts.

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

By default the app builds against the published `io.bitdrift:capture:0.23.10` Maven Central artifact. To validate an unreleased SDK build instead, set `BITDRIFT_USE_LOCAL_AAR` to the **full path** of the AAR to test, resolved in this order:

1. Command-line property: `./gradlew assembleDebug -PBITDRIFT_USE_LOCAL_AAR=/full/path/to/capture.aar`
2. `BITDRIFT_USE_LOCAL_AAR` in `.local.properties` or `local.properties`
3. `BITDRIFT_USE_LOCAL_AAR` env var
4. Unset, blank, or `false`: don't use a local AAR (published Maven Central SDK)

Every build prints which one is active, e.g. `bitdrift capture dependency: LOCAL AAR (/full/path/to/capture.aar)`. To test a different local build, point `BITDRIFT_USE_LOCAL_AAR` at the new file's path — no need to keep it named or located the same as before.

### Step 1: Start the backend

Needs a running Docker daemon — on macOS this repo uses [Colima](https://github.com/abiosoft/colima)
rather than Docker Desktop; see [backend/README.md](backend/README.md#prerequisites-macos) if
`docker ps` isn't already working.

```bash
cd backend
./start-backend-docker.sh
```

Want to correlate this app's bitdrift sessions with server-side Datadog APM traces for the same requests? Swap in the Datadog-instrumented backend variant instead — see [misc-demos/backend-ddtrace/](../../misc-demos/backend-ddtrace/).

> Only here for the **metrics/grouping demo**? Skip this step — it talks to bitdrift directly and
> never touches the backend. See [metric-demo.md](metric-demo.md#setup).

### Step 2: Run the app

Open in Android Studio and run on an emulator (API 36, 1080×2400, 2GB+ RAM). See [local config](README-refs.md#emulator-requirements) for details.

### Step 3: Generate data

On the emulator, use the Simulation buttons on the Welcome screen — tap **Sim 10** to run 10 journeys or **Sim ∞** for continuous simulation. The Sankey, crashes, network calls, spans, and session timelines populate in the dashboard in real time.

---

## What's already instrumented

Every Capture SDK feature below is wired up in this app, mapped to the call used and where it lives:

| Feature | SDK surface | Where it lives |
|---------|-------------|----------------|
| **SDK + build plugin** | `io.bitdrift:capture:0.23.10` (or a local AAR under test — see [Optional: test a local build](#optional-test-a-local-build-of-the-sdk)), `io.bitdrift.capture-plugin` | [build.gradle.kts](build.gradle.kts) |
| **Logger startup** | `Logger.start(...)` in `Application.onCreate()` | [ShoppingDemoApp.kt](app/src/main/java/ai/bitdrift/shop/ShoppingDemoApp.kt) |
| **Session strategy** | `SessionStrategy.Fixed()` | [ShoppingDemoApp.kt](app/src/main/java/ai/bitdrift/shop/ShoppingDemoApp.kt) |
| **Screen views** | `Logger.logScreenView()` via `NavController.OnDestinationChangedListener` | [MainActivity.kt](app/src/main/java/ai/bitdrift/shop/MainActivity.kt), [ScreenLogger.kt](app/src/main/java/ai/bitdrift/shop/ScreenLogger.kt) |
| **User identity** | `Logger.setEntityId("demo")` on launch, then rotated per simulated user | [ShoppingDemoApp.kt](app/src/main/java/ai/bitdrift/shop/ShoppingDemoApp.kt), [SimulationManager.kt](app/src/main/java/ai/bitdrift/shop/SimulationManager.kt) |
| **Network capture** | `CaptureOkHttpEventListenerFactory` on OkHttp | [ApiClient.kt](app/src/main/java/ai/bitdrift/shop/ApiClient.kt) |
| **Structured logs** | `Logger.logInfo/logWarning/logError` (`add_to_cart`, `checkout_started`, `payment_completed`, …) | [Screens.kt](app/src/main/java/ai/bitdrift/shop/Screens.kt), [SimulationManager.kt](app/src/main/java/ai/bitdrift/shop/SimulationManager.kt) |
| **Global fields** | `Logger.addField()` + `FieldProvider` — `user_id`, `app_variant`, `ff_*`, `supportlog`, `sim_app_version` | [ShoppingDemoApp.kt](app/src/main/java/ai/bitdrift/shop/ShoppingDemoApp.kt), [SimulationManager.kt](app/src/main/java/ai/bitdrift/shop/SimulationManager.kt), [MetricsDemo.kt](app/src/main/java/ai/bitdrift/shop/MetricsDemo.kt) |
| **Custom metrics** | `Logger.logInfo()` ticking once/sec (`metric_values`) — ported from misc-demos/metricdemo | [MetricsDemo.kt](app/src/main/java/ai/bitdrift/shop/MetricsDemo.kt) — see [metric-demo.md](metric-demo.md) |
| **App launch TTI** | `Logger.logAppLaunchTTI()` after first frame | [MainActivity.kt](app/src/main/java/ai/bitdrift/shop/MainActivity.kt) |
| **Custom spans** | `Logger.startSpan()` (`journey` → `product_discovery`, `checkout`), `Logger.trackSpan("score_products")` | [SimulationManager.kt](app/src/main/java/ai/bitdrift/shop/SimulationManager.kt), [Screens.kt](app/src/main/java/ai/bitdrift/shop/Screens.kt) |
| **Granular latency spans** | ~18 more spans: cold-start phases, per-screen loads, journey sub-phases, recommendation-engine internals — via `CaptureBridge.trackSpanSuspend`/`trackSpanNested` (the SDK's own `trackSpan` can't nest, suspend, or distinguish cancellation) | [CaptureBridge.kt](app/src/main/java/ai/bitdrift/shop/CaptureBridge.kt), and see [Span-timing workflows and dashboards](#span-timing-workflows-and-dashboards) |
| **Support tooling** | `Logger.createTemporaryDeviceCode()`, Support-Mode toggle | [Screens.kt](app/src/main/java/ai/bitdrift/shop/Screens.kt) |
| **Crash symbolication** | ProGuard mapping upload via `bdUpload*` tasks | [build.gradle.kts](build.gradle.kts) |
| **Session boundaries** | `Logger.startNewSession()` per simulated journey, and every 60s while the metrics demo runs | [SimulationManager.kt](app/src/main/java/ai/bitdrift/shop/SimulationManager.kt), [MetricsDemo.kt](app/src/main/java/ai/bitdrift/shop/MetricsDemo.kt) |

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
| **Per-phase latency histograms** | Granular latency spans | Where cold start, each screen load, and each journey sub-phase actually spend time (P50/P90/P99) |
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
| `bd-shop-12-metric-grouping.json` | custom metric log, custom field | Waveform + counter metrics ported from misc-demos/metricdemo; work-latency average/histogram/table grouped by simulated `sim_app_version` — see [metric-demo.md](metric-demo.md) |

### Span-timing workflows and dashboards

`bd-shop-20` through `bd-shop-23` chart the granular latency spans above. **They're
numbered to match the iOS app's `bd-shop-20`–`23` deliberately: the same number is the
same purpose on both platforms, and the span names are identical**.

These workflows target the Android app only, so their charts contain Android data
alone — the matching numbers are for navigating between the two platforms' configs, not
a live cross-platform view. Because the span names *are* identical (and both apps now
set a `platform` global field), a genuine side-by-side chart is one extra workflow away:
`platform_targets` accepts an array, so a workflow listing both `ai.bitdrift.shop`
(android) and `ai.bitdrift.shop.ios` (apple) matches both apps, and grouping its
histogram by `platform` gives one line per OS. Worth knowing before you do: the two
platforms' absolute numbers differ enough (emulator vs simulator especially) that an
ungrouped chart over both is a bimodal blob describing neither.

| Workflow | Live id | Dashboard | Covers |
|---|---|---|---|
| `bd-shop-20-android-cold-start-span-timings.json` | `RLXS` | [Cold-Start](https://explorations.bitdrift.io/dashboards/cQJTUdHJ3NQsm_H1NVsgf) | `app_cold_start` root + `sdk_init` / `scene_render` / `state_restore` |
| `bd-shop-21-android-screen-load-timings.json` | `vokX` | [Screen Load](https://explorations.bitdrift.io/dashboards/XpcvEcjfYuZU9GdgvYvtG) | 7 screen loads + per-thumbnail `product_image_load` |
| `bd-shop-22-android-journey-subphase-timings.json` | `GfJa` | [Journey Sub-Phase](https://explorations.bitdrift.io/dashboards/TdQHRtJe305Xjz4lEVV4h) | `discovery_fetch`, `product_view`, `wishlist_add`, `cart_assembly`, `checkout.payment`, `checkout.confirmation` |
| `bd-shop-23-android-recommendation-engine-timings.json` | `joJr` | [Recommendation Engine](https://explorations.bitdrift.io/dashboards/b8_b4FFF8xzstrR0b9Psg) | `score_products.parse_catalog` vs `.similarity_pass` |

Deploy them the same way as everything else in [`workflows/`](workflows/); the dashboards
live in [`dashboards/`](dashboards/) and each references its backing workflow ID above, so
**edit that ID before running `bd dashboard create`, not after** — otherwise the new
dashboard's charts point at this account's workflows.

Two things worth doing before demoing these:

- **Toggle "Rec v2"** on the Advanced screen if you want `bd-shop-23` populated — it's off
  by default and nothing in the automated sim turns it on. It's also the fastest way to see
  the point of the split: `parse_catalog` lands near 0ms while `similarity_pass` carries
  seconds.
- **Relaunch once on a fresh install.** `sdk_init` ends ~570ms into the process, before the
  on-device workflow engine has applied its config, so on the very first launch after
  install that one span is missing from its chart while the other phases (ending ~14s in)
  are fine. From the second launch it lands normally. Chart-only artifact — the span is in
  the Timeline waterfall either way.

Full per-workflow caveats, the Android-vs-iOS differences (no `catalog_serialize`, no
`bd-shop-24`, `wishlist_add` behaviour, the `uptimeMillis`→epoch clock conversion) and why
these don't use the SDK's own `Logger.trackSpan` are in
[`workflows/README.md`](workflows/README.md#span-timing-workflows-bd-shop-20-through-bd-shop-23).

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

## Deploy dashboards

Once the relevant workflows are deployed, compose their charts into curated dashboard views from
[`dashboards/`](dashboards/) — see [`dashboards/README.md`](dashboards/README.md) for why these
need one extra step versus workflows (a dashboard chart references an already-deployed workflow's
ID, so the placeholder in each file needs resolving first) and the exact deploy commands.

| Dashboard | Composes | Focus |
|-----------|----------|-------|
| `bd-shop-01-metric-grouping.json` | `bd-shop-12-metric-grouping.json` | Two tabs: work-latency average/histogram/table grouped by `sim_app_version`, and the ported waveform + CloudWatch consistency charts — see [metric-demo.md](metric-demo.md) |
| `android-cold-start-span-timings.dashboard.json` | `bd-shop-20` | Cold-start waterfall: total plus `sdk_init` / `scene_render` / `state_restore` |
| `android-screen-load-timings.dashboard.json` | `bd-shop-21` | Per-screen "time to data ready", plus per-thumbnail image load |
| `android-journey-subphase-timings.dashboard.json` | `bd-shop-22` | The six journey sub-phases, individually and compared |
| `android-recommendation-engine-timings.dashboard.json` | `bd-shop-23` | `score_products`: JSON parse vs the O(n*m) similarity pass |

> **Prompt:** *"Deploy the bd-shop-*.json dashboards to bitdrift using bd CLI, resolving each workflow ID placeholder first."* See [`dashboards/README.md`](dashboards/README.md) for deploy instructions.

---

## Reference

- **[README-refs.md](README-refs.md)** — screens (18), emulator setup, local config, simulation modes, entity list, project structure
- **[../../instrumentation-guide/](../../instrumentation-guide/)** — how to instrument **any** app (prompt-driven), plus a cleanup guide
- **[workflows/README.md](workflows/README.md)** — deploy and monitor workflows via bd CLI
- **[dashboards/README.md](dashboards/README.md)** — deploy dashboards that compose workflow charts via bd CLI
- **[workflows/foreground-background-crashes.md](workflows/foreground-background-crashes.md)** — foreground vs. background crash workflows: why they're separate, the BDRL behind each, and how to cross-check the split against real data
- **[workflows/advanced-crash-attribution.md](workflows/advanced-crash-attribution.md)** — blocking-thread and vendor-SDK crash attribution workflows, plus the attribution-rate chart that ties them together
- **[demo-slow-rendering.md](demo-slow-rendering.md)** — feature-flag-gated slow-rendering bug: setup, live trigger, dashboard/alert walkthrough, and how to diagnose + fix the offending code using bitdrift's output
- **[metric-demo.md](metric-demo.md)** — synthetic waveform metrics ported from misc-demos/metricdemo, plus a work-latency-by-app-version demo showing how to group/break down a custom metric by a dimension

**Simulation features:** [ANR-A](README-refs.md#anr-a-guest-journey-testing) · [Force Quit](README-refs.md#force-quit-journey-testing) · [Crash Loop](README-refs.md#crash-loop) · [Slow Rendering](demo-slow-rendering.md) · [Metric Grouping](metric-demo.md)

## Architecture

```
┌─────────────────────┐        HTTP (OkHttp)        ┌──────────────────────┐
│   Android Emulator   │ ◄─────────────────────────► │  FastAPI Server       │
│   (10.0.2.2:5173)    │    JSON request/response    │  (localhost:5173)     │
└─────────────────────┘                              └──────────────────────┘
```

See [project structure and requirements](README-refs.md#project-structure) for the full file tree and dependencies.
