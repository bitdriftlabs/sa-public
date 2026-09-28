# bitdrift-shop-opentelemetry-ios Workflows

Workflow JSON for the bitdrift-shop-opentelemetry iOS demo app. Scoped to `ai.bitdrift.oteldemo.ios`.
Mirrors [android/workflows/README.md](../../android/workflows/README.md), scoped to the iOS bundle
ID instead.

## `capture-all-sessions.json` — Capture All Sessions (Demo)

Guarantees a full session capture *and* active trace propagation for every session of this app —
fires on `APP_LAUNCH` with no sampling and no other match conditions, so 100% of sessions get
flushed with tracing active. Deploy this **before** running the live demo, not mid-demo: a capture
workflow only sees sessions that start *after* it deploys, so anything already running when you
deploy it won't be captured.

Without this deployed, `Logger.isTracingActive` stays `false` for every session — the SDK still
captures screen views and plain logs, but never injects trace headers or exports OTel spans (see
[../README.md#otel-span-export-experimental](../README.md#otel-span-export-experimental)), since
both depend on tracing being active.

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
bd workflow list -ojson --jq '[.items[] | select(.workflow.name | contains("bitdrift-shop-opentelemetry-ios")) | {id: .workflow.id, state: .workflow.state}]'
```
