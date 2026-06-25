# Agent Instrumentation Runbook

**Version 1.0 — machine-consumable**

This is the **autonomous execution contract** for instrumenting any mobile app with the
bitdrift Capture SDK. It wraps [INSTRUMENTATION_GUIDE.md](INSTRUMENTATION_GUIDE.md) (the
human reference) with everything an agent needs to run **unattended**: a preflight that
halts on missing preconditions, a default value for every human decision point, a strict
execution order, and verification gates phrased as checkable assertions.

> **POC alignment.** Steps map to the criteria in
> [bitdrift poc scope V2.0.md](../../bitdrift%20poc%20scope%20V2.0.md) (`SC-n` = Success
> Criteria row, `PRE-n` = Required Pre-POC Engineering row). The execution table in §2 lists
> the criteria each step satisfies; the human guide's
> [POC coverage matrix](INSTRUMENTATION_GUIDE.md#poc-success-criteria-coverage) is the
> authoritative cross-walk. If the run is scoped to a specific POC, instrument exactly the
> steps whose criteria are in that POC's signed scope.

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
| P3 | Skills installed | `bd-instrumentation`, `bd-docs`, `bd-cli` resolvable | HALT: `npx skills add bitdriftlabs/bd-skills` |
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
| Session strategy | 3 | **fixed** (fresh session per launch — best for PoC/verification) |
| Which events to log | 7 | Discover candidate business events by scanning the code (checkout, payment, auth, errors). Instrument the **top 3–5 highest-signal** events; list them in the run report. Do **not** ASK. |
| Which operations to span | 10 | Wrap the **single most important multi-step flow** found (e.g. checkout/discovery). One parent span + obvious children. |
| Support affordance | 11 | **Skip by default** — it adds UI. Include only if user asked for support tooling. `ASK` only if the run scope explicitly mentions support. |
| Symbol/mapping upload | 12 | Configure for release builds **only**; no-op for debug-only runs. |
| Log-framework forwarding | 14 | Enable **if** an existing logger (Timber/CocoaLumberjack/console) is detected; otherwise skip. |
| Analytics/beacon forwarding | 15 | Enable **if** an existing analytics/event client (Amplitude, custom dispatcher) is detected; otherwise skip. |
| Feature flag exposures | 16 | Enable **if** a feature-flag system is detected; instrument at the divergence point. Otherwise skip. Confirm API via bd-docs. |
| Session replay | 17 | **Skip by default** unless the POC scope includes SC-9. Confirm enablement via bd-docs before changing config. |
| Scope (which steps) | all | If a **POC scope** is provided → instrument exactly the steps whose POC criteria are in scope (see §2 column). If **no scope** given → run the **PoC core: steps 1–10**, plus 14/15/16 where the relevant framework is auto-detected. Steps 11, 12, 13, 17 only on request or when their criterion is in the POC scope. |

---

## 2. Execution order — sequential, gate after each

Drive each step via the **bd-instrumentation** skill using the prompt from the source guide
(linked). After every step, run its gate. **HALT on a failed gate** — do not continue to
the next step on a broken build.

| Order | Step | POC criteria | Prompt source | Gate (must pass before next step) |
|-------|------|--------------|---------------|-----------------------------------|
| 1 | Add dependency + plugin | PRE-0 | [Step 1](INSTRUMENTATION_GUIDE.md#1-add-the-dependency) | Dependency resolves; project builds |
| 2 | Start logger | SC-3, SC-4, SC-6, SC-10 | [Step 2](INSTRUMENTATION_GUIDE.md#2-start-the-logger) | Builds; logger-start call present in launch path |
| 3 | Session strategy (= default *fixed*) | SC-6 | [Step 3](INSTRUMENTATION_GUIDE.md#3-confirm-session-strategy) | Strategy set on the start call |
| 4 | Screen views | PRE-1, SC-7 | [Step 4](INSTRUMENTATION_GUIDE.md#4-instrument-screen-views) | Builds; navigation listener wired |
| 5 | Entity ID | PRE-6, SC-11, SC-5 | [Step 5](INSTRUMENTATION_GUIDE.md#5-identify-users-with-entity-id) | Builds; set at identity boundary |
| 6 | Network capture + path templates | SC-2, PRE-4 | [Step 6](INSTRUMENTATION_GUIDE.md#6-capture-network-traffic) | Builds; **every** dynamic route has a path template (cardinality gate — see ⚠️ below) |
| 7 | Structured custom logs | SC-8, SC-7 | [Step 7](INSTRUMENTATION_GUIDE.md#7-emit-structured-custom-logs) | Builds; messages are stable names, variable data in fields |
| 8 | Global fields | SC-7, SC-11 | [Step 8](INSTRUMENTATION_GUIDE.md#8-attach-global-fields) | Builds |
| 9 | App launch TTI | SC-1, SC-7 | [Step 9](INSTRUMENTATION_GUIDE.md#9-report-app-launch-tti) | Builds |
| 10 | Custom spans | SC-1, PRE-4 | [Step 10](INSTRUMENTATION_GUIDE.md#10-measure-operations-with-custom-spans) | Builds; start+end emit `_duration_ms` |
| 11 | Device id / support *(opt-in)* | SC-5, SC-11 | [Step 11](INSTRUMENTATION_GUIDE.md#11-implement-device-identification-for-support) | Builds |
| 12 | Symbol upload *(release only)* | SC-3 | [Step 12](INSTRUMENTATION_GUIDE.md#12-upload-symbol-files-for-readable-crash-stacks) | Upload step wired; uses SDK key |
| 13 | New session on logout/reset *(opt-in)* | SC-6 | [Step 13](INSTRUMENTATION_GUIDE.md#13-new-session-on-user-logout-or-journey-reset) | Builds; global fields re-applied after |
| 14 | Forward existing logger *(if detected)* | PRE-3, SC-8 | [Step 14](INSTRUMENTATION_GUIDE.md#14-forward-your-existing-log-framework) | Builds |
| 15 | Forward analytics/beacon events *(if detected)* | PRE-2, SC-8, SC-7 | [Step 15](INSTRUMENTATION_GUIDE.md#15-forward-analytics--beacon-events) | Builds; events bridged at single submission point |
| 16 | Feature flag exposures *(if detected)* | PRE-5, SC-7 | [Step 16](INSTRUMENTATION_GUIDE.md#16-record-feature-flag-exposures) | Builds; recorded at divergence point |
| 17 | Session replay *(opt-in / SC-9 in scope)* | SC-9 | [Step 17](INSTRUMENTATION_GUIDE.md#17-enable-session-replay-wireframe) | Builds; replay enabled per bd-docs |

> ⚠️ **Step 6 cardinality gate (hard requirement, not advisory).** Any path with a dynamic
> segment (id/uuid) **must** get a stable path template before this step passes. Unbounded
> cardinality is **silently dropped** server-side. If you cannot template a dynamic route,
> record it in the run report as a known gap — do not mark step 6 passed.

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

**V5 — Decisions logged.** The run report names: chosen session strategy, the events
instrumented (Step 7), the spanned flow (Step 10), and any skipped opt-in steps.

**V6 — POC coverage.** If a POC scope was provided, every in-scope `SC-n`/`PRE-n` criterion
maps to a step that ran (per the §2 column and the
[coverage matrix](INSTRUMENTATION_GUIDE.md#poc-success-criteria-coverage)). For each in-scope
criterion, assert it is covered; **FAIL V6** and list any in-scope criterion with no
completed step. Note: SC-3/SC-4/SC-6/SC-10 are satisfied by automatic instrumentation once
Step 2 ran — confirm they appear in the dashboard as part of V4. SC-12 (Web views) is TBD in
the template and is not a coverage failure.

---

## 4. Run report — emit at the end

Produce a short structured summary so the run is auditable:

```
platform:        <android|ios|react-native>
steps_run:       <list>
steps_skipped:   <list + reason>
session_strategy: <fixed|activity-based>
events_logged:   <names>
spans_added:     <flow + child spans>
cardinality_gaps: <any un-templated dynamic routes, or none>
poc_coverage:    <each in-scope SC-n/PRE-n → covering step, or "no POC scope provided">
gates:           V1 <pass/fail> V2 ... V6 ...
data_in_dashboard: <yes + session id | no + suspected cause>
```

---

## Reference

- **[INSTRUMENTATION_GUIDE.md](INSTRUMENTATION_GUIDE.md)** — human reference; full prose for
  each step, what it unlocks, and platform notes.
- **[AGENT_CLEANUP_GUIDE.md](AGENT_CLEANUP_GUIDE.md)** — autonomous contract to revert
  everything this runbook added.
