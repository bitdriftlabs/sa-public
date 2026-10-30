# bitdrift-shop-opentelemetry Workflows

Workflow JSON for the bitdrift-shop-opentelemetry Android demo app. Scoped to `ai.bitdrift.oteldemo`.

## `capture-all-sessions.json` — Capture All Sessions (Demo)

Guarantees a full session capture **and starts backend tracing** for every purchase journey of this
app. It fires on the `Welcome` screen view (the first step of the purchase flow — the app calls
`Logger.startNewSession()` per journey) rather than on app launch, with no sampling and no other match conditions,
so every journey is flushed (`capture-all-sessions` rule) and has trace context propagated on its
network calls (`trace-all-sessions`, a `start_tracing_rule`). Tracing is what this demo shows, so
without this workflow requests aren't traced end to end into the OTel Demo backend. Locked to
`ai.bitdrift.oteldemo` (`platform_targets`), so it never touches other apps. Deploy this **before**
running the live demo, not mid-demo: a workflow only sees sessions that start *after* it deploys, so
anything already running when you deploy it won't be captured. To trigger on a different step, change
the `_screen_name` value in the `session-start` match.

Deploy it with the script (idempotent — reuses the existing workflow instead of creating a
duplicate if you run it more than once):

```bash
cd android && ./scripts/deploy-capture-workflow.sh
```

Or by hand, from the project root:

```bash
bd workflow create workflows/capture-all-sessions.json \
  --metadata-file workflows/capture-all-sessions.metadata.json \
  --deploy
```

**`create` does not deploy by default** — pass `--deploy`, or call `bd workflow deploy <ID>`
separately afterward. Verify state with:

```bash
bd workflow list -ojson --jq '[.items[] | select(.workflow.name | contains("Capture All Sessions")) | {id: .workflow.id, state: .workflow.state}]'
```

Live workflow: [`Q6nI`](https://explorations.bitdrift.io/workflow/Q6nI)

Live workflow: [`Q6nI`](https://explorations.bitdrift.io/workflow/Q6nI)

## `user-journey-sankey.json` — User Journey Paths (Welcome → Confirmation)

Sankey (path-discovery) workflow for the Telescope Store shopper journey. Starts at the `Welcome`
screen view, ends at `Confirmation`, and loops over every screen view in between, extracting
`_screen_name` for the middle nodes — so the chart shows each route shoppers take (Browse, Search,
Featured, ProductDetail, Cart, CheckoutGuest/SignIn, Payment*, ...) and where they drop off.
Scoped to `ai.bitdrift.oteldemo`. It relies only on the SDK's screen-view logging
(`ScreenContainer` -> `Logger.logScreenView`), no extra instrumentation. Like any workflow, it only
sees sessions that start after it deploys.

```bash
cd android && ./scripts/deploy-sankey-workflow.sh
```

Idempotent: reconciles an existing workflow with these files (stopping it first if LIVE) and
redeploys. Or by hand, from the project root:

```bash
bd workflow create workflows/user-journey-sankey.json \
  --metadata-file workflows/user-journey-sankey.metadata.json
bd workflow deploy <ID>
```

To track a different journey, change the `Welcome`/`Confirmation` screen names (match IDs `start`
and `end`) and the matching `fixed` labels in the sankey action.
