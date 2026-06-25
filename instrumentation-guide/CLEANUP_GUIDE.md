# bitdrift Cleanup Guide

**Version 1.0**

Remove all bitdrift Capture SDK instrumentation from **any** app and return it to its baseline (pre-bitdrift) state — **by prompting an AI coding agent**. Each step is a ready-to-use prompt that drives the **bd-instrumentation** skill to undo the corresponding instrumentation step.

This is the inverse of [INSTRUMENTATION_GUIDE.md](INSTRUMENTATION_GUIDE.md): the same 17 categories, removed in **reverse order** (last added, first removed) so dependent call sites come out before the foundation they relied on, and the project keeps compiling at each step. The prompts are platform-neutral — the skill applies the right removals on Android, iOS, or React Native.

> **Do it in one prompt:** *"Remove all bitdrift Capture SDK instrumentation from this app, working in reverse order, and confirm the project still builds."* The skill sequences the work. The per-step prompts below are the reference if you want to remove categories selectively.

> **Prefer to run this unattended?** This is the *human* reference. For a fully autonomous run, point your agent at the companion **[AGENT_CLEANUP_GUIDE.md](AGENT_CLEANUP_GUIDE.md)** runbook (preflight, strict reverse order, and build gates the agent checks itself) and say *"execute this runbook."*

---

## When to use this guide

- **Return to baseline** to test the app without bitdrift instrumentation.
- **Cleanly evaluate** bitdrift, then revert before deciding to adopt.
- **Roll back** an experimental integration.

---

## Cleanup prompts — reverse order

Work from the bottom of the instrumentation guide up. Each prompt drives the skill to remove one category; the reference links back to what that step added.

| Order | Prompt | Reference |
|-------|--------|-----------|
| 1 | *"Disable bitdrift wireframe session replay and revert its configuration."* | [Step 17](INSTRUMENTATION_GUIDE.md#17-enable-session-replay-wireframe) |
| 2 | *"Remove all bitdrift feature-flag exposure calls."* | [Step 16](INSTRUMENTATION_GUIDE.md#16-record-feature-flag-exposures) |
| 3 | *"Remove the bitdrift analytics/beacon-event forwarding bridge at the analytics submission point."* | [Step 15](INSTRUMENTATION_GUIDE.md#15-forward-analytics--beacon-events) |
| 4 | *"Remove the bitdrift log-framework forwarding (the Timber/CocoaLumberjack/console bridge)."* | [Step 14](INSTRUMENTATION_GUIDE.md#14-forward-your-existing-log-framework) |
| 5 | *"Remove all bitdrift new-session calls and the field re-application that followed them."* | [Step 13](INSTRUMENTATION_GUIDE.md#13-new-session-on-user-logout-or-journey-reset) |
| 6 | *"Remove the bitdrift symbol/mapping upload from the build and any manual upload scripts."* | [Step 12](INSTRUMENTATION_GUIDE.md#12-upload-symbol-files-for-readable-crash-stacks) |
| 7 | *"Remove the bitdrift device-code / session-URL support affordance and the support-mode field."* | [Step 11](INSTRUMENTATION_GUIDE.md#11-implement-device-identification-for-support) |
| 8 | *"Remove all bitdrift spans (start/end and track-span wrappers)."* | [Step 10](INSTRUMENTATION_GUIDE.md#10-measure-operations-with-custom-spans) |
| 9 | *"Remove bitdrift app-launch TTI reporting and the process-start timestamp it used."* | [Step 9](INSTRUMENTATION_GUIDE.md#9-report-app-launch-tti) |
| 10 | *"Remove all bitdrift global fields and any field providers."* | [Step 8](INSTRUMENTATION_GUIDE.md#8-attach-global-fields) |
| 11 | *"Remove all bitdrift structured custom logs."* | [Step 7](INSTRUMENTATION_GUIDE.md#7-emit-structured-custom-logs) |
| 12 | *"Remove bitdrift network capture from every HTTP client and delete all path templates."* | [Step 6](INSTRUMENTATION_GUIDE.md#6-capture-network-traffic) |
| 13 | *"Remove all bitdrift entity-ID calls."* | [Step 5](INSTRUMENTATION_GUIDE.md#5-identify-users-with-entity-id) |
| 14 | *"Remove bitdrift screen-view tracking and any navigation listener added for it."* | [Step 4](INSTRUMENTATION_GUIDE.md#4-instrument-screen-views) |
| 15 | *"Remove the session strategy (together with the logger-start call below)."* | [Step 3](INSTRUMENTATION_GUIDE.md#3-confirm-session-strategy) |
| 16 | *"Remove the bitdrift logger-start call from app startup and all bitdrift imports."* | [Step 2](INSTRUMENTATION_GUIDE.md#2-start-the-logger) |
| 17 | *"Remove the bitdrift Capture SDK dependency and build plugin, then clean and rebuild."* | [Step 1](INSTRUMENTATION_GUIDE.md#1-add-the-dependency) |

> **Order matters.** The skill removes call sites (spans, logs, fields, screen views, network) *before* the logger-start call and the dependency, so the project compiles at each step. The dependency comes out last.

---

## Verify the cleanup

> **Prompt:** *"Confirm all bitdrift instrumentation is gone: no SDK imports, no Logger calls, no path templates or upload steps remain, and the project builds clean."*

The skill checks that the codebase is back to baseline. For a manual spot-check, these searches should return nothing and the build should succeed:

```bash
grep -r "io.bitdrift" .        # Android: no SDK references (also check ios/ for "import Capture", JS for "@bitdrift")
./gradlew clean && ./gradlew build   # or the platform's equivalent build
```

**Checklist** (foundation comes out last — confirm it's gone at the end):

- [ ] Session replay disabled / config reverted (17)
- [ ] No feature-flag exposure calls (16)
- [ ] Analytics/beacon forwarding bridge removed (15)
- [ ] Log-framework bridge removed (14)
- [ ] No new-session calls (13)
- [ ] Symbol/mapping upload removed (12)
- [ ] Device code + support field removed (11)
- [ ] No span calls (10)
- [ ] No TTI reporting (9)
- [ ] No global fields / field providers (8)
- [ ] No custom log calls (7)
- [ ] No network capture or path templates (6)
- [ ] No entity-ID calls (5)
- [ ] No screen-view tracking or navigation listener (4)
- [ ] No session strategy / logger-start call (3, 2)
- [ ] SDK dependency and build plugin removed (1)
- [ ] Project rebuilds successfully
- [ ] No remaining bitdrift references anywhere in the codebase

---

## Platform notes

The prompts are platform-neutral; the skill applies the right removals:

- **iOS:** drops `.enableIntegrations([...])` from the start call, the start call itself (in `@main init()` / `didFinishLaunchingWithOptions`), the `import Capture`, the SPM/CocoaPods dependency, and any dSYM upload build-phase.
- **React Native:** removes the top-level `@bitdrift/react-native` calls and import, the npm package, and the Hermes source-map upload, then `pod install` (iOS) to drop the native pod; Android de-autolinks on package removal.

Ask the skill to confirm the exact symbols for your SDK version via **bd-docs** before deleting call sites.

---

## Reference

- **[INSTRUMENTATION_GUIDE.md](INSTRUMENTATION_GUIDE.md)** — the prompts that add each category (use it to see what each cleanup prompt undoes).
