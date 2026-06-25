# bitdrift Cleanup Guide

Remove all bitdrift Capture SDK instrumentation from **any** app and return it to its baseline (pre-bitdrift) state.

This is the inverse of [INSTRUMENTATION_GUIDE.md](INSTRUMENTATION_GUIDE.md) — the steps are the same 14 categories, removed in **reverse order** (last added, first removed), so dependent code comes out before the foundation it relied on. Examples are shown for Android; the same approach applies to iOS and React Native (see [Other platforms](#other-platforms)).

This guide pairs with the **bd-instrumentation** agent skill, which can perform and verify the removal. For agents, the checklist below is the specification:

> "Remove all bitdrift SDK instrumentation from this app following CLEANUP_GUIDE.md in reverse order (Step 14 → Step 1). Report what was deleted and verify the project still builds."

---

## When to use this guide

- **Return to baseline** to test the app without bitdrift instrumentation.
- **Cleanly evaluate** bitdrift, then revert before deciding to adopt.
- **Roll back** an experimental integration.

---

## Cleanup checklist — 14 categories in reverse

Work from the bottom of the instrumentation guide up. Each entry names what to remove; follow the linked instrumentation step to see exactly what was added.

| Order | Remove | What comes out | Reference |
|-------|--------|----------------|-----------|
| 1 | **Log framework forwarding** | The custom `Timber.Tree` / logging-bridge that forwards existing logs to bitdrift | [Step 14](INSTRUMENTATION_GUIDE.md#14-forward-your-existing-log-framework) |
| 2 | **New-session calls** | All `Logger.startNewSession()` calls and the field re-application that followed them | [Step 13](INSTRUMENTATION_GUIDE.md#13-new-session-on-user-logout-or-journey-reset) |
| 3 | **Symbol upload** | `bdUpload*` task usage and any manual `bd debug-files` upload scripts/CI steps | [Step 12](INSTRUMENTATION_GUIDE.md#12-upload-symbol-files-for-readable-crash-stacks) |
| 4 | **Device identification** | `Logger.createTemporaryDeviceCode()`, `Logger.sessionUrl`, and the `supportlog` field/toggle UI | [Step 11](INSTRUMENTATION_GUIDE.md#11-implement-device-identification-for-support) |
| 5 | **Custom spans** | All `Logger.startSpan()`, `span.end()`, and `Logger.trackSpan()` calls | [Step 10](INSTRUMENTATION_GUIDE.md#10-measure-operations-with-custom-spans) |
| 6 | **App launch TTI** | `Logger.logAppLaunchTTI()` and the process-start timestamp it relied on | [Step 9](INSTRUMENTATION_GUIDE.md#9-report-app-launch-tti) |
| 7 | **Global fields** | All `Logger.addField()` / `Logger.removeField()` calls and any `FieldProvider` implementations | [Step 8](INSTRUMENTATION_GUIDE.md#8-attach-global-fields) |
| 8 | **Custom logs** | All `Logger.logInfo/logWarning/logError/logDebug` calls | [Step 7](INSTRUMENTATION_GUIDE.md#7-emit-structured-custom-logs) |
| 9 | **Network capture** | `CaptureOkHttpEventListenerFactory` from every `OkHttpClient`, plus all `x-capture-path-template` headers | [Step 6](INSTRUMENTATION_GUIDE.md#6-capture-network-traffic) |
| 10 | **Entity ID** | All `Logger.setEntityId()` calls | [Step 5](INSTRUMENTATION_GUIDE.md#5-identify-users-with-entity-id) |
| 11 | **Screen views** | `Logger.logScreenView()` calls and any centralized navigation listener / screen-name mapping added for it | [Step 4](INSTRUMENTATION_GUIDE.md#4-instrument-screen-views) |
| 12 | **Session strategy** | The `sessionStrategy` argument (removed together with the `Logger.start()` call below) | [Step 3](INSTRUMENTATION_GUIDE.md#3-confirm-session-strategy) |
| 13 | **Logger initialization** | The `Logger.start()` call in `Application.onCreate()` and all `io.bitdrift.capture` imports | [Step 2](INSTRUMENTATION_GUIDE.md#2-start-the-logger) |
| 14 | **SDK dependency** | `io.bitdrift:capture` from `app/build.gradle.kts` and `io.bitdrift.capture-plugin` from the root build file | [Step 1](INSTRUMENTATION_GUIDE.md#1-add-the-dependency) |

> **Order matters.** Remove call sites (spans, logs, fields, screen views, network) *before* removing `Logger.start()` and the dependency, so the project keeps compiling at each step. The dependency comes out last.

After removing the dependency: run `./gradlew clean`, re-sync Gradle, and rebuild.

---

## Verify the cleanup

**Command-line — these should all return nothing:**

```bash
# No bitdrift imports
grep -r "io.bitdrift" app/src/

# No bitdrift Logger calls (exclude the platform logger)
grep -rE "Logger\.(start|log|addField|removeField|setEntityId|startSpan|trackSpan|startNewSession|createTemporaryDeviceCode)" app/src/

# No path templates or span helpers left behind
grep -rE "x-capture-path-template|CaptureOkHttpEventListenerFactory" app/src/
```

**Build:**

```bash
./gradlew clean && ./gradlew build   # should succeed with no bitdrift references
```

**Checklist** (top of the instrumentation guide is the foundation — confirm it's gone last):

- [ ] Log framework bridge removed (14)
- [ ] No `startNewSession()` calls (13)
- [ ] Symbol upload tasks/scripts removed (12)
- [ ] Device code + `supportlog` field removed (11)
- [ ] No span creation/ending calls (10)
- [ ] No TTI tracking (9)
- [ ] No `addField`/`removeField`/`FieldProvider` (8)
- [ ] No custom log calls (7)
- [ ] No OkHttp listener or path templates (6)
- [ ] No `setEntityId` calls (5)
- [ ] No screen-view logging or navigation listener (4)
- [ ] No `sessionStrategy` / `Logger.start()` (3, 2)
- [ ] SDK dependency and Gradle plugin removed (1)
- [ ] Project rebuilds successfully
- [ ] No remaining `io.bitdrift` references anywhere in the codebase

---

## Other platforms

The same reverse-order removal applies on **iOS** and **React Native** — only the surfaces differ:

- **iOS:** remove `.enableIntegrations([...])` from `Logger.start()` (network + log forwarding), the `Logger.start(...)` call in `@main init()` / `didFinishLaunchingWithOptions`, the `import Capture`, and the SPM/CocoaPods dependency. Drop any dSYM upload build-phase or `bd debug-files upload` step.
- **React Native:** remove the top-level `@bitdrift/react-native` calls (`init`, `info`/`warning`/`error`, `addField`, `logScreenView`, …), the `import` from `@bitdrift/react-native`, the `npm` package, and the Hermes source-map upload step. Then `pod install` (iOS) to drop the native pod; Android de-autolinks on package removal.

Use **bd-docs** to confirm the exact symbols for the SDK version in use before deleting call sites.

---

## Reference

- **[INSTRUMENTATION_GUIDE.md](INSTRUMENTATION_GUIDE.md)** — what each of the 14 categories adds (use it to identify what to remove).
