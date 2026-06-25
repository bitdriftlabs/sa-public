# bitdrift Instrumentation Guide

A platform-neutral, step-by-step checklist for wiring up the bitdrift Capture SDK in **any** mobile app. Each step lights up a specific product feature. Follow them in order — later steps build on earlier ones.

This guide is the **conceptual reference** — what each step does, what it unlocks, and how the steps relate. It deliberately contains no code: the actual call sites are written and verified for you by the **bd-instrumentation** agent skill, which adapts to your platform and codebase. Use this document to decide *what* to instrument and *why*; let the skill handle *how*.

The order is tuned for a proof-of-concept: stand up the SDK (1–3), then light up the timeline with the highest-value signals first — screen views, user identity, and network (4–6) — before layering on logs, performance, and operational features. This follows bitdrift's [Integration first steps](https://docs.bitdrift.io/product/first-steps). The categories are independent, so reorder them to fit your app.

The concepts, ordering, and product features are the same on **Android**, **iOS**, and **React Native** — only the call sites differ. See [Platform API maps](#platform-api-maps) at the bottom for the per-platform surface.

---

## Using this guide with bd skills

This guide is designed to be used alongside **bitdrift's agent skills**, which give an AI coding agent the operational logic to carry out — and verify — the steps below:

- **bd-instrumentation** — installs and instruments the Capture SDK on Android, iOS, and React Native. It detects the platform and whether the SDK is already present, then performs a fresh install or extends an existing integration. This document is the human-readable companion to that skill.
- **bd-docs** — fetches live bitdrift documentation at query time (the `$bd-docs` references throughout this guide point to it).
- **bd-cli** — drives the `bd` CLI for symbol/source-map uploads, workflows, session/issue queries, and key management.

The skills drive the **`bd` CLI** (also used for the symbol/source-map uploads in Step 12). Install and authenticate it first (macOS, Homebrew):

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

> **How to use it:** ask your agent to do the work — e.g. *"install the bitdrift Capture SDK in this app and add screen tracking and network monitoring"* — and it will follow `bd-instrumentation`. Use this guide as the reference for what each step unlocks.

---

## 1. Add the dependency

Add the Capture SDK and the build-tool plugin to your project. The plugin handles automatic network instrumentation and symbol/mapping uploads.

**Docs:** [SDK Quickstart](https://docs.bitdrift.io/sdk/quickstart)

**Unlocks:** Everything. No other step works without this.

---

## 2. Start the Logger

Start the logger as early as possible in the app's launch path — before any other SDK call, before registering lifecycle callbacks, before logging anything. It takes your SDK key and a session strategy (Step 3).

**Docs:** [Configuration](https://docs.bitdrift.io/sdk/features/configuration), [Automatic Instrumentation](https://docs.bitdrift.io/sdk/features/automatic-instrumentation)

**Unlocks:** Instant Insights dashboards (app launches, crashes, network, resources), session timeline, and all automatic instrumentation (memory pressure, battery, orientation changes, slow frames, thermal state). The SDK begins collecting device telemetry immediately after start.

---

## 3. Confirm session strategy

The session strategy is a required parameter of the start call above. Default to a **fixed** strategy — it begins a fresh session on every process launch, which is the simplest to reason about and ideal for demos and verification.

Optionally switch to an **activity-based** strategy if you need sessions to persist across process restarts and rotate only after a period of inactivity (default 30 minutes, configurable) — useful for user-facing flows where one journey may span a backgrounded app.

**Docs:** [Session Management](https://docs.bitdrift.io/sdk/features/session-management)

**Unlocks:** Correct session grouping in Timeline.

---

## 4. Instrument screen views

Log a screen-view event every time the user navigates to a new screen, using a stable, snake_case name — it becomes the node label in the Sankey diagram.

Prefer a **centralized navigation listener** where the framework offers one (e.g. a Compose `NavController` listener, a React Navigation state listener) — it fires once per navigation for both user-driven and programmatic navigation, independent of view-rendering timing. For simpler apps, emit the event per screen as it appears; for Activities/Fragments, emit on resume.

**Docs:** [Automatic Instrumentation → Screen Views](https://docs.bitdrift.io/sdk/features/automatic-instrumentation)

**Unlocks:** User Journey (Sankey) diagram in Instant Insights. This is the foundation for funnel analysis.

---

## 5. Identify users with Entity ID

Set the entity ID whenever you know who the user is — on login, at session start, or when an anonymous ID is established. The value is hashed; the plaintext is never stored. Set it at the real identity boundary, not at startup with a placeholder.

**Docs:** [Entity ID (SDK)](https://docs.bitdrift.io/sdk/features/entity-id), [Entities (product)](https://docs.bitdrift.io/product/entities)

**Unlocks:** The Entities feature — search any entity by name to see all their sessions, crashes, devices, and last location; queue a session recording with **Record Next Online**; bookmark entities to share with your team.

---

## 6. Capture network traffic

The single highest-value instrumentation after starting the logger, and near-automatic. Attach the SDK's network integration to your HTTP stack and every request/response is logged with timing breakdowns (DNS, TLS, TTFB, total), status codes, and sizes. If you have multiple HTTP clients, instrument each one. For HTTP stacks the integration doesn't cover, fall back to the manual HTTP logging API ($bd-docs).

**Docs:** [HTTP Traffic Logs](https://docs.bitdrift.io/sdk/features/http-traffic-logs)

**Unlocks:** Network tab in Instant Insights (p50/p95 latency, error rate, throughput by endpoint), and network events on the session Timeline alongside custom logs and screen views.

### ⚠️ Collapse high-cardinality paths — do not skip this

When a URL path embeds a dynamic segment — user ID, product ID, session token, UUID — every request becomes a *distinct* path value. The dashboard groups network metrics by path, and bitdrift enforces **cardinality limits**: once a metric exceeds ~1,000 group-by dimensions per ~30 minutes (or 20,000 total across platform/app/version), metrics are **silently dropped** and the chart breaks. Unbounded paths are the most common way to hit this, so this is required, not optional.

Collapse dynamic segments into a stable template (via the `x-capture-path-template` request header, or the platform's path-template API) so `/api/products/abc123` and `/api/products/xyz789` both report as one endpoint. If no template is provided the SDK attempts auto-detection, but explicit templates are far more reliable — **set one on every route that contains a dynamic segment.**

**Docs:** [HTTP Traffic Logs → path template](https://docs.bitdrift.io/sdk/features/http-traffic-logs), [Workflow cardinality limits](https://docs.bitdrift.io/product/workflows/actions)

---

## 7. Emit structured custom logs

Use a **stable event name as the log message** and put **all variable data in fields**. This enables exact matching in Workflow conditions without regex. Never interpolate variable values into the message — it breaks field matching. Pass a caught error/exception to the log call to capture its stack trace automatically.

**Log level guidance:**

| Level | When to use |
|-------|-------------|
| trace / debug | Development-only noise; filtered out in production by default |
| info | Business events: user actions, state transitions, milestones |
| warning | Degraded state: retry, memory pressure, slow response |
| error | Failures: payment failed, API error, flow abandoned |

**Docs:** [Custom Logs](https://docs.bitdrift.io/sdk/features/custom-logs)

**Unlocks:** Workflow matching, custom metrics (count, rate, histogram of any field value), Timeline breadcrumbs, alert triggers.

---

## 8. Attach global fields

Global fields attach to every log emitted after they're set. Use them for context that's true for the duration of a session or lifecycle state — app variant, user tier, build channel. Add them when the context becomes known (e.g. user ID on sign-in) and remove them when it ends (sign-out). For fields that must survive a process restart or come from outside the SDK, use a field provider that's read on every log.

> `user_id` is a special field name: when present, it appears in the Timeline session header.

**Docs:** [Fields](https://docs.bitdrift.io/sdk/features/fields)

**Unlocks:** Dashboard filtering and slicing by any global field (e.g. isolate a release cohort by `app_variant`).

---

## 9. Report app launch TTI

Record the time from process start to first interactive frame: capture a timestamp as early as possible in the launch path, then report the elapsed duration once the first frame is drawn. Report it once — only the first report per logger start takes effect.

**Docs:** [Automatic Instrumentation → TTI](https://docs.bitdrift.io/sdk/features/automatic-instrumentation)

**Unlocks:** App Launch TTI chart in Instant Insights → UX (p50/p95/p99 across your population).

---

## 10. Measure operations with custom spans

Spans measure the duration of any multi-step operation; each span emits a start and an end log, with a `_duration_ms` field on the end log. Nested spans link a child to its parent to form a waterfall hierarchy in the Timeline. Ending a span is idempotent, so it's safe to end at multiple exit points. For synchronous work, a track-span convenience wrapper ends the span automatically on success or failure.

**Docs:** [Spans (SDK)](https://docs.bitdrift.io/sdk/features/spans), [Spans Visualization](https://docs.bitdrift.io/product/timeline/spans-visualization)

**Unlocks:** Spans waterfall in the Timeline; query `_duration_ms` in Workflows to plot p50/p95 of any operation across your user base.

---

## 11. Implement device identification for support

Surface a short-lived device code or the session URL inside the app so support agents can pull the exact session from the dashboard without device logs or a repro. A "Support Mode" toggle that attaches a `supportlog` field to every log lets support filter the dashboard to a specific device.

**Docs:** [Device](https://docs.bitdrift.io/sdk/features/device)

**Unlocks:** Support teams pull any user's session in real time without shipping debug builds. Works in production.

---

## 12. Upload symbol files for readable crash stacks

Release builds obfuscate or strip symbols, so crash stacks are unreadable until you upload the mapping/symbol files. The build-tool plugin from Step 1 can do this automatically after a release build; you can also upload manually with the `bd` CLI (`bd debug-files …`). This is driven by **bd-cli** — ask the agent, or see the docs.

> The API key used for uploads is your **SDK key** (Admin → SDK Keys), not a separate API key.

**Docs:** [Issues & Crashes → Uploading Debug Information Files](https://docs.bitdrift.io/sdk/features/fatal-issues)

**Unlocks:** Human-readable stack traces in the Issues view.

---

## 13. New session on user logout or journey reset

Start a new session whenever context changes enough that a new Timeline entry makes sense — user logout, journey restart, or a distinct flow boundary. Global fields are session-scoped and are **not** carried across a new session, so re-apply the ones you need immediately after starting it.

**Docs:** [Session Management](https://docs.bitdrift.io/sdk/features/session-management)

**Unlocks:** Clean per-user Timeline entries.

---

## 14. Forward your existing log framework

If the app already uses a logging framework (Timber, Log4j, CocoaLumberjack, SwiftyBeaver, `console.*`, etc.), forward those logs to bitdrift so they appear in the Timeline alongside your structured events. If you already have rich logging, do this early — it lights up the Timeline with zero new instrumentation.

**Docs:** [Integrations](https://docs.bitdrift.io/sdk/integrations)

**Unlocks:** All existing debug logs become searchable in Timeline and usable as Workflow match conditions — without changing any existing call sites.

---

## Feature coverage summary

| Step | Instrumentation | bitdrift feature | Docs |
|------|-----------------|-----------------|------|
| 1 | SDK dependency + plugin | All features | [Quickstart](https://docs.bitdrift.io/sdk/quickstart) |
| 2 | Start the logger | Instant Insights, Timeline, automatic events | [Configuration](https://docs.bitdrift.io/sdk/features/configuration) |
| 3 | Session strategy | Correct session grouping | [Session Management](https://docs.bitdrift.io/sdk/features/session-management) |
| 4 | Screen-view logging | User Journey Sankey diagram | [Automatic Instrumentation](https://docs.bitdrift.io/sdk/features/automatic-instrumentation) |
| 5 | Entity ID | Entities: per-user history, Record Next Online | [Entity ID](https://docs.bitdrift.io/sdk/features/entity-id) |
| 6 | Network capture | Network tab, request/response correlation | [HTTP Traffic Logs](https://docs.bitdrift.io/sdk/features/http-traffic-logs) |
| 7 | Structured custom logs | Workflow matching, alerts, breadcrumbs | [Custom Logs](https://docs.bitdrift.io/sdk/features/custom-logs) |
| 8 | Global fields | Dashboard filtering, session header user_id | [Fields](https://docs.bitdrift.io/sdk/features/fields) |
| 9 | App launch TTI | TTI histogram in Instant Insights → UX | [Automatic Instrumentation](https://docs.bitdrift.io/sdk/features/automatic-instrumentation) |
| 10 | Custom spans | Spans waterfall, duration histograms | [Spans](https://docs.bitdrift.io/sdk/features/spans) |
| 11 | Device identification | Support tooling, production device lookup | [Device](https://docs.bitdrift.io/sdk/features/device) |
| 12 | Symbol/mapping upload | Readable crash stacks in Issues | [Issues & Crashes](https://docs.bitdrift.io/sdk/features/fatal-issues) |
| 13 | New session on reset | Clean per-user Timeline entries | [Session Management](https://docs.bitdrift.io/sdk/features/session-management) |
| 14 | Log framework forwarding | Existing logs visible in Timeline | [Integrations](https://docs.bitdrift.io/sdk/integrations) |

---

## Turning signals into metrics and alerts (Workflows)

Some features require **Workflows** — server-side rules configured in the dashboard — to turn raw events into charts, alerts, and metrics. The SDK instrumentation is the input; Workflows are the dashboard configuration.

**Automatic, no Workflow needed:** Instant Insights dashboards (crashes, network, memory, app launches) from starting the logger; Session Timeline breadcrumbs; User Journey Sankey from screen views; TTI histogram; Spans waterfall; Entities view.

**Build Workflows for custom metrics and alerts** — match on your stable event names (Step 7) and span names (Step 10):

| What to measure | Match condition | Action |
|----------------|-----------------|--------|
| Event rate | message equals your event name | Custom metric: count, rate |
| Error alerting | error event name AND rate > threshold | Alert → Slack / PagerDuty |
| Operation p95 | span name AND span-type "end" | Custom metric: histogram of `_duration_ms` |
| Cohort comparison | event name, grouped by a global field | Custom metric: rate per cohort |

**Docs:** [Workflows](https://docs.bitdrift.io/product/workflows/overview), [Custom Metrics & Alerts](https://docs.bitdrift.io/product/workflows/actions)

---

## Additional context for agents

This section is for an AI agent applying this guide to a real app. The numbered steps above describe *what* to instrument; the notes below cover what to discover, decide, and verify when instrumenting an arbitrary codebase. The **bd-instrumentation** skill carries the actual platform-specific code.

### Before you start — discover the target app

| Look for | Why it matters |
|----------|----------------|
| The app's launch entry point (Application subclass on Android, `@main`/`AppDelegate` on iOS, `App.tsx`/`index.js` on RN) | Where the logger starts, global fields are set, and the TTI start timestamp is captured. |
| Every HTTP client (OkHttp/Retrofit, URLSession/Alamofire, `fetch`/XHR) | Each needs the network integration. Miss one and that traffic is invisible. |
| Navigation style (Compose vs Activities/Fragments; React Navigation vs Expo Router) | Decides how screen views are emitted. |
| Existing logging framework | If present, do Step 14 early. |
| The SDK key (build config, secrets, CI) | Needed to start the logger and for symbol upload. Never hardcode it. |
| Whether the SDK is already a dependency | If installed, skip Steps 1–2 and jump to the category requested. |

### Step dependencies (most steps are independent)

After Steps 1–2 the categories are standalone — apply only the ones needed, in any order. The real couplings:

- **2 requires 1.** **3 is a parameter of the start call in 2** — don't add a second call.
- **13 invalidates 8.** Re-apply global fields immediately after every new session.
- **12 requires the build-tool plugin from 1** and a release build; no effect in debug.
- **9 (TTI):** only the first report per logger start takes effect; do it once.

### Stay on stable APIs

Use only stable SDK surface. Avoid experimental, opt-in-required APIs — they can change between releases. None of the steps above depend on one; if a feature is only available experimentally, confirm with the user before opting in.

### Verify your work

1. **Compile** after each category. SDK calls are non-throwing no-ops if the logger hasn't started, so a clean compile + app launch is the first gate.
2. **Confirm data flow** in the dashboard: sessions in Timeline (Step 2), Sankey from screen views (Step 4), network events on Timeline (Step 6), TTI in Instant Insights → UX (Step 9), spans in the waterfall (Step 10).
3. **Validation checklist:** SDK present & current · logger started early · session strategy set · network monitoring on every client · screen tracking on every screen · TTI tracked once · identity fields set after login · global fields re-applied after a new session · symbol/mapping upload wired for release.

### Looking things up

For live API signatures, field names, and enum values, use the **$bd-docs** skill rather than guessing. The SDK evolves; confirm against the docs for the project's SDK version before changing call sites.

---

## Platform API maps

The concepts and ordering above are identical across platforms; only the call sites and a few API shapes differ. The **bd-instrumentation** skill applies these automatically — the maps below are a quick orientation, with authoritative per-step detail in the skill's `references/ios.md` and `references/react-native.md`, confirmed via **$bd-docs**.

### iOS (Swift)

| Concept (step) | Android | iOS (Swift) |
|----------------|---------|-------------|
| Install (1) | `io.bitdrift:capture` + Gradle plugin | SPM `bitdriftlabs/capture-ios` or CocoaPods `pod 'BitdriftCapture'`; `import Capture` (module is `Capture`) |
| Start (2) | in `Application.onCreate()` | SwiftUI `@main App` `init()`; UIKit `application(_:didFinishLaunchingWithOptions:)` |
| Session strategy (3) | `.Fixed()` / `.ActivityBased(...)` | `.fixed()` / `.activityBased(...)` |
| Screen views (4) | Compose nav listener | SwiftUI `.onAppear`; UIKit `viewDidAppear(_:)` |
| Entity ID (5) | `setEntityId(id)` | `setEntityID(id)` — capital **ID** |
| Network (6) | per-client `CaptureOkHttpEventListenerFactory` | `.enableIntegrations([.urlSession()])` on start — swizzles all `URLSession` (covers Alamofire) |
| Custom logs (7) | message in trailing closure | message positional, `fields:` labeled |
| Symbols (12) | ProGuard mapping | **dSYMs** (not ProGuard) |
| Log forwarding (14) | Timber tree | `.enableIntegrations([.cocoaLumberjack()/.swiftyBeaver()])` on start |

iOS gotchas:

- **Integrations are chained on start** — network and log forwarding are enabled on the start call's return value, not per-client.
- **Initialize at launch** (SwiftUI `@main init()`, UIKit `didFinishLaunchingWithOptions`) so the SDK observes launch system events.
- **Don't embed the SDK twice** — add it only to targets that start the logger; adding it to a shared framework the app also imports causes duplicate ObjC class symbol warnings.
- **High-cardinality paths matter on iOS too** — set a path template (header or the URL-path template API).

### React Native (TypeScript)

| Concept (step) | Android | React Native |
|----------------|---------|--------------|
| Install (1) | `io.bitdrift:capture` + Gradle plugin | `npm install @bitdrift/react-native`, then `pod install` (iOS); Android autolinks |
| Start (2) | in `Application.onCreate()` | `init(...)` in `App.tsx`/`index.js`, before the app renders |
| Session strategy (3) | `SessionStrategy.Fixed()` | `SessionStrategy.Fixed` (a value, not a call) |
| Screen views (4) | Compose nav listener | React Navigation `onStateChange`, or Expo Router `usePathname()` |
| Network (6) | per-client factory | No guaranteed auto-capture — wrap `fetch` / add an interceptor via the manual HTTP logging API ($bd-docs) |
| Custom logs (7) | `Logger.logInfo {…}` | top-level `info()` / `warning()` / `error()` |
| Symbols (12) | ProGuard mapping | **Hermes source maps**; native crashes still need dSYM (iOS) / ProGuard (Android) |
| Log forwarding (14) | Timber tree | wrap `console.log/warn/error`, or add a `react-native-logs` transport |

React Native gotchas:

- **Two install layers** — the JS package plus native pods/Gradle. Crash symbolication needs **both** JS source maps and native symbols.
- **JS error reporting** is currently limited to builds on the **New Architecture + Hermes** engine — verify before relying on JS crash capture.
- **Network capture isn't guaranteed automatic** — confirm in $bd-docs whether `fetch`/XHR is auto-instrumented; otherwise wrap it. Step 6 cardinality rules still apply.
- Functions are **top-level named exports** (`init`, `info`, `addField`, …), not methods on a `Logger` object.
