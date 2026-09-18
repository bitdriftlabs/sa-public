# Session Metrics Demo

**Work in process.** Three deployable bitdrift workflows that measure session-based
metrics — session count, session duration, and crash-free-session rate — plus the
one piece of manual instrumentation needed to support them. Originally built and
validated against bitdrift's own `bitdrift-shop` demo apps (see `../android/` and
`../ios/`); this folder is the portable, app-agnostic version meant to be copied into
any customer's own bitdrift org.

Full background on why these are their own concept — separate from bitdrift's
`session_id`, which is an inactivity-timeout session, not a foreground episode — is in
the PRD (`sessionmetrics/PRD - Session-Based Workflow Metrics.docx`, Appendix A).

## What's here

```
workflows/
  bd-shop-13-foreground-session-count.json        # Session count
  bd-shop-14-foreground-session-duration.json     # Session duration
  bd-shop-15-crash-rate-per-foreground.json       # Crash-free-session rate
  chart-metadata/
    bd-shop-13-foreground-session-count.chart.json
    bd-shop-14-foreground-session-duration.chart.json
    bd-shop-15-crash-rate-per-foreground.chart.json
instrument-foreground-session-span.md             # The one manual span, needed for duration only
```

## The three workflows

| Workflow | Matches on | Platforms | What it charts |
|----------|-----------|-----------|-----------------|
| `bd-shop-13-foreground-session-count.json` **(WIP)** | SDK-automatic `AppStart` (Android) or `SceneWillEnterFG` (iOS) log | Android + iOS | Count of foreground episodes |
| `bd-shop-14-foreground-session-duration.json` **(WIP)** | `foreground_session` span end, `_duration_ms` | Android + iOS | Foreground-episode duration — P50/P90/P99 histogram plus a single-value average-duration line |
| `bd-shop-15-crash-rate-per-foreground.json` **(WIP)** | issue-match BDRL (`app_metrics.running_state == "foreground"`) ÷ `AppStart` count | Android only | Crashes ÷ foreground sessions |

**Count and rate (`13`/`15`) — zero app code.** The Capture SDK already logs every
foreground/background transition on its own — Android emits `AppStart`/`AppStop`,
iOS emits `SceneWillEnterFG`/`SceneDidEnterBG` (on by default; Android's is gated by
the `client_feature.android.application_lifecycle_reporting` remote-config flag).
`bd-shop-13` matches both platforms' automatic log; `bd-shop-15` is Android-only for
now, since it also needs `AppStart` specifically as its denominator and its BDRL
program hasn't been adapted to an iOS-equivalent crash-context field.

**Duration (`bd-shop-14`) — one manual span.** A `measure_time_rule` correlating
`AppStart`→`AppStop` across a two-step flow was tried and dropped: at real
cycling volume the workflow debugger showed the second step permanently stuck at 0
matches despite the first step matching every time, for reasons not visible from the
CLI/schema. Instead, wrap the foreground interval in a span named
`foreground_session` — see **[instrument-foreground-session-span.md](instrument-foreground-session-span.md)**
for the exact Android/iOS code. A span's end log carries `_duration_ms` on itself, so
this is a single-step match with no cross-log correlation, and it's the same span
name on both platforms, which is why `bd-shop-14` is the only one of the three that's
cross-platform out of the box.

## Deploy

Adjust `platform_targets` in each workflow file first if you want to scope to a
specific `app_id` rather than matching every app on the platform (the files ship with
empty `apps: []`, i.e. "all apps").

```bash
cd workflows

WORKFLOW_ID=$(bd workflow create bd-shop-13-foreground-session-count.json \
  --chart-metadata-file chart-metadata/bd-shop-13-foreground-session-count.chart.json \
  -ojson --jq '.id' -r)
bd workflow deploy "$WORKFLOW_ID"

WORKFLOW_ID=$(bd workflow create bd-shop-14-foreground-session-duration.json \
  --chart-metadata-file chart-metadata/bd-shop-14-foreground-session-duration.chart.json \
  -ojson --jq '.id' -r)
bd workflow deploy "$WORKFLOW_ID"

WORKFLOW_ID=$(bd workflow create bd-shop-15-crash-rate-per-foreground.json \
  --chart-metadata-file chart-metadata/bd-shop-15-crash-rate-per-foreground.chart.json \
  -ojson --jq '.id' -r)
bd workflow deploy "$WORKFLOW_ID"
```

`bd-shop-14` needs the `foreground_session` span in place before it will show data;
`bd-shop-13`/`15` need no app changes at all.

## Generating data to exercise it

Background/foreground the app a handful of times (each launch is one session; cycling
to/from the background a few more times generates more than one). On Android, driving
this from `adb` (e.g. `am start`/home-button) rather than in-app self-resume avoids
Android's background-activity-launch restriction, which blocks a backgrounded app from
bringing itself back to the foreground. Trigger a few crashes while foregrounded and
backgrounded to exercise `bd-shop-15`'s rate calculation. Then pull the charts:

```bash
bd workflow charts <bd-shop-13 ID> -ojson --last 1h --jq '.'
bd workflow charts <bd-shop-14 ID> -ojson --last 1h --jq '.'
bd workflow charts <bd-shop-15 ID> -ojson --last 1h --jq '.'
```

Session count should match your foreground-episode count, the duration
histogram/average should show a sample per episode, and the crash rate should track
foreground crashes ÷ sessions.
