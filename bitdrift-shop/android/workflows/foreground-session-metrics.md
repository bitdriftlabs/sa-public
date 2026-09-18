# Foreground Session Metrics — Session Count / Duration / Crash Rate (Work in Process)

**Status: work in process.** The count and crash-rate workflows (`bd-shop-13`/`15`) are
validated and working. The duration workflow's underlying approach (a manually-instrumented
span) is also validated, but the broader investigation into whether the same metric can be
derived from a pure two-step correlated flow (no app-code span) is unresolved — see the
"Duration" section below for what was tried and what's still open.

Three workflows — `bd-shop-13-foreground-session-count.json`,
`bd-shop-14-foreground-session-duration.json`, and
`bd-shop-15-crash-rate-per-foreground.json` — that measure a foreground episode as its own
concept (session count, session duration, crash rate per foreground session — the raw
crashes ÷ sessions ratio, not its complement, so it rises when reliability worsens; see
`bd-shop-15`'s own description below for the exact computation). Session count and
crash rate are pure workflow configuration against logs the Capture SDK already emits on
its own; session duration needs one small manual span, for reasons covered below.

## Why

A "session" here means a foreground episode: it starts when the app comes to the
foreground and ends when it backgrounds. bitdrift's own `session_id` is a different,
inactivity-timeout-based concept that survives backgrounding (and in this demo app is
additionally rotated every 60s while the Metrics demo runs — see
[metric-demo.md](metric-demo.md#session-handling) — so it's a poor stand-in for "foreground
episode" even before considering the semantic mismatch). These three workflows measure the
foreground episode directly, as its own concept, without touching `session_id` or the SDK's
session strategy.

Full background on the two definitions and why they diverge is in the PRD
(`sessionmetrics/PRD - Session-Based Workflow Metrics.docx`, Appendix A).

## The instrumentation

**Count and rate (`bd-shop-13`/`15`) — zero app code.** The Capture SDK already logs every
foreground/background transition on its own: on Android it emits a plain `LogType.LIFECYCLE`
log with body `"AppStart"` on foreground entry and `"AppStop"` on backgrounding (on by
default, gated by the `client_feature.android.application_lifecycle_reporting` remote-config
flag). iOS has the same mechanism under different names (`SceneWillEnterFG`/`SceneDidEnterBG`).

- **Session count** (`bd-shop-13`) — Count chart on `AppStart` (Android) OR
  `SceneWillEnterFG` (iOS), so this one's cross-platform. One increment per foreground
  episode.
- **Crash rate per foreground** (`bd-shop-15`, Android-only — its BDRL crash-attribution
  program hasn't been adapted to an iOS-equivalent crash-context field) — Rate chart:
  numerator is crashes where
  `app_metrics.running_state == "foreground"` (the same condition as
  `bd-shop-06-crash-foreground.json`), denominator is the `AppStart` count from `bd-shop-13`.
  Cross-flow numerator/denominator referencing, proven to work by
  `bd-shop-10-attribution-rate.json`. Background crashes are deliberately excluded from the
  numerator — they can't be attributed to a foreground episode that never started. This is
  the raw crashes ÷ sessions ratio — it moves in the same direction as crash volume (up when
  reliability worsens), **not** its complement. Computing the complement would need a
  numerator of crash-free sessions, which isn't directly available as a countable event here.

**Duration (`bd-shop-14`) — one manual span.** The obvious zero-app-code approach is a
`measure_time_rule` (`RuleMeasureTime`) computing elapsed time between an `AppStart` and the
following `AppStop` in a two-step flow. That was tried and dropped: at real cycling volume,
the bitdrift workflow debugger showed the flow's `AppStop` step permanently stuck at 0 matches
while `AppStart` matched every single time — the two-step correlated match never actually
completed, for reasons not visible from the CLI/schema (no per-device active-run
introspection exists to debug further). Raising `max_active_runs` and adding a timeout
`exit_condition` didn't fix it.

Instead, `AppLifecycleCallbacks.kt` wraps the foreground interval in a `Span` named
`foreground_session` (started in `onActivityStarted`, ended in `onActivityStopped` — the
same activity-counter boundary most mobile-agent SDKs use for this concept). A span's end log carries
`_duration_ms` on itself, so `bd-shop-14` is a single-step match on the span-end log with a
plain field reference — no cross-log correlation, no flow-instance bookkeeping, same shape as
`bd-shop-04-span-durations.json`. This is the one place these workflows aren't pure
zero-app-code configuration, and that's a deliberate trade for reliability, not an oversight.

`bd-shop-14` renders two charts off that same span-end match: a P50/P90/P99 histogram, and
an `average_count` time series (`foreground-session-duration-average`) as a single trending
line — added because a customer found the histogram harder to read at a glance than one
number that moves.

**Cross-platform: `bd-shop-13` and `bd-shop-14`, but not `bd-shop-15`.** The iOS app
(`BitdriftShopApp.swift`) emits the identical `foreground_session` span from its `scenePhase`
handling, so `bd-shop-14` charts both platforms' session duration on one line/histogram with
no per-platform matcher needed. `bd-shop-13` matches `AppStart` (Android) OR
`SceneWillEnterFG` (iOS), so it's cross-platform too. `bd-shop-15` is still Android-only: its
denominator is the same `AppStart` count, but its BDRL crash-attribution program hasn't been
adapted to an iOS-equivalent crash-context field.

## Deploy

```bash
WORKFLOW_ID=$(bd workflow create workflows/bd-shop-13-foreground-session-count.json \
  --chart-metadata-file workflows/chart-metadata/bd-shop-13-foreground-session-count.chart.json \
  -ojson --jq '.id' -r)
bd workflow deploy "$WORKFLOW_ID"

WORKFLOW_ID=$(bd workflow create workflows/bd-shop-14-foreground-session-duration.json \
  --chart-metadata-file workflows/chart-metadata/bd-shop-14-foreground-session-duration.chart.json \
  -ojson --jq '.id' -r)
bd workflow deploy "$WORKFLOW_ID"

WORKFLOW_ID=$(bd workflow create workflows/bd-shop-15-crash-rate-per-foreground.json \
  --chart-metadata-file workflows/chart-metadata/bd-shop-15-crash-rate-per-foreground.chart.json \
  -ojson --jq '.id' -r)
bd workflow deploy "$WORKFLOW_ID"
```

## Generating data to exercise it

1. Run the app on the emulator (README.md Quick Start Step 2). Each launch is already one
   foreground episode.
2. Cycle the app to/from the background a handful of times to generate more than one
   session — either home-button it from the emulator UI, or run
   `./scripts/foreground-cycle.sh` (cycles forever by default, Ctrl-C to stop; pass
   `-N` for exactly N cycles, e.g. `-10`; `FOREGROUND_SECONDS`/`BACKGROUND_SECONDS`
   env vars tune the dwell time). This stays external to the app on purpose: an in-app
   version that backgrounds itself and then self-resumes on a timer was tried and
   dropped, because Android's background-activity-launch policy blocks a
   backgrounded app from bringing itself back to the foreground (confirmed via
   logcat: `Background activity launch blocked! goo.gle/android-bal`) — `adb`'s
   `am start` isn't subject to that restriction, so the cycling has to be driven
   from outside the app. The iOS app has the equivalent
   `../ios/scripts/foreground-cycle.sh` (same `-N`/env-var UX), which drives
   `bd-shop-14` specifically since that's the cross-platform workflow.
3. Run `./scripts/watchdog.sh`, then use Crash Loop (Advanced screen) for a few minutes.
   `maybeFireCrash()` already gives each crash a 50% chance of firing in the background via
   `moveTaskToBack`, so this naturally produces both foreground and background crashes to
   check the rate against.
4. Pull the charts and sanity-check:
   ```bash
   bd workflow charts <bd-shop-13 ID> -ojson --last 1h --jq '.'
   bd workflow charts <bd-shop-14 ID> -ojson --last 1h --jq '.'
   bd workflow charts <bd-shop-15 ID> -ojson --last 1h --jq '.'
   ```
   The session count should match the number of foreground entries from steps 1–2, the
   duration histogram should show samples for each, and the crash rate should track the
   ratio of foreground crashes to sessions — cross-check individual crashes' `crash_context`
   field the same way `foreground-background-crashes.md#cross-checking-against-real-data`
   already recommends for `bd-shop-06`/`07`.
