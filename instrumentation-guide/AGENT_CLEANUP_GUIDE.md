# Agent Cleanup Runbook

**Version 1.4 — machine-consumable** — covers removal of all 21 steps, including post-instrumentation signal catalogs and workflow/dashboard state derived from them.

This is the **autonomous execution contract** for removing all bitdrift Capture SDK
instrumentation and returning the app to baseline. It wraps
[CLEANUP_GUIDE.md](CLEANUP_GUIDE.md) (the human reference) with a halt-on-failure preflight,
a strict reverse order, and verification gates phrased as checkable assertions.

> **You are the agent.** Read top to bottom, then execute. Removal is **reverse order**
> (last added, first removed), which keeps transient breakage to a minimum and takes the
> dependency out last. Stop immediately on any `HALT` and report which gate failed.
>
> **This runbook does not gate on the build.** Removal is monotonic toward a known end state, so
> an intermediate break is transient and a final build tells you nothing the greps in §3 don't.
> Verifying the project still compiles is the **caller's** responsibility, not a gate here.

> **Scope modes.** `local-only` removes app instrumentation and local artifacts;
> `full-revert` also removes the signal catalog and evaluation readout; account-side Step 20 deletion
> always requires explicit confirmation. Never delete server resources merely
> because the user asked to clean the local app.

> **Build policy.** A build is recommended after cleanup but is not mandatory. If
> the user says not to build, perform the static gates below and report the build as
> `DEFERRED`; do not claim the project compiles.

---

## 0. Preflight — run first, HALT on any failure

| # | Check | How to verify | On failure |
|---|-------|---------------|------------|
| P1 | Skills installed | `bd-instrumentation`, `bd-docs` resolvable. **Also `bd-cli`, unless the request explicitly excludes Step 20** | HALT: `npx skills add bitdriftlabs/bd-skills` |
| P1b | `bd` usable *(required unless Step 20 is explicitly out of scope)* | `bd --version` exits 0 **and** `bd auth` succeeds interactively, or a harmless authenticated read succeeds when `BD_API_KEY` is already set | HALT: `brew install bd` / `bd auth`. Checking this upfront avoids completing every local removal and only then failing at account cleanup |
| P2 | Source state detected | Run the **V1** grep from §3, check for a local signal catalog/evaluation readout, **and — unless Step 20 is explicitly out of scope — query `bd-cli` for existing Step 20 workflows/dashboards** | Establishes what actually needs removing. Never halts on its own |
| P3 | Something to remove | P2 found SDK references, a catalog/readout, or (when queried) Step 20 workflows/dashboards | HALT with "already baseline" only when everything P2 checked is empty |
| P3b | Platform detected *(only if P2 found SDK references)* | android / ios / react-native | HALT if undetectable **and** app code needs removing. If P2 found no SDK references, skip this and P4 and run the **server-side-and-artifacts-only path** — platform detection is irrelevant when there is no app code to clean |
| P4 | Clean working tree | `git status --porcelain` empty (or user accepts dirty) | WARN; continue (keeps the removal diff reviewable) |
| P5 | Local configuration and generated files | inspect ignored `.xcconfig`, `local.properties`, `.gradle`, `.idea`, `build`, DerivedData, and generated workflow/dashboard directories | WARN; preserve user-owned local files and exclude them from the cleanup diff unless explicitly requested |

Record platform from P3b — it selects the verification commands in §3. On a server-side-only run there is no platform to record and §3's grep gates do not apply.

---

## 1. Decision defaults

| Decision | Default |
|----------|---------|
| Scope | Remove **all** bitdrift instrumentation (full revert). Partial removal only if user named specific categories. |
| Confirm exact symbols | Have bd-instrumentation confirm SDK symbols via **bd-docs** before deleting call sites — avoids leaving orphaned references. |
| Server-side workflows/dashboards (Step 20) | **In scope**, but destructive and account-wide — `ASK` for explicit confirmation before deleting any crash workflow, CUJ stack, or dashboard. Never delete silently as part of a "remove everything" pass. If the user doesn't confirm, skip **Step 20** removal only and note it in the run report as intentionally left in place. |
| Signal catalog + evaluation readout (Steps 19, 21) | Remove **only on a full revert, or when document removal was explicitly requested** — a partial run like "remove screen-view instrumentation" must leave them alone. When in scope, removal is **not** gated on the Step 20 decision: declining to delete workflows must not leave the documents behind. |

---

## 2. Execution order — reverse

Dispatch by order, not uniformly: **order 1** (Step 20) goes through **bd-cli** to delete the
resources recorded in the readout — no code involved, so the gate is confirming via bd-cli that
each is actually gone (or explicitly skipped). **Order 2** (Steps 19 and 21) is a plain file deletion — no
skill. **Orders 3–20** go through **bd-instrumentation**.

Within orders 3–20 the ordering is a **recommended default, not a constraint**: call sites before
the logger-start, dependency last. It exists to minimise transient breakage. On a **full revert**
the end state is identical whichever way you go, and working **file-by-file** is usually faster and
easier to review — a single file often carries five different orders' worth of call sites, and
visiting it once beats visiting it five times. Keep to the order when doing a **partial** removal,
where what you leave behind has to keep working.

⚠️ **Documentation and comments are part of the instrumentation.** No grep in §3 catches prose,
so this is the one category that silently survives an otherwise-green run. Two kinds:

- **Docs** — a README section like "What's already instrumented", deploy instructions, dashboard
  IDs, a project-layout table naming the helper file you just deleted.
- **In-code comments** — rationale notes naming SDK calls, span names, or POC criteria. These
  outnumber the call sites: a real run removed 126 such lines from 14 files after every call site
  was already gone.

Both leave the repo asserting behaviour the code no longer has. **And if the app is being cleaned
so the instrumentation guide can be re-run against it, leaving them invalidates that test outright**
— the next agent reads the answer instead of discovering it, and the run proves nothing. Remove the
sections and comments; keep the app's own product documentation.

⚠️ **Order 1 before order 2 is deliberate.** The readout is usually the only record of which
workflow and dashboard IDs this run created. Discard it first and the agent is left telling this
run's resources apart from unrelated account state by name-matching — exactly the guesswork that
turns a scoped cleanup into a destructive one. Read the IDs out of the readout, delete precisely
that set, then discard the readout.

| Order | Removal | Prompt source | Notes |
|-------|---------|---------------|-------|
| 1 | Crash workflow(s), CUJ stack, POC dashboards, **and any span-timing workflows/dashboards** *(ASK before deleting — see §1)* | [Step 20](INSTRUMENTATION_GUIDE.md#20-build-workflows-and-dashboards-from-observed-data) | Confirm via **bd-cli** that each is actually deleted, or explicitly skipped |
| 2 | Signal catalog, evaluation readout, and generated artifacts *(full revert / explicit request only)* | [Steps 19 and 21](INSTRUMENTATION_GUIDE.md#19-discover-and-validate-post-instrumentation-data) | Plain file deletion |
| 2b | **Instrumentation documentation and comments** — README/docs sections describing the instrumentation, and in-code rationale comments naming SDK calls, span names, or dashboards | — | No skill. See the ⚠️ note below the table — cheap to skip, and the single most common way a "clean" app is not clean |
| 3 | Crash-reporter session-URL cross-linking + any `previousRunInfo` usage | [Step 18](INSTRUMENTATION_GUIDE.md#18-cross-link-with-your-existing-crash-reporter) | — |
| 4 | Session replay — **explicitly disable** (null/nil session-replay configuration) | [Step 17](INSTRUMENTATION_GUIDE.md#17-session-replay-wireframe--on-by-default) | Replay is on in a default `Configuration`, so "reverting to defaults" leaves it running. On a full revert this is moot (order 20 removes everything); on a partial removal it is the whole point of this order |
| 5 | Feature-flag exposure calls | [Step 16](INSTRUMENTATION_GUIDE.md#16-record-feature-flag-exposures) | — |
| 6 | Analytics/beacon forwarding bridge | [Step 15](INSTRUMENTATION_GUIDE.md#15-forward-analytics--beacon-events) | — |
| 7 | Log-framework forwarding bridge | [Step 14](INSTRUMENTATION_GUIDE.md#14-forward-your-existing-log-framework) | — |
| 8 | New-session calls + field re-application | [Step 13](INSTRUMENTATION_GUIDE.md#13-new-session-on-user-logout-or-journey-reset) | — |
| 9 | Symbol/mapping upload + manual scripts | [Step 12](INSTRUMENTATION_GUIDE.md#12-upload-symbol-files-for-readable-crash-stacks) | A `scripts/` directory usually mixes **bitdrift** scripts (symbol upload, workflow deploy, any release script whose purpose is `bd debug-files`) with the **app's own** tooling (launchers, watchdogs, state readers). Delete only the first kind. Judge by purpose, not by whether `bd` appears in the file |
| 10 | Device-code/support affordance + field | [Step 11](INSTRUMENTATION_GUIDE.md#11-implement-device-identification-for-support) | — |
| 11 | All spans — screen-load, journey-phase, app-specific (start/end + track-span wrappers) — **and the span-helper/bridge file** added for them | [Step 10](INSTRUMENTATION_GUIDE.md#10-span-every-element-of-the-user-journey) | No orphaned helper file or import left behind |
| 12 | App-launch TTI + **cold-start span waterfall** + process-start timestamp | [Step 9](INSTRUMENTATION_GUIDE.md#9-report-app-launch-tti--cold-start-span-waterfall) | The waterfall comes out here, not under order 11. If TTI is being kept on a partial removal, the process-start timestamp stays with it |
| 13 | Global fields + field providers | [Step 8](INSTRUMENTATION_GUIDE.md#8-attach-global-fields) | — |
| 14 | Structured custom logs | [Step 7](INSTRUMENTATION_GUIDE.md#7-emit-structured-custom-logs) | ⚠️ If the app routes logging through **its own facade** that calls both bitdrift and something else (`os.log`, Timber, a print wrapper), remove the **bitdrift emission inside the facade** and leave the facade and all its call sites alone. Deleting the facade deletes the app's logging — often hundreds of call sites — which is not what "remove bitdrift" means. Applies to any bitdrift-typed helper the facade exposes (field encoders, level mappers): those go with the emission |
| 15 | Network capture + all path templates | [Step 6](INSTRUMENTATION_GUIDE.md#6-capture-network-traffic) | Path templates are rarely one header line. They are typically a `pathTemplate:` parameter threaded through the app's request builder and every parameterised call site, so removal is a **signature change with a ripple**, not a deletion. Remove the parameter, its header write, and every argument passed to it |
| 16 | Entity-ID calls — `setEntityId`/`setEntityID` **and** `clearEntityId`/`clearEntityID` | [Step 5](INSTRUMENTATION_GUIDE.md#5-identify-users-with-entity-id) | — |
| 17 | Screen-view tracking + nav listener | [Step 4](INSTRUMENTATION_GUIDE.md#4-instrument-screen-views-and-pair-them-with-load-spans) | Same facade caveat as order 14. The nav listener often also drives app-owned behaviour (breadcrumbs, persisted last-screen); strip the bitdrift call, keep the rest |
| 18 | Session strategy (with logger-start below) | [Step 3](INSTRUMENTATION_GUIDE.md#3-confirm-session-strategy) | — |
| 19 | Logger-start call, its `Configuration` (session replay / WebView / sleep mode / fatal-issue reporting), the `startResult` callback and `getSdkStatus()` checks, and all bitdrift imports | [Step 2](INSTRUMENTATION_GUIDE.md#2-start-the-logger) | — |
| 20 | SDK dependency + build plugin + the `bitdrift { instrumentation { … } }` DSL block | [Step 1](INSTRUMENTATION_GUIDE.md#1-add-the-dependency) | Last — nothing depends on it |

---

## 3. Final verification — checkable assertions

The cleanup is **green only if all pass**. There is deliberately no build gate — see §2. If the
caller needs a compiling project, they build it themselves; a green run here asserts that the
references are gone, not that the app still compiles.

**V5 — Call-site integrity.** After each reverse-order removal, search for orphaned
imports, deleted helper names, stale parameters, suspend/non-suspend overload
ambiguity, and references to deleted API methods. This is mandatory even when no
build is run; cleanup is not complete if the source has known dangling references.

**V6 — Local configuration sanity.** Check effective backend URLs and local config
includes for stale host addresses or recursive includes. Never print SDK keys or
other secrets in the run report. Preserve ignored local configuration unless the
user explicitly asks for it to be changed.

**V1 — No SDK references remain.** Each grep must return **nothing**:
- Android: `grep -r "io.bitdrift" .`
- iOS: `grep -r "import Capture" .` (and any `BitdriftCapture` / SPM/Pod entries)
- React Native: `grep -r "@bitdrift" .`
- All: `grep -r "startSpan\|trackSpan\|CaptureBridge\|getSdkStatus\|startResult\|previousRunInfo\|clearEntityI"` — these survive the per-call-site greps above because a helper or diagnostic wrapper may not import anything obviously bitdrift-named. ⚠️ **`startSpan` and `trackSpan` are generic tracing names, not bitdrift-owned.** An app may legitimately use them for OpenTelemetry, its own tracer, or another vendor. Treat a hit as *something to verify ownership of*, not something to delete: confirm it resolves to a bitdrift type or a helper the instrumentation added. Only bitdrift-owned matches must return nothing
- Android: no `bitdrift { instrumentation { … } }` DSL block and no `automaticOkHttpInstrumentation` / `automaticWebViewInstrumentation` references remain in any `build.gradle(.kts)`
- All: no path templates, no debug-file upload steps, no `bd debug-files` scripts remain.
- iOS: no bitdrift **run-script build phase** survives in `project.pbxproj` (the dSYM upload from
  order 9 is a `PBXShellScriptBuildPhase`, invisible to a source grep), and no
  `XCRemoteSwiftPackageReference` / `XCSwiftPackageProductDependency` for the SDK remains.
- All: **prose is clean too** — no README/doc section describes the removed instrumentation, and no
  in-code comment names an SDK call, span name, workflow, or dashboard. Greps cannot confirm this;
  read the README and skim the diff. See the ⚠️ note under §2.

**V2 — Dependency manifests clean.** No bitdrift entry in `build.gradle(.kts)` / `Package.swift` / `Podfile` / `package.json`.

**V3 — Checklist parity.** Every item in [CLEANUP_GUIDE.md](CLEANUP_GUIDE.md#verify-the-cleanup) checklist is satisfied.

**V4 — Server-side state matches the decision made in §1.** If workflow/dashboard deletion was
confirmed, use **bd-cli** to verify the crash workflow(s), CUJ stack, and POC dashboards from
Step 20 no longer exist. If deletion was declined, confirm the run report says so explicitly —
don't leave it ambiguous whether they were removed or simply forgotten.

---

## 4. Run report — emit at the end

```
platform:         <android|ios|react-native>
categories_removed: <list>
categories_skipped: <list + reason, if partial>
gates:            V1 <pass/fail> V2 ... V4 ...
residual_refs:    <none | list of remaining matches>
server_side_state: <crash workflows/CUJ stack/dashboards deleted (with IDs) | intentionally kept per user decision>
```

---

## Reference

- **[CLEANUP_GUIDE.md](CLEANUP_GUIDE.md)** — human reference with per-step prompts and the checklist.
- **[AGENT_INSTRUMENTATION_GUIDE.md](AGENT_INSTRUMENTATION_GUIDE.md)** — the contract this reverts.
