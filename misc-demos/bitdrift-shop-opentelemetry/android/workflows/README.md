# bitdrift-shop-opentelemetry Workflows

Workflow JSON for the bitdrift-shop-opentelemetry Android demo app. Scoped to `ai.bitdrift.oteldemo`.

## `capture-all-sessions.json` — Capture All Sessions (Demo)

Guarantees a full session capture for every session of this app — fires on `APP_LAUNCH` with no
sampling and no other match conditions, so 100% of sessions get flushed. Deploy this **before**
running the live demo, not mid-demo: a capture workflow only sees sessions that start *after* it
deploys, so anything already running when you deploy it won't be captured.

Deploy it with the script (idempotent — reuses the existing workflow instead of creating a
duplicate if you run it more than once):

```bash
./scripts/deploy-capture-workflow.sh
```

Or by hand:

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
