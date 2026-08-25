# Worked examples

Concrete artifacts from running this guide's newer sections against a real app, instead of only
prose prompts.

## Portability contract

These are templates, not a fixed workflow bundle. Never copy app IDs, workflow IDs, screen names,
span names, backend hosts, or crash matchers into another app. First run Step 19 and substitute
the target app's exact observed values. A portable implementation must fail the discovery gate
when a required call site or signal is missing; it must not manufacture data to make a chart
non-empty.

## Validation note

Before deploying any example, list existing account workflows and verify their deployed
definitions. `LIVE` does not prove that the app emits the matched signal. For Android
non-crash validation, run from the Android app directory, reset persisted fault-injection state,
build/install the debug APK, explicitly enable the persisted infinite-simulation flag, launch the
app, and monitor ordinary logs, screen views, network events, and business failures:

```bash
cd /path/to/android-app
./scripts/check-demo-state.sh -s emulator-5554 --reset
./gradlew :app:assembleDebug :app:installDebug
adb -s emulator-5554 shell run-as ai.bitdrift.shop sh -c \
  'mkdir -p shared_prefs && printf %s "<?xml version=\"1.0\" encoding=\"utf-8\" standalone=\"yes\" ?><map><boolean name=\"active\" value=\"true\" /></map>" > shared_prefs/auto_infinite.xml'
adb -s emulator-5554 shell am start -n ai.bitdrift.shop/.MainActivity
```

Do not enable Crash Loop, ANR-A, or Force-Quit for this pass. Record workflow status and whether
charts have non-empty series; do not create duplicates when artifacts already exist. For chart
validation, start with `bd workflow charts <ID> --last 1h` and inspect the returned target scope;
only add `--platform`/`--app-id` after confirming those dimensions match the session data.

For iOS simulator runs, use `xcrun simctl boot`/`install`/`launch` with crash, hang, and force-quit
flags disabled. Point the debug app's ignored local config at `127.0.0.1` when the backend runs on
the host; an old LAN address can make the loop appear instrumented while network signals fail.

| File | What it is |
|------|-----------|
| [crash-workflow-bdrl-examples.md](crash-workflow-bdrl-examples.md) | Two real Ripsaw/BDRL scripts — lock-contention thread attribution and vendor-SDK stack-trace attribution — annotated for reuse, with the cardinality guardrail that matters when copying them. |
| [evaluation-readout-sample.md](evaluation-readout-sample.md) | A real, deliberately partial historical evaluation readout (Step 21): useful for evidence format, but not a v1.4 portfolio-compliant run. |
| [cuj-funnel-pitfalls.md](cuj-funnel-pitfalls.md) | Two mistakes that produce a silently-empty funnel — both hit for real while building one — and how to catch them in minutes instead of days. |
| [journey-span-instrumentation.md](journey-span-instrumentation.md) | What spanning a whole user journey (Steps 4/9/10) produces, and the eight ways it goes quietly wrong — every one hit for real on iOS and Android. |
| [post-instrumentation-signal-catalog.md](post-instrumentation-signal-catalog.md) | The **bd-post-instrumentation** Step 19 evidence template: observed sessions, exact matcher values, fields, network paths, and Issue shape before account-side configuration. |
| [post-instrumentation-build-readout.md](post-instrumentation-build-readout.md) | The **bd-observability-portfolio** Step 20 template: a complete workflow/dashboard portfolio, replacement panels for unavailable optional signals, and post-deploy evidence. |
