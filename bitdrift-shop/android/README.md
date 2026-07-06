# Bitdrift Shop (Android — SDK)

**Version 3.0**

Demo Android app simulating an e-commerce shopping experience, **already instrumented with the bitdrift Capture SDK** (`io.bitdrift:capture:0.23.9` + the `io.bitdrift.capture-plugin`). It pairs with a FastAPI backend (Docker) that serves randomized products and configurable fault injection, so the app produces realistic sessions, network traffic, crashes, and performance signals out of the box.

This is community-contributed content provided for educational purposes only.

> ⚠️ **Run `scripts/watchdog.sh` before enabling any crash/fault mode.** If **Crash Loop**, **ANR-A**, or **Force-Quit** is turned on (Advanced screen), the watchdog must already be running against the target emulator:
> ```bash
> ./scripts/watchdog.sh
> ```
> These modes deliberately crash, freeze, or kill the app so bitdrift has faults to capture. Without the watchdog polling and relaunching the app, the emulator gets stuck on a dead process or a frozen ANR dialog and the simulation stalls instead of continuing. See [Crash Loop](README-refs.md#crash-loop), [ANR-A](README-refs.md#anr-a-guest-journey-testing), and [Force-Quit](README-refs.md#force-quit-journey-testing) for what each mode does and how the watchdog recovers from it.
>
> **Fast Crash Mode fires too quickly to stop from the UI.** If you enabled "Fast crash mode" on the startup splash screen, tapping "Stop crash loop" won't reliably catch it — use the `adb` commands under [Stopping Fast Crash Mode](README-refs.md#crash-loop) instead.

> Want to instrument **your own** app? This README documents what's already wired up here. For a step-by-step, prompt-driven walkthrough you can apply to any app, see the repository's [instrumentation-guide/](../../instrumentation-guide/).

## Quick Start

### Step 0: Configure your bitdrift credentials

Create `.local.properties` in this directory (gitignored — your real values go here, overlaying the blank `local.properties` template):

```properties
BITDRIFT_SDK_KEY=<your-sdk-key>
BITDRIFT_API_HOST=api.bitdrift.io
```

Get the SDK key from **bitdrift dashboard → Settings → SDK Keys**. The key determines which project your data lands in — crashes, sessions, and workflows only appear in the project that owns this key, scoped to the `ai.bitdrift.shop` app.

### Step 1: Start the backend

```bash
cd backend
./start-backend-docker.sh
```

### Step 2: Run the app

Open in Android Studio and run on an emulator (API 36, 1080×2400, 2GB+ RAM). See [local config](README-refs.md#emulator-requirements) for details.

### Step 3: Generate data

On the emulator, use the Simulation buttons on the Welcome screen — tap **Sim 10** to run 10 journeys or **Sim ∞** for continuous simulation. The Sankey, crashes, network calls, spans, and session timelines populate in the dashboard in real time.

---

## What's already instrumented

Every Capture SDK feature below is wired up in this app. The table maps each to the call used and the file where it lives, so you can read the real implementation.

| Feature | SDK surface | Where it lives |
|---------|-------------|----------------|
| **SDK + build plugin** | `io.bitdrift:capture:0.23.9`, `io.bitdrift.capture-plugin` | [build.gradle.kts](build.gradle.kts), [app/build.gradle.kts](app/build.gradle.kts) |
| **Logger startup** | `Logger.start(apiKey, apiUrl, sessionStrategy, fieldProviders)` in `Application.onCreate()` | [ShoppingDemoApp.kt](app/src/main/java/ai/bitdrift/shop/ShoppingDemoApp.kt) |
| **Session strategy** | `SessionStrategy.Fixed()` (fresh session per launch) | [ShoppingDemoApp.kt](app/src/main/java/ai/bitdrift/shop/ShoppingDemoApp.kt) |
| **Screen views** | `Logger.logScreenView()` via a centralized `NavController.OnDestinationChangedListener` | [MainActivity.kt](app/src/main/java/ai/bitdrift/shop/MainActivity.kt), [ScreenLogger.kt](app/src/main/java/ai/bitdrift/shop/ScreenLogger.kt) |
| **User identity** | `Logger.setEntityId()` (rotates simulated users so each journey is a distinct entity) | [SimulationManager.kt](app/src/main/java/ai/bitdrift/shop/SimulationManager.kt) |
| **Network capture** | `CaptureOkHttpEventListenerFactory` on the OkHttp clients, plus an `x-capture-path-template` header on the dynamic `/api/inventory/lookup/<item>/<session>` route | [ApiClient.kt](app/src/main/java/ai/bitdrift/shop/ApiClient.kt) |
| **Structured logs** | `Logger.logInfo/logWarning/logError` with stable event names and field-based data (`add_to_cart`, `checkout_started`, `payment_completed`, `payment_failed`, `memory_pressure`, …) | [Screens.kt](app/src/main/java/ai/bitdrift/shop/Screens.kt), [SimulationManager.kt](app/src/main/java/ai/bitdrift/shop/SimulationManager.kt), [AppLifecycleCallbacks.kt](app/src/main/java/ai/bitdrift/shop/AppLifecycleCallbacks.kt) |
| **Global fields** | `Logger.addField()`/`removeField()` plus a `FieldProvider` (`UserIdFieldProvider`) — sets `user_id`, `app_variant`, the `ff_*` feature-flag/variant fields, `crash_kind`, and `supportlog` | [ShoppingDemoApp.kt](app/src/main/java/ai/bitdrift/shop/ShoppingDemoApp.kt), [SimulationManager.kt](app/src/main/java/ai/bitdrift/shop/SimulationManager.kt), [Screens.kt](app/src/main/java/ai/bitdrift/shop/Screens.kt) |
| **App launch TTI** | process-start timestamp + `Logger.logAppLaunchTTI()` after the first frame | [ShoppingDemoApp.kt](app/src/main/java/ai/bitdrift/shop/ShoppingDemoApp.kt), [MainActivity.kt](app/src/main/java/ai/bitdrift/shop/MainActivity.kt) |
| **Custom spans** | `Logger.startSpan()` with a nested hierarchy — `journey` (root) → `product_discovery`, `checkout` — and `Logger.trackSpan("score_products")` for synchronous work | [SimulationManager.kt](app/src/main/java/ai/bitdrift/shop/SimulationManager.kt), [Screens.kt](app/src/main/java/ai/bitdrift/shop/Screens.kt) |
| **Support tooling** | `Logger.createTemporaryDeviceCode()` and a Support-Mode toggle that sets the `supportlog` field | [Screens.kt](app/src/main/java/ai/bitdrift/shop/Screens.kt) (Welcome screen) |
| **Crash symbolication** | ProGuard mapping/symbol upload via the build plugin's `bdUpload*` tasks (release builds) | [build.gradle.kts](build.gradle.kts) |
| **Session boundaries** | `Logger.startNewSession()` at the start of each simulated journey, with global fields re-applied afterward | [SimulationManager.kt](app/src/main/java/ai/bitdrift/shop/SimulationManager.kt) |

The app also exercises fault scenarios on top of this instrumentation — ANR, force-quit, crash loop, and slow-frame demos — driven from the simulation controls and the `crash_kind`/`crash_context` fields. Each crash-loop firing now has an independent 50% chance of happening in the foreground or after backgrounding the app (`moveTaskToBack`), so every crash type can be observed in either app state — see [Crash Loop](README-refs.md#crash-loop) and [workflows/foreground-background-crashes.md](workflows/foreground-background-crashes.md).

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

Once the app is generating data, use the **bd-cli** skill to deploy the ten sample workflows in [`workflows/`](workflows/) — each turns the signals above into metrics, alerts, or funnels:

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

## Issue (Crash) Analytics
### What the `issue-match` demos (06–10) show

These five run server-side against the full crash Report, not on-device against a log line. bitdrift uniquely allows turning crash data into a **standing, ingest-time chart** across every crash automatically, instead of a human reading one report at a time.

- **Foreground vs. background** (`bd-shop-06`/`07`) — splits crash volume by app state (`app_metrics.running_state`) without creating new issue groups
  - *Mobile dev owners:* separates crashes a user was actively looking at from crashes during backgrounded/OS-driven work, without instrumenting a new field per crash type — triage what's actually user-visible first
  - *Business owners:* quantifies how much of your crash volume is actually hurting the visible experience (the part that drives churn, support tickets, and store ratings) vs. invisible background noise — sharpens where engineering time should go
- **Blocking thread attribution** (`bd-shop-08`) — searches `thread_details.threads[]` for a known contention pattern and charts which thread was holding the lock
  - *Mobile dev owners:* turns a manual "open this one report and read the thread dump" investigation into a standing chart that continuously flags lock/monitor contention across the whole fleet, so a recurring concurrency bug surfaces on its own
  - *Business owners:* concurrency bugs are some of the most expensive crashes to diagnose in engineering hours — a chart that already points at the blocking thread shortens time-to-fix on exactly the class of bug that otherwise eats weeks
- **Vendor SDK attribution** (`bd-shop-09`) — searches stack frames across **every** error in the report (not just the top one) for a third-party namespace, and charts crash share by vendor
  - *Mobile dev owners:* automatically classifies "is this our bug or a vendor's" for every crash, instead of manually bucketing each new crash type by hand
  - *Business owners:* directly quantifies how much instability is caused by a third-party SDK instead of your own app — the evidence you need when negotiating with an ad/analytics vendor, deciding whether to drop a dependency, or explaining a crash-free-rate dip that isn't your team's fault
- **Attribution rate** (`bd-shop-10`) — ties the two above together with BDRL's `rate` action (two independent flows, one used as numerator, one as denominator) into a single "% of crashes we can explain" chart, rather than leaving 08/09 as two disconnected bar charts
  - *Mobile dev owners:* one continuously-updating number for "how much of our crash volume do we actually understand," trackable like any other engineering SLO
  - *Business owners:* a single "% of crashes explained" KPI is legible to a non-engineering stakeholder — "we understand root cause for X% of crashes and are closing the gap" is a far easier story to tell in a business review than a raw crash count

> **Prompt:** *"Deploy the bd-shop-*.json workflows to bitdrift using bd CLI and verify they transition to LIVE status."*

See [`workflows/README.md`](workflows/README.md) for deploy instructions.

---

## Reference

- **[README-refs.md](README-refs.md)** — screens (18), emulator setup, local config, simulation modes, entity list, project structure
- **[../../instrumentation-guide/](../../instrumentation-guide/)** — how to instrument **any** app (prompt-driven), plus a cleanup guide
- **[workflows/README.md](workflows/README.md)** — deploy and monitor workflows via bd CLI
- **[workflows/foreground-background-crashes.md](workflows/foreground-background-crashes.md)** — foreground vs. background crash workflows: why they're separate, the BDRL behind each, and how to cross-check the split against real data
- **[workflows/advanced-crash-attribution.md](workflows/advanced-crash-attribution.md)** — blocking-thread and vendor-SDK crash attribution workflows, plus the attribution-rate chart that ties them together

**Simulation features:** [ANR-A](README-refs.md#anr-a-guest-journey-testing) · [Force Quit](README-refs.md#force-quit-journey-testing) · [Crash Loop](README-refs.md#crash-loop) · [Slow Frames](README-refs.md#slow-frames-performance-bug-demo)

## Architecture

```
┌─────────────────────┐        HTTP (OkHttp)        ┌──────────────────────┐
│   Android Emulator   │ ◄─────────────────────────► │  FastAPI Server       │
│   (10.0.2.2:5173)    │    JSON request/response    │  (localhost:5173)     │
└─────────────────────┘                              └──────────────────────┘
```

See [project structure and requirements](README-refs.md#project-structure) for the full file tree and dependencies.
