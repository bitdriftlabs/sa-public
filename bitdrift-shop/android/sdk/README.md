# Bitdrift Shop (Android — SDK)

Demo Android app simulating an e-commerce shopping experience, instrumented with the bitdrift Capture SDK for proof-of-concept evaluation. Follow the **13-step instrumentation checklist** below to understand what each SDK feature unlocks for your POC.

Includes a FastAPI backend (Docker) serving randomized products and configurable fault injection for realistic testing scenarios.

This is community contributed content to serve only for educational purposes.

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

Open in Android Studio and run on emulator (API 36, 1080×2400, 2GB+ RAM). See [local config](README-refs.md#emulator-requirements) for details.

---

## How to Use This README with Bitdrift Skills

This README is designed to be used **with agent skills**, not as a manual copy-paste guide:

**For humans:** Read each step's **Skill prompt** and **POC criteria** to understand what to do and why. Click **Code reference** links to see actual implementation.

**For agents:** Use the 13-step checklist as a specification. Example prompt:

> "Instrument the bitdrift shop Android app for POC evaluation. Follow the 13-step checklist in README.md: use the bd-instrumentation skill to implement steps 1–6 (SDK setup, logging, screen views, network), then report what was installed and what to do next."

The agent will:
1. Read the README to understand the 13 steps
2. Invoke the `bd-instrumentation` skill with context from each step
3. Verify each step completed
4. Link back to README sections for reference

**Skills available:**
- **bd-instrumentation** — Add SDK dependency, initialize logger, instrument screen views, network, logs, spans
- **bd-cli** — Deploy workflows, read charts, manage API keys
- **bd-docs** — Understand bitdrift features and behavior
- **mobile-dev** — Answer Android development questions

---

## Instrumentation Checklist — 13 Steps to POC Readiness

Each step uses the **bd-instrumentation** skill to implement an SDK feature. Follow in order — later steps build on earlier ones.

### Step 1: Add the Capture SDK Dependency
**Skill prompt:** "Add the bitdrift Capture SDK and Gradle plugin to the Android project"

**POC criteria:** The prerequisite every success criterion rides on.

**Unlocks:** Everything. No other step works without this. 

**Code reference:** [Step 1: Add the Capture SDK Dependency](INSTRUMENTATION_GUIDE.md#1-add-the-dependency)

---

### Step 2: Start the Logger in Application.onCreate()
**Skill prompt:** "Initialize Logger.start() with SessionStrategy.Fixed() in the Application class"

**POC criteria:** Evaluates crash detection, memory monitoring, and visual performance — these OOTB signals light up automatically.

**Unlocks:** Instant Insights dashboards (app launches, crashes, network, resources), session timeline, automatic instrumentation (memory pressure, battery, orientation changes, slow frames).

**Code reference:** [Step 2: Start the Logger in Application.onCreate()](INSTRUMENTATION_GUIDE.md#2-start-the-logger)

---

### Step 3: Confirm Session Strategy
**Skill prompt:** "Review session strategy in Logger.start() — confirm SessionStrategy.Fixed() for demo use"

**POC criteria:** Evaluates session management — full capture without the cost–coverage trade-off.

**Unlocks:** Correct session grouping in Timeline.

**Code reference:** [Step 3: Confirm Session Strategy](INSTRUMENTATION_GUIDE.md#3-confirm-session-strategy)

---

### Step 4: Instrument Screen Views
**Skill prompt:** "Add Logger.logScreenView() calls to track navigation via NavController.OnDestinationChangedListener"

**POC criteria:** Covers screen-names pre-work and helps evaluate per-screen crash analytics.

**Unlocks:** User Journey (Sankey) diagram in Instant Insights. Each screen appears as a node; edge thickness shows flow. Foundation for funnel analysis.

**Code reference:** [Step 4: Instrument Screen Views](INSTRUMENTATION_GUIDE.md#4-instrument-screen-views)

---

### Step 5: Identify Users with Entity ID
**Skill prompt:** "Call Logger.setEntityId() at session start to tag users by ID or name"

**POC criteria:** Helps evaluate ad-hoc debugging — retrieve any user's session on demand.

**Unlocks:** Entities feature. Search by entity name in the dashboard to see all their sessions, crashes, devices, and last location.

**Code reference:** [Step 5: Identify Users with Entity ID](INSTRUMENTATION_GUIDE.md#5-identify-users-with-entity-id) · [Entity list](README-refs.md#entities) · [Simulation probabilities](README-refs.md#probabilistic-state-machine)

---

### Step 6: Capture Network Traffic
**Skill prompt:** "Add CaptureOkHttpEventListenerFactory to OkHttpClient and set x-capture-path-template headers for dynamic paths"

**POC criteria:** Covers the networking pre-work and helps evaluate network monitoring — unsampled latency, error rates, and throughput per endpoint.

**Unlocks:** Network tab in Instant Insights (p50/p95 latency, error rate, throughput by endpoint). Correlate payment failures with exact HTTP errors on Timeline.

**Code reference:** [Step 6: Capture Network Traffic](INSTRUMENTATION_GUIDE.md#6-capture-network-traffic)

---

### Step 7: Emit Structured Custom Logs
**Skill prompt:** "Add Logger.logInfo/logError calls with stable event names and field-based variables to track checkout, payments, and errors"

**POC criteria:** Covers the beacon/analytics-event pre-work and helps evaluate log forwarding & integration.

**Unlocks:** Workflow matching, custom metrics (count, rate, histogram of any field), Timeline breadcrumbs, alert triggers.

**Code reference:** [Step 7: Emit Structured Custom Logs](INSTRUMENTATION_GUIDE.md#7-emit-structured-custom-logs)

---

### Step 8: Attach Global Fields
**Skill prompt:** "Call Logger.addField() to attach user_id, app_variant, and other context fields that persist for a session"

**POC criteria:** Helps evaluate insights & visualization — slice dashboards by any cohort.

**Unlocks:** Dashboard filtering and slicing by any global field. Filter sessions by `app_variant`, `user_tier`, or custom fields.

**Code reference:** [Step 8: Attach Global Fields](INSTRUMENTATION_GUIDE.md#8-attach-global-fields)

---

### Step 9: Report App Launch TTI
**Skill prompt:** "Capture SystemClock.uptimeMillis() at app start and call Logger.logAppLaunchTTI() after first frame"

**POC criteria:** Helps evaluate event tracking — unsampled p50/p90/p99 for a key flow.

**Unlocks:** App Launch TTI chart in Instant Insights → UX. p50/p95/p99 latency histograms across your whole user population.

**Code reference:** [Step 9: Report App Launch TTI](INSTRUMENTATION_GUIDE.md#9-report-app-launch-tti)

---

### Step 10: Measure Operations with Custom Spans
**Skill prompt:** "Wrap multi-step operations with Logger.startSpan() / span.end() to emit _duration_ms histograms for journey, checkout, and discovery flows"

**POC criteria:** Helps evaluate event tracking — precise percentile durations for critical flows.

**Unlocks:** Spans Visualization in session Timeline (waterfall chart). Query `_duration_ms` in Workflows to plot p50/p95 of any operation. Compare operation duration by user segment.

**Code reference:** [Step 10: Measure Operations with Custom Spans](INSTRUMENTATION_GUIDE.md#10-measure-operations-with-custom-spans)

---

### Step 11: Implement Device Identification for Support
**Skill prompt:** "Add Logger.createTemporaryDeviceCode() and supportlog toggle to enable support teams to retrieve sessions without device logs"

**POC criteria:** Helps evaluate the end-to-end debugging workflow — pull a reported session without a repro.

**Unlocks:** Support teams can pull any user's session in real time without shipping debug builds.

**Code reference:** [Step 11: Implement Device Identification for Support](INSTRUMENTATION_GUIDE.md#11-implement-device-identification-for-support)

---

### Step 12: Upload Symbol Files for Readable Crash Stacks
**Skill prompt:** "Run bd CLI or Gradle task to upload ProGuard mappings after release builds"

**POC criteria:** Helps evaluate crash detection — readable stacks with full session context.

**Unlocks:** Human-readable stack traces in the Issues view.

**Code reference:** [Step 12: Upload Symbol Files for Readable Crash Stacks](INSTRUMENTATION_GUIDE.md#12-upload-symbol-files-for-readable-crash-stacks)

---

### Step 13: New Session on User Logout or Journey Reset
**Skill prompt:** "Call Logger.startNewSession() on logout or when resetting user context"

**POC criteria:** Ensures session boundaries align with your app's ownership model.

**Unlocks:** Clean session segmentation by user login/logout lifecycle.

**Code reference:** [Step 13: New Session on User Logout or Journey Reset](INSTRUMENTATION_GUIDE.md#13-new-session-on-user-logout-or-journey-reset)

---

## After the 13 Steps — What Lights Up Automatically

Once you complete steps 1–13, the app automatically feeds data to these bitdrift features **without any additional configuration**:

| Feature | Enabled by | What it shows |
|---------|-----------|---|
| **Instant Insights dashboards** | Step 2 (Logger.start()) | Crash count, network p50/p95, memory pressure, app launches |
| **Session Timeline** | Every log/event | Full breadcrumb trail of user actions, network calls, errors |
| **User Journey Sankey** | Step 4 (screen views) | Screen-to-screen flow; dropout points; variant comparison |
| **TTI histogram** | Step 9 (logAppLaunchTTI) | p50/p95/p99 app startup times |
| **Spans waterfall** | Step 10 (custom spans) | Timeline visualization of operation durations |
| **Entities view** | Step 5 (setEntityId) | Per-user session history, crashes, devices, location |
| **Network tab** | Step 6 (OkHttp capture) | Latency, errors, throughput by endpoint |

**To generate test data:** Open the app on the emulator and use the Simulation buttons on the Welcome screen (tap **Sim 10** to run 10 journeys or **SIM ∞** for continuous simulation). You'll see the Sankey, crashes, network calls, and session timelines populate in real time.

---

## Deploy Workflows for POC Evaluation

Once the app is running and generating data, use the **bd-cli** skill to deploy the five suggested workflows in [`workflows/`](workflows/). Each demonstrates a metric type mentioned in the instrumentation checklist:

| Workflow | Steps it uses | POC focus |
|----------|---|---|
| `bd-shop-01-checkout-funnel.json` | 4 (screen views), 10 (spans) | Screen-based user journey sankey, funnel metrics, A/B variant comparison |
| `bd-shop-02-payment-errors.json` | 7 (custom logs), 5 (entity ID) | Log matching, error categorization, real-time alerts |
| `bd-shop-03-crash-analytics.json` | 2 (logger), 12 (symbols) | Crash issue matching, BDRL categorization, readable stacks |
| `bd-shop-04-span-durations.json` | 10 (spans), 8 (global fields) | Span histograms, SLO tracking, performance impact by variant |
| `bd-shop-05-anr-force-quit.json` | 2 (logger), 8 (fields) | Android fault tracking (ANR, force-quit), variant-specific rates |

**Skill prompt:** "Deploy the bd-shop-*.json workflows to bitdrift using bd CLI and verify they transition to LIVE status"

See [`workflows/README.md`](workflows/README.md) for deploy instructions.

---

## Reference & Guides

- **[README-refs.md](README-refs.md)** — Screens (18), emulator setup, local config, simulation modes, entity list, project structure
- **[INSTRUMENTATION_GUIDE.md](INSTRUMENTATION_GUIDE.md)** — Full walkthrough of all 13 steps with code examples and what each feature surfaces in the dashboard
- **[CLEANUP_GUIDE.md](CLEANUP_GUIDE.md)** — Reverse the instrumentation and return the app to baseline (remove all bitdrift SDK code)
- **[workflows/README.md](workflows/README.md)** — Deploy and monitor workflows using bd CLI

**Simulation features:** [ANR-A](README-refs.md#anr-a-guest-journey-testing) · [Force Quit](README-refs.md#force-quit-journey-testing) · [Crash Loop](README-refs.md#crash-loop) · [Slow Frames](README-refs.md#slow-frames-performance-bug-demo)

## Architecture

```
┌─────────────────────┐        HTTP (OkHttp)        ┌──────────────────────┐
│   Android Emulator   │ ◄─────────────────────────► │  FastAPI Server       │
│   (10.0.2.2:5173)    │    JSON request/response    │  (localhost:5173)     │
└─────────────────────┘                              └──────────────────────┘
```

See [project structure and requirements](README-refs.md#project-structure) for the full file tree and dependencies.
