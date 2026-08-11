# iOS workflows

Deploy with the **bd CLI**. Each file is a `Workflow` payload:

```bash
bd workflow create bd-shop-15-crashes-by-final-screen.json   # returns an id
bd workflow deploy <id>
```

| File | What it shows |
|------|---------------|
| `bd-shop-13-ios-app-hang-sessions.json` | App Hang (`0x8BADF00D`) count, with session capture on each |
| `bd-shop-14-ios-paths-to-force-quit.json` | Sankey: launch → screens → force quit |
| `bd-shop-15-crashes-by-final-screen.json` | Crashes grouped by the screen the user was last on |

## Why there is no "journey to crash" Sankey

The obvious workflow — screen views looping into a crash step — cannot complete
for the crash classes that matter most on iOS.

A flow only matches events it can see **in one session**. App hangs and
out-of-memory kills produce no log at the moment they happen; the OS reports them
on the **next launch**, in a new session. The simulator also calls
`startNewSession()` per journey. So the screen views and the termination end up in
different sessions and the final step never fires — the Sankey silently stays
empty rather than erroring.

`bd-shop-14` works because force-quit journeys deliberately keep the startup
session, so `APP_TERMINATION` lands alongside the screen views that preceded it.

For crashes, attribution is done with **fields instead of a flow** — see
`bd-shop-15`, and [misc-demos/lastscreenbeforecrash](../../../misc-demos/lastscreenbeforecrash)
for the generic write-up.
