# bitdrift Cleanup Guide

**Version 1.4** — covers removal of all 21 steps, including post-instrumentation signal catalogs and the server-side workflow/dashboard state derived from them.

Remove all bitdrift Capture SDK instrumentation from **any** app and return it to its baseline (pre-bitdrift) state — **by prompting an AI coding agent**. Each step is a ready-to-use prompt that drives the **bd-instrumentation** skill to undo the corresponding instrumentation step.

This is the inverse of [INSTRUMENTATION_GUIDE.md](INSTRUMENTATION_GUIDE.md): the same 21 steps, removed in **reverse order** (last added, first removed) so dependent call sites come out before the foundation they relied on, and the project keeps compiling at each step. The prompts are platform-neutral — the skill applies the right removals on Android, iOS, or React Native.

> **Do it in one prompt (app code only):** *"Remove all bitdrift Capture SDK instrumentation from this app, working in reverse order. Build if permitted; otherwise perform static verification and report the build as DEFERRED."* The skill sequences the work for Steps 1–18 (app code). The per-step prompts below are the reference if you want to remove categories selectively.
>
> **Step 20 is server-side/account state, not app code** — deleting a crash workflow, a CUJ stack, or a dashboard is destructive to whatever else the account was using them for, and isn't covered by the one-shot prompt above. Confirm explicitly before removing any of it (see order 1 below).
>
> **Steps 19 and 21 are documents.** The signal catalog and evaluation readout have no account-side state — discarding them is an ordinary file deletion needing no special confirmation, and is independent of whether you keep or delete the Step 20 resources (see order 2 below — after Step 20 deletion, since the readout records the IDs that deletion needs).

> **Prefer to run this unattended?** This is the *human* reference. For a fully autonomous run, point your agent at the companion **[AGENT_CLEANUP_GUIDE.md](AGENT_CLEANUP_GUIDE.md)** runbook (preflight, strict reverse order, and grep-based verification gates the agent checks itself) and say *"execute this runbook."* Builds are recommended but optional; the agent must distinguish PASS, FAIL, and DEFERRED.

> **Scope:** use `local-only` to remove app instrumentation and local artifacts;
> use `full-revert` to remove the signal catalog and evaluation readout too. Step 20 account resources
> are destructive and always require explicit confirmation.

---

## When to use this guide

- **Return to baseline** to test the app without bitdrift instrumentation.
- **Cleanly evaluate** bitdrift, then revert before deciding to adopt.
- **Roll back** an experimental integration.

---

## Cleanup prompts — reverse order

Work from the bottom of the instrumentation guide up. Each prompt drives the skill to remove one category; the reference links back to what that step added.

> **Delete the account resources before discarding the readout.** The readout is usually the only
> place the created workflow/dashboard IDs are written down — discard it first and you're left
> identifying them by name against unrelated account state.

| Order | Prompt | Reference |
|-------|--------|-----------|
| 1 | *"Using the workflow and dashboard IDs recorded in the post-instrumentation build readout, delete the crash workflow(s), the bd-cuj CUJ stack (Sankey/funnel/SLO/alerts), and the POC dashboards — confirm each deletion explicitly, this is destructive account state."* | [Step 20](INSTRUMENTATION_GUIDE.md#20-build-workflows-and-dashboards-from-observed-data) |
| 2 | *"Discard the signal catalog, evaluation readout, and any generated summary artifacts."* (no code involved) | [Steps 19 and 21](INSTRUMENTATION_GUIDE.md#19-discover-and-validate-post-instrumentation-data) |
| 3 | *"Remove the bitdrift session-URL cross-linking from our existing crash reporter, and any `previousRunInfo` usage added alongside it."* | [Step 18](INSTRUMENTATION_GUIDE.md#18-cross-link-with-your-existing-crash-reporter) |
| 4 | *"Disable bitdrift wireframe session replay by passing a null session-replay configuration — do not just revert to a default `Configuration`."* | [Step 17](INSTRUMENTATION_GUIDE.md#17-session-replay-wireframe--on-by-default) |
| 5 | *"Remove all bitdrift feature-flag exposure calls."* | [Step 16](INSTRUMENTATION_GUIDE.md#16-record-feature-flag-exposures) |
| 6 | *"Remove the bitdrift analytics/beacon-event forwarding bridge at the analytics submission point."* | [Step 15](INSTRUMENTATION_GUIDE.md#15-forward-analytics--beacon-events) |
| 7 | *"Remove the bitdrift log-framework forwarding (the Timber/CocoaLumberjack/console bridge)."* | [Step 14](INSTRUMENTATION_GUIDE.md#14-forward-your-existing-log-framework) |
| 8 | *"Remove all bitdrift new-session calls and the field re-application that followed them."* | [Step 13](INSTRUMENTATION_GUIDE.md#13-new-session-on-user-logout-or-journey-reset) |
| 2b | *"Remove the README sections and in-code comments that describe the bitdrift instrumentation — what was instrumented, deploy steps, dashboard IDs, and any comment naming an SDK call or span name. Leave the app's own product documentation."* | — |
| 9 | *"Remove the bitdrift symbol/mapping upload from the build, and any bitdrift-specific scripts (symbol upload, workflow deploy). Leave the app's own tooling scripts alone."* | [Step 12](INSTRUMENTATION_GUIDE.md#12-upload-symbol-files-for-readable-crash-stacks) |
| 10 | *"Remove the bitdrift device-code / session-URL support affordance and the support-mode field."* | [Step 11](INSTRUMENTATION_GUIDE.md#11-implement-device-identification-for-support) |
| 11 | *"Remove all bitdrift spans — screen-load, journey-phase, and any app-specific ones — plus the span-helper file added for them."* | [Step 10](INSTRUMENTATION_GUIDE.md#10-span-every-element-of-the-user-journey) |
| 12 | *"Remove bitdrift app-launch TTI reporting, the cold-start span waterfall, and the process-start timestamp they used."* | [Step 9](INSTRUMENTATION_GUIDE.md#9-report-app-launch-tti--cold-start-span-waterfall) |
| 13 | *"Remove all bitdrift global fields and any field providers."* | [Step 8](INSTRUMENTATION_GUIDE.md#8-attach-global-fields) |
| 14 | *"Remove all bitdrift structured custom logs. If the app logs through its own facade that also writes to os.log/Timber/etc., strip only the bitdrift emission inside it and leave the facade and its call sites intact."* | [Step 7](INSTRUMENTATION_GUIDE.md#7-emit-structured-custom-logs) |
| 15 | *"Remove bitdrift network capture from every HTTP client and delete all path templates — including the `pathTemplate` parameter on the app's request builder and every call site that passes one."* | [Step 6](INSTRUMENTATION_GUIDE.md#6-capture-network-traffic) |
| 16 | *"Remove all bitdrift entity-ID calls — `setEntityId`/`setEntityID` and `clearEntityId`/`clearEntityID`."* | [Step 5](INSTRUMENTATION_GUIDE.md#5-identify-users-with-entity-id) |
| 17 | *"Remove bitdrift screen-view tracking and any navigation listener added for it — but if the listener also drives app-owned behaviour (breadcrumbs, a persisted last-screen), keep that and strip only the bitdrift call."* | [Step 4](INSTRUMENTATION_GUIDE.md#4-instrument-screen-views-and-pair-them-with-load-spans) |
| 18 | *"Remove the session strategy (together with the logger-start call below)."* | [Step 3](INSTRUMENTATION_GUIDE.md#3-confirm-session-strategy) |
| 19 | *"Remove the bitdrift logger-start call from app startup, its `Configuration` (session replay, WebView, sleep mode, fatal-issue reporting), the `startResult` callback and any `getSdkStatus()` checks, and all bitdrift imports."* | [Step 2](INSTRUMENTATION_GUIDE.md#2-start-the-logger) |
| 20 | *"Remove the bitdrift Capture SDK dependency, the build plugin, and its `bitdrift { instrumentation { … } }` DSL block, then clean and rebuild."* | [Step 1](INSTRUMENTATION_GUIDE.md#1-add-the-dependency) |

> **Spans are no longer a handful of call sites.** Under guide v1.2 an instrumented app has one span per screen, one per journey phase, the cold-start waterfall, and a span-helper file — so order 11 is the largest removal in this list. Two things to keep straight: the cold-start spans come out under order 12 with TTI, not order 11; and if TTI is being *kept* while spans are removed, the process-start timestamp stays.

> **Session replay is on by default, so "revert the configuration" is the wrong instinct** (order 4). Restoring a default `Configuration` re-enables replay, because `sessionReplayConfiguration` defaults to a live object on both platforms. On a **full** revert this is moot — the whole SDK goes at order 20. It matters on a **partial** removal, where leaving the logger in place means leaving replay running.

> **Order is a sensible default, not a rule.** On a full revert the end state is the same whichever
> way you go, and working file-by-file is usually faster — one file often holds several orders' worth
> of call sites. Keep to the order on a *partial* removal, where what you leave has to keep working.
>
> **Original rationale.** Orders 1–2 are server-side/account cleanup with no build impact, so they're safe to do first (or to skip, if the workflows/dashboards should stay). From order 3 onward, the skill removes call sites (spans, logs, fields, screen views, network) *before* the logger-start call and the dependency. That ordering keeps transient breakage to a minimum, though nothing verifies compilation at each step — build when you want to, not because a gate demands it. The dependency comes out last.

---

## Verify the cleanup

> **Prompt:** *"Confirm all bitdrift instrumentation is gone: no SDK imports, no Logger calls, no path templates or upload steps remain, and the project builds clean."*

The skill checks that the codebase is back to baseline. For a manual spot-check, these searches should return nothing and the build should succeed:

```bash
grep -r "io.bitdrift" .        # Android: no SDK references (also check ios/ for "import Capture", JS for "@bitdrift")
grep -rn "bitdrift SDK:\|POC:" .   # orphaned rationale comments — no grep in the runbook catches prose
./gradlew clean && ./gradlew build   # or the platform's equivalent build
```

Two things a grep will not tell you, and both routinely survive an otherwise-clean removal:

- **On iOS, the dSYM upload is a run-script build phase inside `project.pbxproj`**, not source — a
  source grep misses it entirely. Check the target's Build Phases, and that no Swift-package
  reference to the SDK remains.
- **Prose.** README sections describing the instrumentation, and in-code comments naming SDK calls
  or span names, leave the repo asserting behaviour the code no longer has. If the app is being
  cleaned so the instrumentation guide can be re-run against it, leaving them **invalidates that
  test** — the next agent reads the answer instead of finding it.

**Checklist** (foundation comes out last — confirm it's gone at the end):

- [ ] Evaluation readout discarded (20)
- [ ] Crash workflows, CUJ stack, and POC dashboards deleted from the account — or deliberately kept (19)
- [ ] Crash-reporter session-URL cross-linking removed (18)
- [ ] Session replay explicitly disabled — null config, not a default `Configuration` (17)
- [ ] Logger `Configuration` removed: session replay, WebView, sleep mode, fatal-issue reporting (2)
- [ ] `startResult` callback and `getSdkStatus()` checks removed (2)
- [ ] Gradle plugin `bitdrift { instrumentation { … } }` DSL block removed (1, 6)
- [ ] No feature-flag exposure calls (16)
- [ ] Analytics/beacon forwarding bridge removed (15)
- [ ] Log-framework bridge removed (14)
- [ ] No new-session calls (13)
- [ ] Symbol/mapping upload removed (12)
- [ ] Device code + support field removed (11)
- [ ] No screen-load spans (10)
- [ ] No journey-phase spans (10)
- [ ] No app-specific spans — custom networking, compute, image/row loads (10)
- [ ] Span-helper / bridge file deleted (10)
- [ ] No cold-start waterfall spans (9)
- [ ] No TTI reporting or process-start timestamp (9)
- [ ] No global fields / field providers (8)
- [ ] No custom log calls (7)
- [ ] No network capture or path templates (6)
- [ ] No entity-ID calls — set *and* clear (5)
- [ ] No screen-view tracking or navigation listener (4)
- [ ] No session strategy / logger-start call (3, 2)
- [ ] SDK dependency and build plugin removed (1)
- [ ] iOS: no bitdrift run-script build phase or Swift-package reference left in the Xcode project (9, 1)
- [ ] README sections and in-code comments describing the instrumentation removed (2b)

Then build the project if permitted. It is recommended evidence, not part of the
reference-removal checklist. If skipped, report `DEFERRED` rather than claiming the
app still compiles. In all cases, search for orphaned imports, deleted helper names,
stale parameters, removed API methods, and suspend/non-suspend overload ambiguity.

Also inspect ignored local configuration (`.xcconfig`, `local.properties`, and
environment overrides) for stale backend hosts or recursive includes. Preserve
those files unless the user explicitly asks to change them, and never include keys
or secrets in the cleanup report.
- [ ] No remaining Capture SDK, telemetry configuration, or instrumentation references in the target app; sample product identity such as `ai.bitdrift.shop` and Bitdrift Shop branding may remain

---

## Platform notes

The prompts are platform-neutral; the skill applies the right removals:

- **iOS:** drops `.enableIntegrations([...])` from the start call, the start call itself (in `@main init()` / `didFinishLaunchingWithOptions`), the `import Capture`, the SPM/CocoaPods dependency, and any dSYM upload build-phase.
- **React Native:** removes the top-level `@bitdrift/react-native` calls and import, the npm package, and the Hermes source-map upload, then `pod install` (iOS) to drop the native pod; Android de-autolinks on package removal.

Ask the skill to confirm the exact symbols for your SDK version via **bd-docs** before deleting call sites.

---

## Reference

- **[INSTRUMENTATION_GUIDE.md](INSTRUMENTATION_GUIDE.md)** — the prompts that add each category (use it to see what each cleanup prompt undoes).
