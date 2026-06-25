# Agent Cleanup Runbook

**Version 1.0 — machine-consumable**

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
| P1 | Skills installed | `bd-instrumentation`, `bd-docs` resolvable | HALT: `npx skills add bitdriftlabs/bd-skills` |
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
| Server-side workflows | Out of scope — this runbook only touches app code/build. Note any dashboard workflows the user may still want to delete. |

---

## 2. Execution order — reverse, gate after each

Drive each removal via **bd-instrumentation**. After every step, the project **must still
build** — HALT on a failed gate. Order is fixed: call sites come out before the logger-start
and the dependency, which comes out last.

| Order | Removal | Prompt source | Gate |
|-------|---------|---------------|------|
| 1 | Session replay disable + config revert | [Step 17](INSTRUMENTATION_GUIDE.md#17-enable-session-replay-wireframe) | Builds |
| 2 | Feature-flag exposure calls | [Step 16](INSTRUMENTATION_GUIDE.md#16-record-feature-flag-exposures) | Builds |
| 3 | Analytics/beacon forwarding bridge | [Step 15](INSTRUMENTATION_GUIDE.md#15-forward-analytics--beacon-events) | Builds |
| 4 | Log-framework forwarding bridge | [Step 14](INSTRUMENTATION_GUIDE.md#14-forward-your-existing-log-framework) | Builds |
| 5 | New-session calls + field re-application | [Step 13](INSTRUMENTATION_GUIDE.md#13-new-session-on-user-logout-or-journey-reset) | Builds |
| 6 | Symbol/mapping upload + manual scripts | [Step 12](INSTRUMENTATION_GUIDE.md#12-upload-symbol-files-for-readable-crash-stacks) | Builds |
| 7 | Device-code/support affordance + field | [Step 11](INSTRUMENTATION_GUIDE.md#11-implement-device-identification-for-support) | Builds |
| 8 | All spans (start/end + track-span) | [Step 10](INSTRUMENTATION_GUIDE.md#10-measure-operations-with-custom-spans) | Builds |
| 9 | App-launch TTI + process-start timestamp | [Step 9](INSTRUMENTATION_GUIDE.md#9-report-app-launch-tti) | Builds |
| 10 | Global fields + field providers | [Step 8](INSTRUMENTATION_GUIDE.md#8-attach-global-fields) | Builds |
| 11 | Structured custom logs | [Step 7](INSTRUMENTATION_GUIDE.md#7-emit-structured-custom-logs) | Builds |
| 12 | Network capture + all path templates | [Step 6](INSTRUMENTATION_GUIDE.md#6-capture-network-traffic) | Builds |
| 13 | Entity-ID calls | [Step 5](INSTRUMENTATION_GUIDE.md#5-identify-users-with-entity-id) | Builds |
| 14 | Screen-view tracking + nav listener | [Step 4](INSTRUMENTATION_GUIDE.md#4-instrument-screen-views) | Builds |
| 15 | Session strategy (with logger-start below) | [Step 3](INSTRUMENTATION_GUIDE.md#3-confirm-session-strategy) | Builds |
| 16 | Logger-start call + all bitdrift imports | [Step 2](INSTRUMENTATION_GUIDE.md#2-start-the-logger) | Builds |
| 17 | SDK dependency + build plugin, clean+rebuild | [Step 1](INSTRUMENTATION_GUIDE.md#1-add-the-dependency) | Builds from clean |

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

---

## 4. Run report — emit at the end

```
platform:         <android|ios|react-native>
categories_removed: <list>
categories_skipped: <list + reason, if partial>
gates:            V1 <pass/fail> V2 ... V4 ...
residual_refs:    <none | list of remaining matches>
dashboard_note:   <any server-side workflows the user may still want to delete>
```

---

## Reference

- **[CLEANUP_GUIDE.md](CLEANUP_GUIDE.md)** — human reference with per-step prompts and the checklist.
- **[AGENT_INSTRUMENTATION_GUIDE.md](AGENT_INSTRUMENTATION_GUIDE.md)** — the contract this reverts.
