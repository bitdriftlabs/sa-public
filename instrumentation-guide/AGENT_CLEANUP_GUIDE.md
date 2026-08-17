# Agent Cleanup Runbook

**Version 1.1 — machine-consumable** — covers removal of all 20 steps, including server-side workflow/dashboard state.

This is the **autonomous execution contract** for removing all bitdrift Capture SDK
instrumentation and returning the app to baseline. It wraps
[CLEANUP_GUIDE.md](CLEANUP_GUIDE.md) (the human reference) with a halt-on-failure preflight,
a strict reverse order, and verification gates phrased as checkable assertions.

> **You are the agent.** Read top to bottom, then execute. Removal is **reverse order**
> (last added, first removed) so the project compiles at every step. Stop immediately on any
> `HALT` and report which gate failed.

---

## 0. Preflight — run first, HALT on any failure

| # | Check | How to verify | On failure |
|---|-------|---------------|------------|
| P1 | Skills installed | `bd-instrumentation`, `bd-docs` resolvable (`bd-cli` also needed if removing Step 19/20 server-side state) | HALT: `npx skills add bitdriftlabs/bd-skills` |
| P2 | Platform detected | android / ios / react-native | HALT if undetectable |
| P3 | bitdrift actually present | V2 grep from §3 returns matches | HALT (nothing to remove — report "already baseline") |
| P4 | Clean working tree | `git status --porcelain` empty (or user accepts dirty) | WARN; continue (keeps the removal diff reviewable) |
| P5 | Baseline build passes | platform build succeeds **before** removal | HALT: a red baseline makes per-step gates meaningless |

Record platform from P2 — it selects the verification commands in §3.

---

## 1. Decision defaults

| Decision | Default |
|----------|---------|
| Scope | Remove **all** bitdrift instrumentation (full revert). Partial removal only if user named specific categories. |
| Confirm exact symbols | Have bd-instrumentation confirm SDK symbols via **bd-docs** before deleting call sites — avoids leaving orphaned references. |
| Server-side workflows/dashboards (Step 19) | **In scope**, but destructive and account-wide — `ASK` for explicit confirmation before deleting any crash workflow, CUJ stack, or dashboard. Never delete silently as part of a "remove everything" pass. If the user doesn't confirm, skip Step 19/20 removal and note it in the run report as intentionally left in place. |

---

## 2. Execution order — reverse, gate after each

Drive each removal via **bd-instrumentation**. After every step, the project **must still
build** — HALT on a failed gate. Order is fixed: call sites come out before the logger-start
and the dependency, which comes out last.

| Order | Removal | Prompt source | Gate |
|-------|---------|---------------|------|
| 1 | Evaluation readout + generated artifacts | [Step 20](INSTRUMENTATION_GUIDE.md#20-generate-the-evaluation-readout) | No code — nothing to build |
| 2 | Crash workflow(s), CUJ stack, POC dashboards *(ASK before deleting — see §1)* | [Step 19](INSTRUMENTATION_GUIDE.md#19-turn-crashes-and-journeys-into-workflows-and-dashboards) | No code — confirm via **bd-cli** that each is actually deleted, or explicitly skipped |
| 3 | Crash-reporter session-URL cross-linking | [Step 18](INSTRUMENTATION_GUIDE.md#18-cross-link-with-your-existing-crash-reporter) | Builds |
| 4 | Session replay disable + config revert | [Step 17](INSTRUMENTATION_GUIDE.md#17-enable-session-replay-wireframe) | Builds |
| 5 | Feature-flag exposure calls | [Step 16](INSTRUMENTATION_GUIDE.md#16-record-feature-flag-exposures) | Builds |
| 6 | Analytics/beacon forwarding bridge | [Step 15](INSTRUMENTATION_GUIDE.md#15-forward-analytics--beacon-events) | Builds |
| 7 | Log-framework forwarding bridge | [Step 14](INSTRUMENTATION_GUIDE.md#14-forward-your-existing-log-framework) | Builds |
| 8 | New-session calls + field re-application | [Step 13](INSTRUMENTATION_GUIDE.md#13-new-session-on-user-logout-or-journey-reset) | Builds |
| 9 | Symbol/mapping upload + manual scripts | [Step 12](INSTRUMENTATION_GUIDE.md#12-upload-symbol-files-for-readable-crash-stacks) | Builds |
| 10 | Device-code/support affordance + field | [Step 11](INSTRUMENTATION_GUIDE.md#11-implement-device-identification-for-support) | Builds |
| 11 | All spans (start/end + track-span) | [Step 10](INSTRUMENTATION_GUIDE.md#10-measure-operations-with-custom-spans) | Builds |
| 12 | App-launch TTI + process-start timestamp | [Step 9](INSTRUMENTATION_GUIDE.md#9-report-app-launch-tti) | Builds |
| 13 | Global fields + field providers | [Step 8](INSTRUMENTATION_GUIDE.md#8-attach-global-fields) | Builds |
| 14 | Structured custom logs | [Step 7](INSTRUMENTATION_GUIDE.md#7-emit-structured-custom-logs) | Builds |
| 15 | Network capture + all path templates | [Step 6](INSTRUMENTATION_GUIDE.md#6-capture-network-traffic) | Builds |
| 16 | Entity-ID calls | [Step 5](INSTRUMENTATION_GUIDE.md#5-identify-users-with-entity-id) | Builds |
| 17 | Screen-view tracking + nav listener | [Step 4](INSTRUMENTATION_GUIDE.md#4-instrument-screen-views) | Builds |
| 18 | Session strategy (with logger-start below) | [Step 3](INSTRUMENTATION_GUIDE.md#3-confirm-session-strategy) | Builds |
| 19 | Logger-start call + all bitdrift imports | [Step 2](INSTRUMENTATION_GUIDE.md#2-start-the-logger) | Builds |
| 20 | SDK dependency + build plugin, clean+rebuild | [Step 1](INSTRUMENTATION_GUIDE.md#1-add-the-dependency) | Builds from clean |

---

## 3. Final verification — checkable assertions

The cleanup is **green only if all pass**.

**V1 — No SDK references remain.** Each grep must return **nothing**:
- Android: `grep -r "io.bitdrift" .`
- iOS: `grep -r "import Capture" .` (and any `BitdriftCapture` / SPM/Pod entries)
- React Native: `grep -r "@bitdrift" .`
- All: no path templates, no debug-file upload steps, no `bd debug-files` scripts remain.

**V2 — Build is clean from scratch.** Exits 0:
- Android: `./gradlew clean && ./gradlew build`
- iOS: clean build of the scheme; if CocoaPods, `pod install` reflects pod removal
- React Native: package removed from `package.json`; `pod install` (iOS) drops native pod; Android de-autolinks

**V3 — Dependency manifests clean.** No bitdrift entry in `build.gradle(.kts)` / `Package.swift` / `Podfile` / `package.json`.

**V4 — Checklist parity.** Every item in [CLEANUP_GUIDE.md](CLEANUP_GUIDE.md#verify-the-cleanup) checklist is satisfied.

**V5 — Server-side state matches the decision made in §1.** If workflow/dashboard deletion was
confirmed, use **bd-cli** to verify the crash workflow(s), CUJ stack, and POC dashboards from
Step 19 no longer exist. If deletion was declined, confirm the run report says so explicitly —
don't leave it ambiguous whether they were removed or simply forgotten.

---

## 4. Run report — emit at the end

```
platform:         <android|ios|react-native>
categories_removed: <list>
categories_skipped: <list + reason, if partial>
gates:            V1 <pass/fail> V2 ... V5 ...
residual_refs:    <none | list of remaining matches>
server_side_state: <crash workflows/CUJ stack/dashboards deleted (with IDs) | intentionally kept per user decision>
```

---

## Reference

- **[CLEANUP_GUIDE.md](CLEANUP_GUIDE.md)** — human reference with per-step prompts and the checklist.
- **[AGENT_INSTRUMENTATION_GUIDE.md](AGENT_INSTRUMENTATION_GUIDE.md)** — the contract this reverts.
