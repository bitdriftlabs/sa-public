# bitdrift Instrumentation Guide

**Version 1.1** — adds Steps 18–20 (crash-reporter cross-linking, crash/CUJ workflows and dashboards, evaluation readout) and [worked examples](examples/).

A platform-neutral, step-by-step guide for instrumenting **any** mobile app with the bitdrift Capture SDK — **by prompting an AI coding agent**. Each step is a ready-to-use prompt. Steps 1–18 drive the **bd-instrumentation** skill to do the actual app-code work (write the call sites, wire the build, verify it compiles); Step 19 is server-side console configuration driven by **bd-issue-match**, **bd-cuj**, and **bd-cli**; Step 20 writes up the result and touches neither. You don't write the code; you run the prompts in order and the skills handle the platform-specific details on Android, iOS, or React Native.

Each step also lists the bitdrift feature it **unlocks** and the relevant **docs**, so you know what each prompt buys you.

The order is tuned for a proof-of-concept: stand up the SDK (1–3), then light up the timeline with the highest-value signals first — screen views, user identity, and network (4–6) — before layering on logs, performance, and operational features (7–18). This follows bitdrift's [Integration first steps](https://docs.bitdrift.io/product/first-steps). Steps **19–20** then turn that raw signal into the artifacts an evaluation is actually judged on: classified crash workflows, journey dashboards, and a criterion-by-criterion readout. Steps 4–18 are independent of each other, so run only the prompts you need, in any order that suits your app.

> **The prompts are platform-neutral.** Run the same prompt whether the target is Android, iOS, or React Native — the skill detects the platform and applies the right APIs. See [Platform notes](#platform-notes) at the bottom for per-platform specifics the skill handles for you.

> **Prefer to run this unattended?** This guide is the *human* reference — you read it and paste prompts in order. For a fully autonomous run (no human in the loop), use the companion **[AGENT_INSTRUMENTATION_GUIDE.md](AGENT_INSTRUMENTATION_GUIDE.md)** runbook, which adds a halt-on-failure preflight, a default for every decision point, and verification gates an agent can check by itself. Point your agent at that file and say *"execute this runbook."*

> **Mapping to your POC.** Every step below lists the **POC criteria** it satisfies using this guide's own generic legend: `SC-n` = a *Success Criteria & Use Cases* category, `PRE-n` = a *Required Pre-POC Engineering* category. These IDs are self-contained shorthand for this guide, not tied to any specific customer's POC scope document — the [POC coverage matrix](#poc-success-criteria-coverage) at the bottom defines every one and shows the step(s) that cover it. If you're working from your own POC scope document, map its rows to these IDs (they follow bitdrift's standard POC criteria categories: event tracking, network monitoring, crash detection, memory, debugging, session management, insights & visualization, log forwarding, session replay, visual performance, and customer support).

---

## Setup — install the skills first

These prompts assume your agent (Claude Code, Cursor, Codex, Copilot, or any skills-compatible agent) has bitdrift's skills installed:

- **bd-instrumentation** — installs and instruments the Capture SDK; detects the platform and whether the SDK is already present, then does a fresh install or extends an existing integration. This is the skill Steps 1–18 drive.
- **bd-docs** — fetches live bitdrift documentation at query time.
- **bd-cli** — drives the `bd` CLI for symbol/source-map uploads, workflows, keys, and dashboard composition.
- **bd-issue-match** — writes and deploys server-side crash-classification scripts (Ripsaw/BDRL). Drives the crash-workflow half of Step 19.
- **bd-cuj** — automates a full critical-user-journey stack (Sankey, funnel, SLO, alerting, session capture, dashboard) for one flow in a single pass. Drives the CUJ half of Step 19.

Install and authenticate the `bd` CLI (macOS, Homebrew):

```bash
brew tap bitdriftlabs/bd
brew install bd
bd auth   # browser login; for CI/automation use --api-key <key> or the BD_API_KEY env var
```

Then install the skills with [skills.sh](https://skills.sh/) (requires `node`/`npm`):

```bash
npx skills add bitdriftlabs/bd-skills
# update later with: npx skills update --all
```

The skills follow the [agentskills.io](https://agentskills.io/) open standard. See the [CLI Quickstart](https://docs.bitdrift.io/cli/quickstart) and [Agent Skills docs](https://docs.bitdrift.io/product/skills/overview).

If you have the cli and skills installed make sure to update them both before using them with `brew upgrade` and a reinstall of the skills. Additionally you should authenticate the CLI to your account with `bd auth` before beginning.

> **Tip:** you can run several steps at once — e.g. *"install the bitdrift Capture SDK in this app, then add screen tracking and network monitoring"* — and the skill sequences the work. The single-step prompts below are the reference for what's available.

---

## 1. Add the dependency

> **Prompt:** *"Install the bitdrift Capture SDK and build-tool plugin in this app."*

The skill adds the SDK dependency and the build plugin (which handles automatic network instrumentation and symbol/mapping uploads).

**Unlocks:** Everything. No other step works without this.

**POC criteria:** PRE-0 (current bitdrift SDK required) — the foundation every other criterion builds on.

**Docs:** [SDK Quickstart](https://docs.bitdrift.io/sdk/quickstart)

---

## 2. Start the Logger

> **Prompt:** *"Initialize the bitdrift logger at app startup, as early as possible in the launch path."*

The skill starts the logger with your SDK key and a session strategy (Step 3), before any other SDK call.

**Unlocks:** Instant Insights dashboards (app launches, crashes, network, resources), the session Timeline, and all automatic instrumentation (memory pressure, battery, orientation changes, slow frames, thermal state) — collected immediately after start.

**POC criteria:** SC-3 (Crash Detection — automatic crash capture with full session context), SC-4 (Memory Monitoring — continuous memory tracking), SC-6 (Session Management — log-everything-on-device), SC-10 (Visual Performance — slow-frame/jank & responsiveness capture). All four are automatic once the logger starts; no extra call sites needed.

**Docs:** [Configuration](https://docs.bitdrift.io/sdk/features/configuration), [Automatic Instrumentation](https://docs.bitdrift.io/sdk/features/automatic-instrumentation)

---

## 3. Confirm session strategy

> **Prompt:** *"Use a fixed session strategy for the bitdrift logger."* (or *"…switch to an activity-based session strategy with a 30-minute inactivity timeout."*)

A **fixed** strategy starts a fresh session on every launch — simplest to reason about, ideal for demos and verification. Choose **activity-based** if sessions should persist across process restarts and rotate only after inactivity.

**Unlocks:** Correct session grouping in Timeline.

**POC criteria:** SC-6 (Session Management — full session data available on-demand for a selected device).

**Docs:** [Session Management](https://docs.bitdrift.io/sdk/features/session-management)

---

## 4. Instrument screen views

> **Prompt:** *"Add bitdrift screen-view tracking for every screen, using a centralized navigation listener where the framework supports one."*

The skill logs a stable, snake_case screen name on each navigation (the label that becomes a Sankey node), preferring a centralized listener so both user and programmatic navigation are captured.

**Unlocks:** User Journey (Sankey) diagram in Instant Insights — the foundation for funnel analysis.

**POC criteria:** PRE-1 (Screen Names — app currently lacks them), SC-7 (Insights & Visualization — Sankey/journey dashboards).

**Docs:** [Automatic Instrumentation → Screen Views](https://docs.bitdrift.io/sdk/features/automatic-instrumentation)

---

## 5. Identify users with Entity ID

> **Prompt:** *"Set the bitdrift entity ID at the user identity boundary (e.g. on login)."*

The skill sets the entity ID when the user is known. The value is hashed; plaintext is never stored.

**Unlocks:** The Entities feature — search any entity by name to see all their sessions, crashes, devices, and last location; queue a recording with **Record Next Online**; bookmark entities to share with your team.

**POC criteria:** PRE-6 (Entities — `Logger.setEntityID`), SC-11 (Customer Support — pick any individual user to support/monitor), SC-5 (Debugging — retrieve a specific user's session via Record Next Online).

**Docs:** [Entity ID (SDK)](https://docs.bitdrift.io/sdk/features/entity-id), [Entities (product)](https://docs.bitdrift.io/product/entities)

---

## 6. Capture network traffic

> **Prompt:** *"Enable bitdrift network capture on every HTTP client in this app, and add path templates for any routes with dynamic segments."*

The skill attaches the network integration to each HTTP client and collapses high-cardinality paths.

**Unlocks:** Network tab in Instant Insights (p50/p95 latency, error rate, throughput by endpoint), and network events on the Timeline alongside logs and screen views.

> ⚠️ **High-cardinality paths are required, not optional.** When a path embeds a dynamic segment (user ID, product ID, UUID), every request becomes a distinct value. The dashboard groups metrics by path and enforces **cardinality limits** (~1,000 group-by dimensions / ~30 min, 20,000 total) — exceed them and metrics are **silently dropped**. The prompt above tells the skill to add a stable path template to every dynamic route.

**POC criteria:** SC-2 (Network Monitoring — unsampled HTTP latency/error-rate/throughput per endpoint), PRE-4 (Networking — wrap okhttp/URLSession; custom networking is handled in Step 10), SC-12 (Web views — if the app embeds WebViews, the same network integration extends to them, though WebView instrumentation is **experimental on both platforms**: Android via the Capture Gradle plugin, iOS as of SDK 0.23.11. The skill confirms the current API via bd-docs before enabling it, and will stop rather than guess if the docs don't cover it).

**Docs:** [HTTP Traffic Logs](https://docs.bitdrift.io/sdk/features/http-traffic-logs), [Workflow cardinality limits](https://docs.bitdrift.io/product/workflows/actions)

---

## 7. Emit structured custom logs

> **Prompt:** *"Add structured bitdrift logs for the key events in this app (e.g. checkout started, payment failed) — use a stable event name as the message and put variable data in fields."*

The skill emits logs with stable event-name messages and field-based variable data (never interpolated into the message), at the right level (info for business events, warning for degraded state, error for failures), capturing stack traces for caught exceptions.

**Unlocks:** Workflow matching, custom metrics (count, rate, histogram of any field), Timeline breadcrumbs, alert triggers.

**POC criteria:** SC-8 (Log Forwarding & Integration — synthetic logs/metrics from events), SC-7 (Insights & Visualization — custom-metric dashboards). For forwarding an *existing* logging framework see Step 14; for *analytics/beacon* events see Step 15.

**Docs:** [Custom Logs](https://docs.bitdrift.io/sdk/features/custom-logs)

---

## 8. Attach global fields

> **Prompt:** *"Attach bitdrift global fields for session-wide context (e.g. app variant, user tier), and set/remove them as that context changes."*

The skill adds fields that attach to every subsequent log, including a field provider for values that must survive a process restart.

> `user_id` is a special field: when set, it appears in the Timeline session header.

**Unlocks:** Dashboard filtering and slicing by any global field (e.g. isolate a release cohort by `app_variant`).

**POC criteria:** SC-7 (Insights & Visualization — slice dashboards by any dimension), SC-11 (Customer Support — `user_id` in the Timeline session header).

**Docs:** [Fields](https://docs.bitdrift.io/sdk/features/fields)

---

## 9. Report app launch TTI

> **Prompt:** *"Add bitdrift app-launch TTI reporting — capture process start early and report the time to first interactive frame."*

The skill captures the start timestamp in the launch path and reports the elapsed time once the first frame is drawn (once per logger start).

**Unlocks:** App Launch TTI chart in Instant Insights → UX (p50/p95/p99 across your population).

**POC criteria:** SC-1 (Event Tracking — unsampled p50/p90/p99, here for app launch), SC-7 (Insights & Visualization — UX dashboards).

**Docs:** [Automatic Instrumentation → TTI](https://docs.bitdrift.io/sdk/features/automatic-instrumentation)

---

## 10. Measure operations with custom spans

> **Prompt:** *"Wrap the key multi-step operations in this app (e.g. checkout, product discovery) in bitdrift spans, nesting child spans under a parent where it makes sense."*

The skill adds spans (each emits a start and end log with `_duration_ms`), nesting children under parents to form a Timeline waterfall, and uses the track-span wrapper for synchronous work.

**Unlocks:** Spans waterfall in the Timeline; query `_duration_ms` in Workflows to plot p50/p95 of any operation across your user base.

**POC criteria:** SC-1 (Event Tracking — precise p50/p90/p99 for 2–3 critical flows without sampling bias — *this is the primary step for SC-1*), PRE-4 (Networking — wrap **custom** networking that isn't okhttp/URLSession in spans).

**Docs:** [Spans (SDK)](https://docs.bitdrift.io/sdk/features/spans), [Spans Visualization](https://docs.bitdrift.io/product/timeline/spans-visualization)

---

## 11. Implement device identification for support

> **Prompt:** *"Add a bitdrift support affordance — surface a temporary device code / session URL in the app and a support-mode toggle that tags logs."*

The skill surfaces a short-lived device code or session URL and adds a toggle that attaches a `supportlog` field so support can filter to one device.

**Unlocks:** Support teams pull any user's session in real time without shipping debug builds. Works in production.

**POC criteria:** SC-5 (Debugging — ad-hoc/on-demand session capture for a user-reported issue), SC-11 (Customer Support — support any individual user).

**Docs:** [Device](https://docs.bitdrift.io/sdk/features/device)

---

## 12. Upload symbol files for readable crash stacks

> **Prompt:** *"Wire up bitdrift symbol/mapping upload for release builds."* (driven via **bd-cli**)

The skill configures the build plugin to upload mappings/symbols after a release build, or sets up a manual `bd debug-files …` upload.

> The API key used for uploads is your **SDK key** (Admin → SDK Keys), not a separate API key.

**Unlocks:** Human-readable stack traces in the Issues view.

**POC criteria:** SC-3 (Crash Detection — readable crash stacks alongside the full session timeline; pairs with the automatic crash capture from Step 2).

**Docs:** [Issues & Crashes → Uploading Debug Information Files](https://docs.bitdrift.io/sdk/features/fatal-issues)

---

## 13. New session on user logout or journey reset

> **Prompt:** *"Start a new bitdrift session on logout / journey reset, and re-apply the global fields afterward."*

The skill starts a new session at the right boundary and re-applies global fields (they're session-scoped and not carried across a new session).

**Unlocks:** Clean per-user Timeline entries.

**POC criteria:** SC-6 (Session Management — clean session boundaries so on-demand session retrieval maps to one user).

**Docs:** [Session Management](https://docs.bitdrift.io/sdk/features/session-management)

---

## 14. Forward your existing log framework

> **Prompt:** *"Forward this app's existing logging framework (e.g. Timber / CocoaLumberjack / console) into bitdrift."*

The skill bridges your existing logger into bitdrift so those logs land in the Timeline with no change to existing call sites. If the app already has rich logging, run this early.

**Unlocks:** All existing debug logs become searchable in Timeline and usable as Workflow match conditions.

**POC criteria:** PRE-3 (Logging — wrap existing Timber/SwiftyBeaver/CocoaLumberjack), SC-8 (Log Forwarding & Integration — capture existing logs without re-instrumenting call sites).

**Docs:** [Integrations](https://docs.bitdrift.io/sdk/integrations)

---

## 15. Forward analytics / beacon events

> **Prompt:** *"Forward this app's existing analytics/beacon events (e.g. Amplitude, a custom event client) into bitdrift at the single submission point, with the event name as the message and event properties as fields."*

The skill hooks the app's central analytics dispatch point and mirrors each event into bitdrift, so product/usage events land on the Timeline and feed Workflows — without touching every call site. This differs from Step 7 (new structured logs you author) and Step 14 (a logging framework like Timber): here you are bridging an existing **analytics** pipeline.

**Unlocks:** Product-usage analytics in bitdrift (funnels, event rates, behavior metrics) correlated with logs, network, and crashes in one Timeline.

**POC criteria:** PRE-2 (User analytics — forward "beacon" events that track user behavior/product usage), SC-8 (Log Forwarding & Integration), SC-7 (Insights & Visualization).

**Docs:** [Integrations](https://docs.bitdrift.io/sdk/integrations), [Custom Logs](https://docs.bitdrift.io/sdk/features/custom-logs)

---

## 16. Record feature flag exposures

> **Prompt:** *"Record bitdrift feature-flag exposures at the moment of divergence — when a flag value actually affects what the user sees or does."*

The skill records the variant a user is exposed to at the point the flag changes behavior (not at app start), so flag state can be correlated with crashes, performance, and journeys.

**Unlocks:** Slice any metric, crash, or funnel by feature-flag variant; spot regressions tied to a rollout.

**POC criteria:** PRE-5 (Feature flags — forward feature-flag exposures for product-feature visibility), SC-7 (Insights & Visualization).

**Docs:** [Fields](https://docs.bitdrift.io/sdk/features/fields) — confirm the exact feature-flag exposure API for your SDK version via **bd-docs** (search `feature flag exposure`).

---

## 17. Enable session replay (wireframe)

> **Prompt:** *"Enable bitdrift wireframe session replay on this build and confirm the configuration via bd-docs."*

The skill enables lightweight, wireframe-based replay (no screenshots or video) and verifies the per-platform configuration. Replay reconstructs the user experience while preserving device performance.

**Unlocks:** Wireframe session replay in the Timeline — reconstruct what the user saw and did during any captured session.

**POC criteria:** SC-9 (Session Replay — wireframe replay with sufficient fidelity for debugging at <1% CPU/memory impact).

> ⚠️ Session replay enablement and its exact configuration are version- and platform-specific. The skill confirms the current method via **bd-docs** (search `session replay`) before changing config rather than guessing.

**Docs:** [Session Replay](https://docs.bitdrift.io/product/timeline) — confirm via **bd-docs** (`session replay`).

---

## 18. Cross-link with your existing crash reporter

> **Prompt:** *"Cross-link this app's bitdrift sessions with our existing crash reporter (Crashlytics / Sentry / Bugsnag) by attaching the bitdrift session URL as a custom tag on every crash report."*

The skill reads the session URL (`Logger.sessionUrl` / `Logger.sessionURL` / `getSessionUrl()`) once the logger has started and attaches it to the incumbent crash tool as a custom key or tag, re-reading it whenever the session rotates.

**Unlocks:** Every crash in the existing tool links straight to its matching bitdrift session — full logs, network calls, spans, and device state. Lets bitdrift run alongside an incumbent crash tool during a POC instead of replacing it on day one.

**POC criteria:** SC-3 (Crash Detection — full session context alongside the current tool's reports).

**Docs:** [Fatal Issues](https://docs.bitdrift.io/sdk/features/fatal-issues), [Session Management](https://docs.bitdrift.io/sdk/features/session-management)

---

## 19. Turn crashes and journeys into workflows and dashboards

Every step above is app code, driven by **bd-instrumentation**. This step is different: it's **server-side console configuration**, driven by **bd-issue-match** (crash classification scripting) and **bd-cuj** (critical-user-journey automation), composed into dashboards with **bd-cli**. Run it once data is flowing — after at least Steps 1–10.

> **Prompt:** *"Deploy a bitdrift crash workflow that classifies crashes by [ANR reason / memory-pressure level at crash time / feature-flag exposure] using Issue/Crash Workflows (Ripsaw), then use bd-cuj to build a full critical-user-journey stack for our [checkout / onboarding / login] flow, and compose the results into POC dashboards."*

- **bd-issue-match** writes and deploys a Ripsaw/BDRL script that runs server-side against every crash Report (not on-device), turning raw crash payloads into standing charts — e.g. classify ANRs by blocked reason, tag OOM crashes with the memory-pressure level captured automatically since Step 2, or compute a feature-flag crash differential (does variant B crash more than control?).
- **bd-cuj** builds the full critical-user-journey stack for one flow in a single pass: a Sankey of the actual path taken, a funnel with step-by-step conversion, a completion-rate SLO alert, a key-step-duration alert, on-demand session capture for drop-offs, and a two-tab dashboard — instead of hand-assembling each piece from raw workflow primitives.
- **bd-cli** composes the resulting charts (from both of the above, plus Instant Insights) into 2–3 curated POC dashboards: a **Stability** dashboard (crash classification, ANR/OOM breakdown, crash-free % by version), a **Business/UX** dashboard (funnel, TTI, span percentiles, jank/slow-frame rate), and an **Entities/Support** dashboard (per-user profiles, Record Next Online).

**Before building a funnel, confirm the step names against what the app actually emits** — don't trust the names in a journey description. A matcher on a screen that is never logged deploys cleanly, reports LIVE, and charts nothing, which reads as a 0% conversion rate rather than a config error. Grep the source for the real values (`grep -rhoE 'screenName *= *"[^"]*"' --include=*.kt`) or read them off `bd tail`, then verify the *deployed* definition with `bd workflow describe <ID>`. Watch for two specific traps: a step that's really a category with several concrete screens behind it, and mutually exclusive branches listed as if they were sequential — both need an `or_matcher`. See [examples/cuj-funnel-pitfalls.md](examples/cuj-funnel-pitfalls.md).

**Unlocks:** This is the step that turns instrumented signals into the artifacts a customer actually looks at during an evaluation — crash workflows, CUJ dashboards, and curated POC dashboards — instead of raw Instant Insights and an unclassified Timeline.

**POC criteria:** SC-3 (Crash Detection — root-cause classification, not just raw reports), SC-7 (Insights & Visualization — 2–3 purpose-built dashboards, this is the primary step for SC-7's "build 2–3 dashboards" test plan), SC-11 (Customer Support — a dedicated Entities/Support dashboard).

**Worked examples:** [examples/crash-workflow-bdrl-examples.md](examples/crash-workflow-bdrl-examples.md) (two real BDRL classification scripts), [examples/cuj-funnel-pitfalls.md](examples/cuj-funnel-pitfalls.md) (how a funnel comes out silently empty).

**Docs:** the **bd-issue-match** and **bd-cuj** skills; [Workflows](https://docs.bitdrift.io/product/workflows/overview), [Ripsaw scripting](https://docs.bitdrift.io/product/workflows/scripting/overview), [Dashboards](https://docs.bitdrift.io/product/dashboards/overview)

---

## 20. Generate the evaluation readout

> **Prompt:** *"Map every in-scope POC criterion to a concrete bitdrift artifact — a chart, a workflow, a dashboard, or a captured session — and produce a readout a business stakeholder can review, with a portal link or screenshot proving each one."*

Walk the [POC coverage matrix](#poc-success-criteria-coverage) below (or your own POC scope document, mapped to these IDs) and for each in-scope criterion capture: which step/workflow/dashboard covers it, a `bd-cli` command or portal link that proves it, and a pass/fail note. Build this incrementally as steps complete rather than reconstructing it at the end.

State what was actually confirmed and how. A row that says "deployed" when nothing has flowed through it yet should say that — the honest gaps are what make the verified rows credible, and an all-green readout on day three invites the wrong kind of scrutiny.

**Unlocks:** A criterion-by-criterion, evidence-backed readout — the artifact that actually closes a POC evaluation, not just "the SDK is installed." This is the same deliverable a POC's evaluation-readout milestone calls for.

**POC criteria:** All in-scope criteria — this step is the cross-cutting proof layer, not a single capability.

**Worked example:** [examples/evaluation-readout-sample.md](examples/evaluation-readout-sample.md) — a real readout from this guide run against a demo app, including the criteria left deliberately open with reasons.

**Docs:** N/A — this step composes the outputs of Steps 1–19.

---

## Feature coverage summary

| Step | Prompt drives | bitdrift feature | POC criteria | Docs |
|------|---------------|-----------------|--------------|------|
| 1 | Install SDK + plugin | All features | PRE-0 | [Quickstart](https://docs.bitdrift.io/sdk/quickstart) |
| 2 | Start the logger | Instant Insights, Timeline, automatic events | SC-3, SC-4, SC-6, SC-10 | [Configuration](https://docs.bitdrift.io/sdk/features/configuration) |
| 3 | Session strategy | Correct session grouping | SC-6 | [Session Management](https://docs.bitdrift.io/sdk/features/session-management) |
| 4 | Screen-view tracking | User Journey Sankey diagram | PRE-1, SC-7 | [Automatic Instrumentation](https://docs.bitdrift.io/sdk/features/automatic-instrumentation) |
| 5 | Entity ID | Entities: per-user history, Record Next Online | PRE-6, SC-11, SC-5 | [Entity ID](https://docs.bitdrift.io/sdk/features/entity-id) |
| 6 | Network capture + path templates | Network tab, request/response correlation | SC-2, PRE-4 | [HTTP Traffic Logs](https://docs.bitdrift.io/sdk/features/http-traffic-logs) |
| 7 | Structured custom logs | Workflow matching, alerts, breadcrumbs | SC-8, SC-7 | [Custom Logs](https://docs.bitdrift.io/sdk/features/custom-logs) |
| 8 | Global fields | Dashboard filtering, session header user_id | SC-7, SC-11 | [Fields](https://docs.bitdrift.io/sdk/features/fields) |
| 9 | App launch TTI | TTI histogram in Instant Insights → UX | SC-1, SC-7 | [Automatic Instrumentation](https://docs.bitdrift.io/sdk/features/automatic-instrumentation) |
| 10 | Custom spans | Spans waterfall, duration histograms | SC-1, PRE-4 | [Spans](https://docs.bitdrift.io/sdk/features/spans) |
| 11 | Device identification | Support tooling, production device lookup | SC-5, SC-11 | [Device](https://docs.bitdrift.io/sdk/features/device) |
| 12 | Symbol/mapping upload | Readable crash stacks in Issues | SC-3 | [Issues & Crashes](https://docs.bitdrift.io/sdk/features/fatal-issues) |
| 13 | New session on reset | Clean per-user Timeline entries | SC-6 | [Session Management](https://docs.bitdrift.io/sdk/features/session-management) |
| 14 | Log framework forwarding | Existing logs visible in Timeline | PRE-3, SC-8 | [Integrations](https://docs.bitdrift.io/sdk/integrations) |
| 15 | Analytics / beacon forwarding | Product-usage events in Timeline | PRE-2, SC-8, SC-7 | [Integrations](https://docs.bitdrift.io/sdk/integrations) |
| 16 | Feature flag exposures | Slice metrics by flag variant | PRE-5, SC-7 | [Fields](https://docs.bitdrift.io/sdk/features/fields) |
| 17 | Session replay (wireframe) | Wireframe replay in Timeline | SC-9 | [Session Replay](https://docs.bitdrift.io/product/timeline) |
| 18 | Cross-link existing crash reporter | Session URL cross-tagged on incumbent tool's crashes | SC-3 | [Fatal Issues](https://docs.bitdrift.io/sdk/features/fatal-issues) |
| 19 | Crash workflows + CUJ + POC dashboards | Issue/Crash Workflows (Ripsaw), CUJ Sankey/funnel/SLO, curated dashboards | SC-3, SC-7, SC-11 | bd-issue-match, bd-cuj skills |
| 20 | Evaluation readout | Criterion-by-criterion, evidence-backed readout | All in-scope | — |

---

## POC success-criteria coverage

This guide's own `SC-n` / `PRE-n` legend — what each ID means and the step(s) that cover it — self-contained and not tied to any specific customer's POC scope document. Use this to confirm the instrumentation plan covers whatever POC scope you're working against before kickoff; if you have a signed POC scope doc, map its rows to the IDs below.

### Success Criteria & Use Cases

| POC ID | Category | Covered by step(s) | Notes |
|--------|----------|--------------------|-------|
| SC-1 | Event Tracking (p50/p90/p99 of key flows) | **10** (primary), 9 | Spans + synthetic metrics give unsampled percentiles; TTI covers launch |
| SC-2 | Network Monitoring | **6** | Unsampled per-endpoint latency/error/throughput |
| SC-3 | Crash Detection | **2** (automatic capture) + **12** (readable stacks) + **18** (cross-linked with existing tool) + **19** (root-cause classification via Issue/Crash Workflows) | Full session context is automatic; symbols make stacks human-readable; 18/19 add cross-tool linking and classification depth |
| SC-4 | Memory Monitoring | **2** | Automatic — no call sites; crash reports also carry the memory-pressure level at crash time (SDK 0.23.1+), no extra config |
| SC-5 | Debugging (ad-hoc capture) | **5**, **11** | Record Next Online + device/session lookup |
| SC-6 | Session Management | **2**, **3**, **13** | Log-everything-on-device, upload on demand |
| SC-7 | Insights & Visualization | **19** (primary — 2–3 curated dashboards) + 4, 7, 8, 9, 15, 16 | Steps 4–16 emit the signals; Step 19 is what actually builds the dashboards a customer looks at |
| SC-8 | Log Forwarding & Integration | **7**, **14**, **15** | New logs, framework bridge, analytics bridge |
| SC-9 | Session Replay | **17** | Wireframe replay |
| SC-10 | Visual Performance (jank/slowness) | **2** | Automatic JankStats / responsiveness |
| SC-11 | Customer Support | **5**, **11**, **8** (`user_id`), **19** (dedicated Entities/Support dashboard) | Entities + device support tooling, curated into its own dashboard |
| SC-12 | Web views | **6** | Experimental on both platforms — Android via the Capture Gradle plugin, iOS as of SDK 0.23.11. Confirm the current API via bd-docs before enabling, and treat as a POC risk rather than a settled capability |

### Required Pre-POC Engineering

| POC ID | Category | Covered by step(s) |
|--------|----------|--------------------|
| PRE-0 | SDK | **1** |
| PRE-1 | Screen Names | **4** |
| PRE-2 | User analytics (beacon events) | **15** |
| PRE-3 | Logging | **14** |
| PRE-4 | Networking (okhttp/URLSession + custom) | **6** (standard clients) + **10** (custom networking via spans) |
| PRE-5 | Feature flags | **16** |
| PRE-6 | Entities | **5** |

> **Every POC criterion above maps to at least one step**, including SC-12 (Web views) as of Step 6 — though WebView instrumentation is **experimental on both platforms**, so scope it as a POC risk rather than a settled capability, and confirm the current API via bd-docs before committing to it in a scope document.

---

## Turning signals into metrics and alerts (Workflows)

Some features need **Workflows** — server-side rules configured in the dashboard — to turn raw events into charts, alerts, and metrics. The SDK instrumentation above is the input; Workflows are the configuration. For a one-off metric or alert, drive it directly via **bd-cli**:

> **Prompt:** *"Create a bitdrift workflow that alerts when the `payment_failed` event rate exceeds a threshold."* — or — *"…a custom metric for the p95 of the `checkout` span duration."*

For the full crash-classification, CUJ, and dashboard treatment — the part of a POC that actually delights a customer — see **[Step 19](#19-turn-crashes-and-journeys-into-workflows-and-dashboards)**, which hands off to the **bd-issue-match** and **bd-cuj** skills.

**Automatic, no Workflow needed:** Instant Insights dashboards (crashes, network, memory, app launches); Session Timeline breadcrumbs; User Journey Sankey; TTI histogram; Spans waterfall; Entities view.

**Docs:** [Workflows](https://docs.bitdrift.io/product/workflows/overview), [Custom Metrics & Alerts](https://docs.bitdrift.io/product/workflows/actions)

---

## Tips for prompting the skill on a real app

- **Let the skill discover the app first.** A good opening prompt: *"Inspect this app and tell me where the bitdrift logger should start, which HTTP clients need instrumenting, and how navigation works — then propose an instrumentation plan."* The skill will find the launch entry point, every HTTP client, the navigation style, any existing logging framework, the SDK key location, and whether the SDK is already installed.
- **Run steps in dependency order.** Step 2 requires Step 1; Step 3 is part of the Step 2 call. After Steps 1–2 the rest are independent — ask only for what you need. Note Step 13 (new session) clears global fields, so the skill re-applies them; and Step 12 (symbols) only matters for release builds.
- **Ask the skill to verify.** End with *"compile the app and confirm the bitdrift instrumentation builds and data flows to the dashboard."* SDK calls are no-ops if the logger hasn't started, so a clean compile + launch is the first gate; then confirm sessions in Timeline, the Sankey from screen views, network events, TTI, and spans.
- **Keep it on stable APIs.** The skill avoids experimental, opt-in-required APIs by default. If a feature you want is only available experimentally, it will ask before opting in.
- **When in doubt, point it at the docs.** Ask the skill to confirm signatures via **bd-docs** for your installed SDK version rather than guessing.

---

## Platform notes

The prompts above are identical across platforms — the skill applies the right APIs. A few specifics it handles for you:

**iOS (Swift):** install via SPM (`bitdriftlabs/capture-ios`) or CocoaPods (`pod 'BitdriftCapture'`, `import Capture`); start in the SwiftUI `@main App` `init()` or UIKit `didFinishLaunchingWithOptions`; integrations (network, log forwarding) are **chained on the start call**, not wired per-client; entity ID is `setEntityID` (capital **ID**); symbols are **dSYMs**, not ProGuard; the SDK is added only to targets that start the logger (avoids duplicate-symbol warnings). Path templates apply on iOS too.

**React Native (TypeScript):** install `@bitdrift/react-native` then `pod install` (iOS); Android autolinks — so crash symbolication needs **both** JS source maps (Hermes) and native symbols. Start with `init(...)` in `App.tsx`/`index.js`; screen views hook into React Navigation `onStateChange` or Expo Router `usePathname()`. Network capture **isn't guaranteed automatic** — the skill wraps `fetch`/adds an interceptor where needed. JS error reporting currently requires the **New Architecture + Hermes** engine. Functions are top-level named exports (`init`, `info`, `addField`, …).

For authoritative, per-step platform detail, the bd-instrumentation skill ships `references/ios.md` and `references/react-native.md`, and confirms live signatures via **bd-docs**.
