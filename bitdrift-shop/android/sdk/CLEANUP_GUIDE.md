# Bitdrift Cleanup Guide (Android)

Remove all bitdrift Capture SDK instrumentation and return the app to baseline state.

This guide is designed to be used **with agent skills**, following the same pattern as [README.md](README.md).

**For humans:** Read each step's **Skill prompt** to understand what to remove and why. Use code references to verify what was added before deletion.

**For agents:** Use the cleanup checklist as a specification. Example prompt:

> "Remove all bitdrift SDK instrumentation from the Android app. Follow the cleanup checklist: use the bd-instrumentation skill to remove steps 13–8 (remove logging, spans, global fields), then report what was deleted and what remains."

**Skills available:**
- **bd-instrumentation** — Remove SDK components, revert Logger calls, restore to baseline
- **mobile-dev** — Android development cleanup, Gradle configuration revert

---

## Cleanup Checklist — 13 Steps in Reverse

Follow these steps in **reverse order** (Step 13 down to Step 1) to systematically remove instrumentation.

---

## Step 13: Remove New Session Calls

**Skill prompt:** "Remove all Logger.startNewSession() calls from the app"

**Why remove it:** Restoring the app to its original session lifecycle behavior.

**What it removes:** Session boundary reset calls that were added to align with logout/reset events.

**Code reference:** [Step 13: New Session on User Logout or Journey Reset](INSTRUMENTATION_GUIDE.md#13-new-session-on-user-logout-or-journey-reset)

---

## Step 12: Remove Symbol Upload Tasks

**Skill prompt:** "Remove ProGuard mapping upload configuration from the Gradle plugin"

**Why remove it:** Cleanup of symbol file management (typically automatic via the plugin from Step 1).

**What it removes:** Symbol upload task configuration and any manual upload scripts.

**Code reference:** [Step 12: Upload Symbol Files for Readable Crash Stacks](INSTRUMENTATION_GUIDE.md#12-upload-symbol-files-for-readable-crash-stacks)

---

## Step 11: Remove Device Identification Code

**Skill prompt:** "Remove Logger.createTemporaryDeviceCode() and supportlog field from screens"

**Why remove it:** Eliminates device code generation and support log filtering features.

**What it removes:** Device code UI, support log toggle, and all associated Logger calls.

**Code reference:** [Step 11: Implement Device Identification for Support](INSTRUMENTATION_GUIDE.md#11-implement-device-identification-for-support)

---

## Step 10: Remove Custom Spans

**Skill prompt:** "Remove all Logger.startSpan(), span.end(), and Logger.trackSpan() calls from the app"

**Why remove it:** Eliminates custom operation duration tracking and span hierarchy.

**What it removes:** All span creation, span ending, span result callbacks, and span field tracking.

**Code reference:** [Step 10: Measure Operations with Custom Spans](INSTRUMENTATION_GUIDE.md#10-measure-operations-with-custom-spans)

---

## Step 9: Remove App Launch TTI Tracking

**Skill prompt:** "Remove Logger.logAppLaunchTTI() calls and process start timing from the Application and MainActivity"

**Why remove it:** Eliminates app startup time telemetry collection.

**What it removes:** TTI measurement infrastructure, SystemClock.uptimeMillis() tracking for app launch.

**Code reference:** [Step 9: Report App Launch TTI](INSTRUMENTATION_GUIDE.md#9-report-app-launch-tti)

---

## Step 8: Remove Global Fields

**Skill prompt:** "Remove all Logger.addField() and Logger.removeField() calls from the app"

**Why remove it:** Eliminates session-wide context fields and cohort tagging.

**What it removes:** Global field assignments for user_id, app_variant, custom fields, and all removeField calls.

**Code reference:** [Step 8: Attach Global Fields](INSTRUMENTATION_GUIDE.md#8-attach-global-fields)

---

## Step 7: Remove Structured Custom Logs

**Skill prompt:** "Remove all Logger.logInfo(), Logger.logError(), Logger.logWarning(), Logger.logDebug() calls from the app"

**Why remove it:** Eliminates custom event logging and structured log signals.

**What it removes:** All Logger.log* calls, error logging with throwables, field-based logging.

**Code reference:** [Step 7: Emit Structured Custom Logs](INSTRUMENTATION_GUIDE.md#7-emit-structured-custom-logs)

---

## Step 6: Remove Network Traffic Capture

**Skill prompt:** "Remove CaptureOkHttpEventListenerFactory from OkHttpClient and delete all x-capture-path-template headers"

**Why remove it:** Eliminates automatic network call instrumentation.

**What it removes:** OkHttp event listener factory, path template headers, network telemetry collection.

**Code reference:** [Step 6: Capture Network Traffic](INSTRUMENTATION_GUIDE.md#6-capture-network-traffic)

---

## Step 5: Remove Entity ID Tracking

**Skill prompt:** "Remove all Logger.setEntityId() calls from the app"

**Why remove it:** Eliminates user identification and Entities dashboard integration.

**What it removes:** Entity ID assignment calls that tag sessions with user/device identifiers.

**Code reference:** [Step 5: Identify Users with Entity ID](INSTRUMENTATION_GUIDE.md#5-identify-users-with-entity-id)

---

## Step 4: Remove Screen View Tracking

**Skill prompt:** "Remove Logger.logScreenView() calls and the NavController.OnDestinationChangedListener from MainActivity"

**Why remove it:** Eliminates screen navigation telemetry and User Journey Sankey population.

**What it removes:** Screen view logging, NavController listener, screen name mapping, ScreenLogger wrapper.

**Code reference:** [Step 4: Instrument Screen Views](INSTRUMENTATION_GUIDE.md#4-instrument-screen-views)

---

## Step 3: Confirm Session Strategy Removal

**Skill prompt:** "Remove SessionStrategy.Fixed() parameter from Logger.start() call"

**Why remove it:** Restores default session behavior (cleanup of explicit session strategy configuration).

**What it removes:** Session strategy parameter from Logger initialization.

**Code reference:** [Step 3: Confirm Session Strategy](INSTRUMENTATION_GUIDE.md#3-confirm-session-strategy)

---

## Step 2: Remove Logger Initialization

**Skill prompt:** "Remove Logger.start() call from Application.onCreate() and delete bitdrift Logger imports"

**Why remove it:** Stops SDK initialization and all automatic telemetry collection.

**What it removes:** Logger.start() call, all bitdrift.capture imports, Session strategy configuration.

**Code reference:** [Step 2: Start the Logger in Application.onCreate()](INSTRUMENTATION_GUIDE.md#2-start-the-logger)

---

## Step 1: Remove the SDK Dependency

**Skill prompt:** "Remove io.bitdrift:capture dependency and io.bitdrift.capture-plugin from build.gradle files, then run gradle clean and rebuild"

**Why remove it:** Eliminates the SDK library and Gradle plugin entirely.

**What it removes:** SDK dependency from app/build.gradle.kts, Gradle plugin from build.gradle.kts (project root).

**Code reference:** [Step 1: Add the Capture SDK Dependency](INSTRUMENTATION_GUIDE.md#1-add-the-dependency)

**Final steps:**
- Run `./gradlew clean` to clear the build cache
- Sync Gradle in Android Studio
- Rebuild the project

---

## Verify Cleanup — 13-Step Checklist

After removing all 13 steps, verify the app is back to baseline:

**Command-line verification:**
```bash
# Should return no bitdrift imports
grep -r "io.bitdrift.capture" app/src/

# Should return no bitdrift Logger calls
grep -r "Logger\." app/src/ | grep -v "logcat\|android\.util"

# Should return no span references
grep -r "startSpan\|trackSpan" app/src/
```

**Build verification:**
```bash
./gradlew clean
./gradlew build
# Should build without errors
```

**Manual checklist:**
- [ ] Step 13: No `startNewSession` calls
- [ ] Step 12: Symbol upload tasks removed
- [ ] Step 11: Device code and support log removed
- [ ] Step 10: No span creation/ending calls
- [ ] Step 9: No TTI tracking
- [ ] Step 8: No global field calls (addField/removeField)
- [ ] Step 7: No custom logging calls (logInfo/logError)
- [ ] Step 6: No OkHttp listener or path templates
- [ ] Step 5: No Entity ID calls
- [ ] Step 4: No screen view logging or NavController listener
- [ ] Step 3: No session strategy in Logger
- [ ] Step 2: No Logger.start() call
- [ ] Step 1: No SDK dependency or plugin
- [ ] Project rebuilds successfully
- [ ] No remaining bitdrift imports in codebase

---

## When to Use This Guide

- **Return to baseline:** Test the app without bitdrift instrumentation
- **Switch observability tools:** Cleanly evaluate bitdrift before committing
- **Revert instrumentation:** Restore to original state if instrumentation was experimental

**For agent-driven cleanup:** Use a skill prompt like:

> "Remove all bitdrift SDK instrumentation from the Android app following CLEANUP_GUIDE.md steps 13–1. Report what was deleted and verify the project rebuilds."

---

## Reference

- **[INSTRUMENTATION_GUIDE.md](INSTRUMENTATION_GUIDE.md)** — What each of the 13 steps adds (use to understand what to remove)
- **[README.md](README.md)** — Entry point and instrumentation checklist (reverse of this guide)
- **[README-refs.md](README-refs.md)** — App reference data
