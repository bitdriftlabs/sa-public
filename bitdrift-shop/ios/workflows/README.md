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
| `bd-shop-17-ios-journey-vs-crashes.json` | Journey Sankey + 7-step funnel + crash-by-screen + visit denominator |
| `bd-shop-18-ios-crashes-by-last-screen-live.json` | Ripsaw: reads the screen trail off the crash report itself |

## Why there is no "journey to crash" Sankey

Measured on device 2026-08-12 (`capture-ios` 0.23.11), not inferred:

| Flow shape | Result |
|---|---|
| `APP_IOS_BUILT_IN_CRASH` alone | 37 matches |
| screen view → crash (2 steps) | **0** |
| crash → screen view (2 steps) | **0** |
| screen view → loop → crash (3 steps) | **0** |
| screen view → loop → `Confirmation` (3 steps) | 122 matches, 22 Sankey links |

Multi-step flows and looping Sankeys work fine on iOS. Per-journey
`startNewSession()` is also fine — a 3-step Sankey was verified populating with
rotation on. The single blocker is that `APP_IOS_BUILT_IN_CRASH` and
`APP_IOS_BUILT_IN_ANR` match only as a standalone first step and never advance a
multi-step flow, in either direction. So a crash cannot be a Sankey terminal.

`bd-shop-18` is the way around it: the app keeps a 5-deep shift register of
screens as **global fields**, global fields ride onto the crash report, and a
Ripsaw `issue_match` script reads the path straight off the report. No flow
involved, so none of the above applies.

Two consequences worth knowing:

- Crash classes the OS reports on the *next* launch (often `EXC_CRASH`) arrive in
  a fresh process with no global fields set, and attribute as `unknown`. Expected,
  not a broken register — `bd-shop-18`'s error cross-tab shows which is which.
- A Sankey whose terminal is unreachable renders empty rather than erroring. That
  is why `bd-shop-17` carries a second Sankey ending at `CheckoutGuest`: during a
  crash run the journey never reaches `Confirmation`, so the conversion Sankey is
  blank exactly when crashes are happening.


For crashes, attribution is done with **fields instead of a flow** — see
`bd-shop-15`, and [misc-demos/lastscreenbeforecrash](../../../misc-demos/lastscreenbeforecrash)
for the generic write-up.
