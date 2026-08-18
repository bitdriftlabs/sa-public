# iOS workflows

Deploy with the **bd CLI**. Each file is a `Workflow` payload:

```bash
../scripts/deploy-workflows.sh          # all of them, plus the dashboard
```

Or one at a time:

```bash
bd workflow create bd-shop-15-crashes-by-final-screen.json   # returns an id
bd workflow deploy <id>
```

Editing a deployed workflow requires `stop` → `update` → `deploy`; its config is
locked while live. Metadata-only changes (titles, descriptions, display mode) are
the exception and apply without a stop — worth preferring, since a stop/deploy
cycle resets the evaluation window and discards accumulated data.

| File | What it shows |
|------|---------------|
| `bd-shop-13-ios-app-hang-sessions.json` | App Hang (`0x8BADF00D`) count, with session capture on each |
| `bd-shop-14-ios-paths-to-force-quit.json` | Sankey: launch → screens → force quit |
| `bd-shop-15-crashes-by-final-screen.json` | Crashes grouped by the screen the user was last on |
| `bd-shop-17-ios-journey-vs-crashes.json` | Journey Sankey to `Confirmation` + 7-step funnel + crash counts by screen |
| `bd-shop-18-ios-crashes-by-last-screen-live.json` | Ripsaw: reads the screen trail off the crash report itself |
| `bd-shop-19-ios-crash-terminal-sankey.json` | Sankey ending at the crash — needs `sessionStrategy: .activityBased()` |
| `bd-shop-20-ios-cold-start-span-timings.json` | Cold-start span waterfall (`app_cold_start` root + `sdk_init`/`scene_render`/`state_restore` children): per-phase P50/P90/P99 histograms, plus one chart comparing all three phases |

## Journey-to-crash Sankey: it depends on session strategy

This was investigated twice with opposite conclusions, so state both, with the
evidence attached, rather than pick one.

**Under `sessionStrategy: .fixed()`, it never closes.** Measured on device
(`capture-ios` 0.23.11):

| Flow shape | Result |
|---|---|
| `APP_IOS_BUILT_IN_CRASH` alone | 37 matches |
| screen view → crash (2 steps) | **0** |
| crash → screen view (2 steps) | **0** |
| screen view → loop → crash (3 steps) | **0** |
| screen view → loop → `Confirmation` (3 steps) | 122 matches, 22 links |

Multi-step flows and looping Sankeys work fine on iOS; per-journey
`startNewSession()` is fine too. The one thing that doesn't work under
`.fixed()` is `APP_IOS_BUILT_IN_CRASH` (and `APP_IOS_BUILT_IN_ANR`) advancing a
multi-step flow, in either direction.

**Under `sessionStrategy: .activityBased()`, it closes.** `bd-shop-19`, same
account: `flow-closed-count` = 26, matching the Sankey's incoming-crash links
exactly (`Browse→Crash` 4 + `ProductDetail→Crash` 11 + `CheckoutGuest→Crash`
11 = 26). Mechanism, confirmed on a captured session: the SDK's fatal issue
handler reads the crash report on the *next* launch and replays it into the
timeline carrying a snapshot of the global-field state from the moment of
death. Under `.fixed()` that replay lands in a brand-new session, so the flow
that was mid-progress when the process died can't see it. Under
`.activityBased()` the relaunch resumes the *same* session (if it lands
within `inactivityThresholdMins`, 30 min default), so the replay arrives
inside the session whose `Welcome → loop` steps already matched, and the flow
closes.

**The dependency this creates:** if the relaunch is slow enough to age the
session out, you're back to the `.fixed()`-shaped empty Sankey with no visible
change in config. Test your own relaunch latency against the threshold before
promising this unconditionally. Untested altogether: whether the same
mechanism closes a flow for `APP_IOS_BUILT_IN_ANR` (hangs) — plausible, same
fatal-issue-handler family, not verified.

`bd-shop-18` doesn't have this dependency at all — the app keeps a 5-deep
shift register of screens as **global fields**, which ride onto the crash
report regardless of session strategy or relaunch timing, and a Ripsaw
`issue_match` script reads the path straight off the report. No flow involved.
Use the Sankey (`bd-shop-19`) to see *where journeys branch and how many
crash at each point*; use the register (`bd-shop-18`) when every crash needs
attribution regardless of timing.

Two consequences worth knowing about `bd-shop-18`:

- Crash classes the OS reports on the *next* launch (often `EXC_CRASH`) arrive
  in a fresh process with no global fields set, and attribute as `unknown`.
  Expected, not a broken register — the error cross-tab shows which is which.
- A Sankey whose terminal is unreachable renders empty rather than erroring.
  `bd-shop-17`'s `journey-sankey` needs `Confirmation`, which a crash run never
  reaches — so during a crash run that particular Sankey is blank by design,
  not broken. `bd-shop-19` is the one that stays populated during crashes.

For crashes, `bd-shop-15` and `bd-shop-18` attribute with **fields instead of a
flow** — see [misc-demos/lastscreenbeforecrash](../../../misc-demos/lastscreenbeforecrash)
for the generic write-up.

## Cold-start span timings (`bd-shop-20`)

`app_cold_start` is a root span opened at the very end of `CaptureBridge.start()`,
back-dated (`startTimeInterval`) to the true kernel process-start time so its
duration is directly comparable to `CaptureBridge.timeToInteractive`. Three
child spans (`sdk_init`, `scene_render`, `state_restore`) nest under it via
`parentSpanID`, so a single cold start renders as one waterfall in Timeline
instead of four unrelated flat spans — see `ColdStartSpans` in
`CaptureBridge.swift`.

Each span's *end* log (not start) is what workflow matches on — it's the one
carrying `_duration_ms`. Matching all three phases in one step and grouping the
Histogram action by `_span_name` (`hist-phases-compared`) gives one chart with
a line per phase; matching each phase in its own step gives that phase its own
full P50/P90/P99 breakdown instead of a single collapsed percentile.

Like every workflow here, this one only evaluates sessions that start *after*
it's deployed — an already-running app instance's cold-start spans (e.g. the
one that was live while you were writing/testing this) won't retroactively
show up. Relaunch the app once after deploying to get a session the new
workflow can actually see.

A dashboard composes its 5 charts into one view:
[`dashboards/ios-cold-start-span-timings.dashboard.json`](../dashboards/ios-cold-start-span-timings.dashboard.json)
(live at workflow id `0pTX`, dashboard id `1rik5G13l_cOcZMr_Oxka`). Deploy it
with:

```bash
bd dashboard create --request-file ../dashboards/ios-cold-start-span-timings.dashboard.json
```

The committed payload's chart components reference `0pTX` directly — if you
redeploy `bd-shop-20` to a different account, edit every `workflow_id` in the
dashboard file first (same caveat `deploy-workflows.sh` works around for the
guided crash dashboard above, just not automated here since this dashboard
only has one workflow behind it).
