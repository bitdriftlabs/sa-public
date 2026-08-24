# Agent Instrumentation Runbook

**Version 1.3 — machine-consumable** — covers the 20-step guide, including the Step 4/10 span pairing and the SDK 0.23.12 review (session replay on by default, init diagnostics, entity-ID clearing, trace-propagation defaults).

This is the **autonomous execution contract** for instrumenting any mobile app with the
bitdrift Capture SDK. It wraps [INSTRUMENTATION_GUIDE.md](INSTRUMENTATION_GUIDE.md) (the
human reference) with everything an agent needs to run **unattended**: a preflight that
halts on missing preconditions, a default value for every human decision point, a strict
execution order, and verification gates phrased as checkable assertions.

> **POC alignment.** Steps map to this guide's own generic `SC-n` (Success Criteria) /
> `PRE-n` (Required Pre-POC Engineering) legend — self-contained shorthand, not tied to any
> specific customer's POC scope document. The execution table in §2 lists the criteria each
> step satisfies; the human guide's
> [POC coverage matrix](INSTRUMENTATION_GUIDE.md#poc-success-criteria-coverage) is the
> authoritative legend and cross-walk. If the run is scoped to a customer's own signed POC
> scope document, map that document's criteria to these IDs before starting, and instrument
> exactly the steps whose criteria are in scope.

> **You are the agent.** Read this file top to bottom, then execute. Do not ask the user
> for input unless a step's decision rule explicitly says `ASK`. Stop immediately on any
> `HALT` condition and report which gate failed.

---

## 0. Preflight — run first, HALT on any failure

Check every precondition before touching the codebase. If any check fails, stop and report
the exact failing check; do not proceed or attempt repairs unless noted.

| # | Check | How to verify | On failure |
|---|-------|---------------|------------|
| P1 | `bd` CLI installed | `bd --version` exits 0 | HALT: instruct user to `brew tap bitdriftlabs/bd && brew install bd` |
| P2 | `bd` authenticated | `bd auth status` (or first authed command) succeeds | HALT: instruct user to run `bd auth`, or set `BD_API_KEY` for CI |
| P3 | Skills installed | `bd-instrumentation`, `bd-docs`, `bd-cli` resolvable. **Also `bd-cuj` whenever Step 19 is in scope — which the no-scope default in §1 always includes**, so treat it as mandatory unless Step 19 was explicitly excluded. There are exactly four bitdrift skills; crash classification lives in **bd-cli**'s IssueMatch recipes, not a separate skill | HALT: `npx skills add bitdriftlabs/bd-skills` |
| P4 | Skills/CLI current | (best-effort) `brew upgrade` + `npx skills update --all` | WARN only; continue |
| P5 | Target platform detected | bd-instrumentation reports android / ios / react-native | HALT if undetectable |
| P6 | SDK key available | locate key (Admin → SDK Keys) in env, config, or user-provided | If absent → `ASK` user once for the SDK key; HALT if not supplied |
| P7 | Clean working tree | `git status --porcelain` is empty (or user accepts dirty) | WARN; continue (so changes are reviewable in a clean diff) |
| P8 | Baseline build passes | platform build succeeds **before** any change | HALT: a red baseline makes later gates meaningless |

Record platform from P5 — it selects the verification commands in §3 and the platform notes
in the human guide.

---

## 1. Decision defaults — resolve without the user

Every human judgment call in the source guide has a default below. Apply the default
silently unless the user has already stated a preference this session. Only the rows marked
`ASK` require a prompt.

| Decision | Source step | Default (use unless told otherwise) |
|----------|-------------|-------------------------------------|
| Init diagnostics | 2 | **On.** Pass the `startResult` callback (SDK 0.23.0+) and log its outcome; check `getSdkStatus()` after start. Cheap, and it turns a silent bad-key/blocked-egress failure into an explicit one at the call site rather than an empty dashboard at V4. |
| Session strategy | 3 | **fixed** (fresh session per launch — best for PoC/verification) |
| Which events to log | 7 | Discover candidate business events by scanning the code (checkout, payment, auth, errors). Instrument the **top 3–5 highest-signal** events; list them in the run report. Do **not** ASK. |
| Cold-start span waterfall | 9 | **On.** Root `app_cold_start` back-dated to real process start, with `sdk_init` / `scene_render` / `state_restore` children. In addition to the TTI report, not instead of it. |
| Which operations to span | 10 | Span **every** journey element: one `<screen>_screen_load` per screen instrumented in Step 4, plus one `journey.<phase>` per phase of the flow chosen for Step 19, nested via explicit parent span IDs. Add app-specific hot paths (custom networking, heavy compute, per-row loads). Do **not** ASK, and do **not** narrow this to one flow. |
| Support affordance | 11 | **Skip by default** — it adds UI. Include only if user asked for support tooling. `ASK` only if the run scope explicitly mentions support. |
| Symbol/mapping upload | 12 | Configure for release builds **only**; no-op for debug-only runs. |
| Log-framework forwarding | 14 | Enable **if** an existing logger (Timber/CocoaLumberjack/console) is detected; otherwise skip. |
| Analytics/beacon forwarding | 15 | Enable **if** an existing analytics/event client (Amplitude, custom dispatcher) is detected; otherwise skip. |
| Feature flag exposures | 16 | Enable **if** a feature-flag system is detected; instrument at the divergence point. Otherwise skip. Confirm API via bd-docs. |
| Session replay | 17 | **Already on** — the default `Configuration` enables it on both platforms, so "skipping" Step 17 still ships replay. Default action: leave enabled, and **record in the run report that it is on**. Disable (pass a null/nil session-replay configuration) only if the user or POC scope asks, or a privacy review is unresolved — that case is an `ASK`. |
| Crash reporter cross-linking | 18 | Enable **if** an existing crash reporter (Crashlytics/Sentry/Bugsnag/etc.) is detected in the codebase; otherwise skip. |
| Crash workflow classification dimensions | 19 | Auto-discover from what the app actually produces — classify by feature-flag exposure if flags are instrumented, by memory-pressure level for OOM-type crashes, by ANR/blocked-thread reason for ANR-type crashes. Do **not** ASK; pick whichever dimensions the crash catalog supports. |
| CUJ flow to automate | 19 | `ASK` once — bd-cuj needs to know which flow is business-critical (e.g. checkout, onboarding, login). Skip this half of Step 19 only if told to stop at raw instrumentation. |
| POC dashboards to build | 19 | Build the 3 default dashboards (Stability, Business/UX, Entities/Support) unless the scope says otherwise. |
| Evaluation readout | 20 | Run whenever a POC scope was provided (map to its criteria). If no scope was given, run it anyway as a generic step-coverage summary rather than skipping. |
| Scope (which steps) | all | If a **POC scope** is provided → instrument exactly the steps whose POC criteria are in scope (see §2 column). If **no scope** given → run the **PoC core: steps 1–10**, plus 14/15/16 where the relevant framework is auto-detected, plus **19** (crash workflows/CUJ/dashboards — the highest-visibility output) and **20** (readout). Steps 11, 12, 13, 17, 18 only on request or when their criterion is in the POC scope. |

---

## 2. Execution order — sequential, gate after each

Dispatch by step: **Steps 1–18** run through the **bd-instrumentation** skill using the prompt
from the source guide (linked); **Step 19** is server-side and runs through **bd-cli** (IssueMatch
recipes for crash classification, plus dashboard composition) and **bd-cuj**; **Step 20** is document generation and uses no skill. After every
step, run its gate. **HALT on a failed gate** — do not continue to the next step on a broken
build.

| Order | Step | POC criteria | Prompt source | Gate (must pass before next step) |
|-------|------|--------------|---------------|-----------------------------------|
| 1 | Add dependency + plugin | PRE-0 | [Step 1](INSTRUMENTATION_GUIDE.md#1-add-the-dependency) | Dependency resolves; project builds |
| 2 | Start logger | SC-3, SC-4, SC-6, SC-9, SC-10 | [Step 2](INSTRUMENTATION_GUIDE.md#2-start-the-logger) | Builds; logger-start call present in launch path; `startResult` wired and `getSdkStatus()` reports `Running` |
| 3 | Session strategy (= default *fixed*) | SC-6 | [Step 3](INSTRUMENTATION_GUIDE.md#3-confirm-session-strategy) | Strategy set on the start call |
| 4 | Screen views (+ screen-name inventory) | PRE-1, SC-7 | [Step 4](INSTRUMENTATION_GUIDE.md#4-instrument-screen-views-and-pair-them-with-load-spans) | Builds; navigation listener wired; **the full list of emitted screen names is captured and recorded in the run report** — it is the input to Step 10 and to Step 19's funnel matchers |
| 5 | Entity ID | PRE-6, SC-11, SC-5 | [Step 5](INSTRUMENTATION_GUIDE.md#5-identify-users-with-entity-id) | Builds; `setEntityId`/`setEntityID` at the identity boundary (not the removed `registerOpaqueEntityId`), and `clearEntityId`/`clearEntityID` on logout if a logout path exists |
| 6 | Network capture + path templates | SC-2, PRE-4 | [Step 6](INSTRUMENTATION_GUIDE.md#6-capture-network-traffic) | Builds; **every** dynamic route has a path template (cardinality gate — see ⚠️ below); exactly one OkHttp instrumentation path on Android (plugin **or** manual, never both); trace-propagation default surfaced to the user (see ⚠️ below) |
| 7 | Structured custom logs | SC-8, SC-7 | [Step 7](INSTRUMENTATION_GUIDE.md#7-emit-structured-custom-logs) | Builds; messages are stable names, variable data in fields |
| 8 | Global fields | SC-7, SC-11 | [Step 8](INSTRUMENTATION_GUIDE.md#8-attach-global-fields) | Builds |
| 9 | App launch TTI + cold-start waterfall | SC-1, SC-7 | [Step 9](INSTRUMENTATION_GUIDE.md#9-report-app-launch-tti--cold-start-span-waterfall) | Builds; TTI reported; root + 3 phase spans emit `_duration_ms`; root back-dated with a custom start **and** end time (both, or the SDK falls back to system time) in the SDK's clock domain (epoch, not monotonic uptime) |
| 10 | Spans for every journey element | SC-1, PRE-4 | [Step 10](INSTRUMENTATION_GUIDE.md#10-span-every-element-of-the-user-journey) | Builds; start+end emit `_duration_ms`; **parity holds** — every Step 4 screen has a span and no span names a screen the app never emits; every hygiene item in the ⚠️ block below passes |
| 11 | Device id / support *(opt-in)* | SC-5, SC-11 | [Step 11](INSTRUMENTATION_GUIDE.md#11-implement-device-identification-for-support) | Builds |
| 12 | Symbol upload *(release only)* | SC-3 | [Step 12](INSTRUMENTATION_GUIDE.md#12-upload-symbol-files-for-readable-crash-stacks) | Upload step wired; uses SDK key |
| 13 | New session on logout/reset *(opt-in)* | SC-6 | [Step 13](INSTRUMENTATION_GUIDE.md#13-new-session-on-user-logout-or-journey-reset) | Builds; global fields re-applied after; on a logout boundary the entity ID is cleared and user-scoped fields removed |
| 14 | Forward existing logger *(if detected)* | PRE-3, SC-8 | [Step 14](INSTRUMENTATION_GUIDE.md#14-forward-your-existing-log-framework) | Builds |
| 15 | Forward analytics/beacon events *(if detected)* | PRE-2, SC-8, SC-7 | [Step 15](INSTRUMENTATION_GUIDE.md#15-forward-analytics--beacon-events) | Builds; events bridged at single submission point |
| 16 | Feature flag exposures *(if detected)* | PRE-5, SC-7 | [Step 16](INSTRUMENTATION_GUIDE.md#16-record-feature-flag-exposures) | Builds; recorded at divergence point |
| 17 | Session replay *(verify; already on by default)* | SC-9 | [Step 17](INSTRUMENTATION_GUIDE.md#17-session-replay-wireframe--on-by-default) | Builds; the configuration in force is **stated** — enabled (default) or explicitly disabled with the reason. Never leave this unreported |
| 18 | Cross-link existing crash reporter *(if detected)* | SC-3 | [Step 18](INSTRUMENTATION_GUIDE.md#18-cross-link-with-your-existing-crash-reporter) | Builds; session URL attached as a custom key/tag |
| 19 | Crash workflows + CUJ + POC dashboards | SC-3, SC-7, SC-11 | [Step 19](INSTRUMENTATION_GUIDE.md#19-turn-crashes-and-journeys-into-workflows-and-dashboards) | Driven by **bd-cli** + **bd-cuj**, not bd-instrumentation. Crash workflow(s) deployed and LIVE; CUJ stack (Sankey/funnel/SLO/alert/session-capture/dashboard) deployed for the ASK'd flow; 3 POC dashboards composed and viewable; **span-percentile charts present on the Business/UX dashboard**, labeled distinctly from bd-cuj's wall-clock step timing |
| 20 | Evaluation readout | All in-scope | [Step 20](INSTRUMENTATION_GUIDE.md#20-generate-the-evaluation-readout) | Every in-scope criterion has a named artifact + a `bd-cli` command or portal link proving it |

> ⚠️ **Step 6 cardinality gate (hard requirement, not advisory).** Any path with a dynamic
> segment (id/uuid) **must** get a stable path template before this step passes. Unbounded
> cardinality is **silently dropped** server-side. If you cannot template a dynamic route,
> record it in the run report as a known gap — do not mark step 6 passed.

> ⚠️ **Step 10 span-hygiene gate (hard requirement, not advisory).** Every one of these produces a
> chart that is wrong or empty *without producing an error*, so none of them is caught by a build:
>
> 1. The span **wraps** the try/catch, not the reverse — a swallowing catch inside the span records
>    SUCCESS on a failed operation, usually a fast one, so the p50 improves when the app breaks.
> 2. Cancellation maps to **CANCELED, not FAILURE**. On Android this is the common case:
>    `LaunchedEffect(key)` cancels on ordinary scrolling.
> 3. No broad `catch (Exception)` inside a span body — in Kotlin it swallows `CancellationException`
>    before the wrapper sees it, undoing item 2.
> 4. No bare `return` inside a span closure — it exits the closure, not the caller.
> 5. Custom start times are in the SDK's clock domain (**epoch**, not monotonic uptime), and are
>    supplied as a **pair** — a custom start with no custom end is silently tracked on system time.
> 6. Children pass an **explicit parent span ID** — never an ambient/global span-context stack,
>    which misattributes under concurrent loads.
> 7. Every span name is reachable in the app's **default configuration** — not only behind a
>    non-default mode or an off-by-default flag. If gated, wire a headless toggle and report it.
> 8. Duration charts set `y_axis.unit = MILLISECONDS` and a `TimeSeriesMetadata.title` per series at
>    creation (without a title the legend shows an opaque action-ID hash), and filter
>    `_result != canceled` where cancellation is routine.
>
> Full detail and the code that hits each one:
> [examples/journey-span-instrumentation.md](examples/journey-span-instrumentation.md).

> ⚠️ **Step 6 outbound-header notice (report it, don't silently ship it).** With network capture on,
> the SDK injects a distributed-tracing header into instrumented outgoing requests by default (W3C
> `traceparent`; `b3-single` / `b3-multi` / Datadog / `none` also available, selected by the
> **server-side** runtime variable `client_config.trace.propagation_mode`). This reaches the
> customer's backend, WAF, and CDN without an app release. Name it in the run report whenever Step 6
> ran. It is not a failure — it is a change to outbound traffic that nobody should discover from a
> CORS preflight error in staging.

> **API signatures:** before writing call sites, have bd-instrumentation confirm exact
> symbols for the installed SDK version via **bd-docs** (e.g. iOS `setEntityID` capital ID,
> chained integrations; RN top-level named exports). Do not guess signatures.

---

## 3. Final verification — checkable assertions

Run all of these after the last in-scope step. Each is pass/fail; the run is **green only if
all pass**.

**V1 — Build is clean.** Platform build exits 0:
- Android: `./gradlew clean && ./gradlew build`
- iOS: `xcodebuild ... build` (or the project's scheme build) exits 0
- React Native: `pod install` (iOS) succeeds **and** the app bundles

**V2 — Instrumentation is present.** Source contains the SDK and a logger-start call:
- Android: `grep -rq "io.bitdrift" .`
- iOS: `grep -rq "import Capture" .`
- React Native: `grep -rq "@bitdrift/react-native" .`

**V3 — No interpolated log messages** (Step 7 contract): spot-check that custom log
*messages* are stable strings and variable data is in fields, not string-formatted into the
message.

**V4 — Data flows to the platform.** SDK calls are no-ops until the logger starts, so a
clean build is necessary but not sufficient. Launch the app (or a debug session) and confirm
a session appears:
- Use **bd-cli** to query recent sessions for this app (see the `bd-cli` skill for the
  exact command). **PASS** if ≥1 session with timeline events appears within ~120s of launch.
- If empty after 120s → **FAIL V4**; report (do not silently pass). Likely causes: logger
  not started early enough, wrong SDK key, no network egress from device/emulator.
- **Diagnose in-app before guessing.** The `startResult` callback wired in Step 2 reports an
  initialization error directly, and `getSdkStatus()` distinguishes the cases the list above
  lumps together: `NotStarted` / `Disabled` is a start problem, while `Running` with a stale
  last-handshake or last-config-delivery time is an egress or key problem. Report which one.

**V5 — Decisions logged.** The run report names: chosen session strategy, the events
instrumented (Step 7), the spans added (Step 10 — see V9's parity table), the session-replay state
(on by default, or disabled with the reason), the trace-propagation mode in force, and any skipped
opt-in steps.

**V6 — POC coverage.** If a POC scope was provided, every in-scope `SC-n`/`PRE-n` criterion
maps to a step that ran (per the §2 column and the
[coverage matrix](INSTRUMENTATION_GUIDE.md#poc-success-criteria-coverage)). For each in-scope
criterion, assert it is covered; **FAIL V6** and list any in-scope criterion with no
completed step. Note: SC-3/SC-4/SC-6/SC-10 are satisfied by automatic instrumentation once
Step 2 ran — confirm they appear in the dashboard as part of V4.

**V7 — Workflows and dashboards are live, not just deployed.** If Step 19 ran, use **bd-cli**
to confirm the crash workflow(s) and the bd-cuj CUJ stack transitioned to **LIVE** status (not
stuck `IDLE` — this is exactly the drift the account audit found in an earlier run: workflows
created but never deployed, or deployed with an empty match rule instead of the intended Ripsaw
script). **FAIL V7** if any workflow this run created is not LIVE.

For chart data, the bar depends on whether matching traffic actually occurred:

- **CUJ charts** (Sankey, funnel, completion rate, network) — representative journey traffic is
  something the run can generate, so **FAIL V7** if these return no data after exercising the
  flow.
- **Span-timing charts** (screen load, journey phase, cold start) — same bar as CUJ charts, for the
  same reason: the run can generate the traffic. An empty one means the span is on a code path the
  default configuration never runs, or the matcher names a span that was never added. **FAIL V7**;
  do not write it off as low traffic.
- **Crash workflows** — a valid, correctly-scripted crash workflow legitimately has no data when
  no matching crash occurred, and this runbook never requires causing one. Do **not** fail on an
  empty crash chart. Validate on LIVE state plus a correct deployed script, and record
  *"deployed, no matching crash observed during the run"* in the report. Failing here would
  reject a working workflow on most fresh POCs, where crashes are rare by design.

Check the *deployed definition*, not only the state — `bd workflow describe <ID>` and confirm the
matchers hold values the app actually emits. A matcher on a screen name that is never logged
deploys clean and reports LIVE while charting nothing, which presents as 0% conversion rather
than as an error. Note also that funnel and Sankey charts return `funnel_data` / `sankey_data`,
**not** `line_data.time_series` — a populated funnel looks empty to a check that only inspects
metric series.

**V8 — Evaluation readout is evidence-backed.** If Step 20 ran, every in-scope criterion in
the readout has a concrete artifact (a chart, workflow, dashboard, or session ID) and a
`bd-cli` command or portal link that proves it — not just a step name. **FAIL V8** on any
criterion listed with no accompanying proof. If no POC scope was given, "in-scope criterion"
has no `SC-n`/`PRE-n` set to check against — apply the same evidence bar to each step listed in
the generic step-coverage summary (§2) instead, so an empty readout can't pass V8 by vacuously
having nothing to check.

**V9 — Span/screen parity.** Produce the table of every emitted screen name against every span
name. **FAIL V9** on an orphan in either direction: a screen with no `<screen>_screen_load` span, or
a span naming a screen the app never emits. Journey-phase spans are checked the same way against the
phases of the flow chosen for Step 19.

**V10 — Span data is real, not just present.** Via **bd-cli**, every span name added has non-zero
events after the flow has been exercised. Two specific failures this catches, both of which look
like a broken chart and are not:
- The span sits on a code path the app's **default configuration never runs** (a non-default journey
  mode, an off-by-default feature flag). Fix the coverage or wire a headless toggle; don't relabel it
  as "no traffic."
- The span reports **only FAILURE or CANCELED**. That is a hygiene bug (⚠️ items 1–3), not a
  measurement — its durations are partial and will skew every percentile it feeds.

Also check the shape of what arrives: several unrelated spans reporting an *identical* duration is
near-conclusive evidence of one shared failure mode (a fixed timeout, a dead backend), not several
real measurements. Report it rather than charting it.

---

## 4. Run report — emit at the end

Produce a short structured summary so the run is auditable:

```
platform:        <android|ios|react-native>
steps_run:       <list>
steps_skipped:   <list + reason>
session_strategy: <fixed|activity-based>
sdk_status:      <getSdkStatus() state at first launch + startResult outcome>
session_replay:  <enabled (default) | disabled + reason>
trace_propagation: <w3c (default)|b3-single|b3-multi|dd|none> — outbound header the app now sends
events_logged:   <names>
screen_spans:    <screen name -> span name parity table; "none unpaired" or the orphans>
journey_spans:   <phase spans + their parent>
cold_start_spans: <root + phases, or "not run">
span_hygiene:    <⚠️ items 1-8, each pass/fail>
cardinality_gaps: <any un-templated dynamic routes, or none>
poc_coverage:    <each in-scope SC-n/PRE-n → covering step, or "no POC scope provided">
gates:           V1 <pass/fail> V2 ... V10 ...
data_in_dashboard: <yes + session id | no + suspected cause>
crash_workflows: <name/id + LIVE status, or "not run">
cuj_stack:       <flow name + Sankey/funnel/SLO/alert/dashboard ids, or "not run">
poc_dashboards:  <dashboard names/ids built, or "not run">
evaluation_readout: <link/path to the readout doc, or "not run">
```

---

## Reference

- **[INSTRUMENTATION_GUIDE.md](INSTRUMENTATION_GUIDE.md)** — human reference; full prose for
  each step, what it unlocks, and platform notes.
- **[AGENT_CLEANUP_GUIDE.md](AGENT_CLEANUP_GUIDE.md)** — autonomous contract to revert
  everything this runbook added.
