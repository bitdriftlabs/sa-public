# bitdrift-shop-opentelemetry Workflows

Workflow JSON for the bitdrift-shop-opentelemetry Android demo app. Scoped to `ai.bitdrift.oteldemo`.

## `capture-all-sessions.json` — Capture All Sessions (Demo)

Captures every purchase journey **and starts backend tracing** for it, which is what this demo
showcases. It fires on the `Welcome` screen view (the app calls `Logger.startNewSession()` per
journey) rather than on app launch, with no sampling: the `capture-all-sessions` rule flushes the
session and `trace-all-sessions` (`start_tracing_rule`) propagates trace context on its network
calls. Locked to `ai.bitdrift.oteldemo` (`platform_targets`). Deploy it **before** the live demo: a
workflow only sees sessions that start *after* it deploys. To trigger on a different step, change
the `_screen_name` in the `session-start` match.

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

## Metric workflows + dashboard

Two metric workflows and a dashboard (`../dashboards/otel-telescope-store.dashboard.json`) give the
app a spread of metric shapes — counts, a latency histogram with percentiles, rates, grouped series.
Chart titles and units live in `chart-metadata/<name>.chart.json`. Deploy everything (idempotent;
the dashboard is replaced):

```bash
cd android && ./scripts/deploy-metric-workflows.sh
```

| Workflow | Chart (`rule_id`) | Shape |
|----------|-------------------|-------|
| `otel-api-metrics.json` | `api-request-count` | count, by `_path_template` |
| | `api-latency` | histogram of `_duration_ms` (p50/p90/p99), by `_path_template` |
| | `api-errors` | count where `_result != success`, by `_path_template` |
| | `api-error-rate` | rate: errors / requests |
| `otel-journey-health.json` | `journeys-started` | count of `journey_started` logs (one per journey) |
| | `journeys-completed` | count of `Confirmation` screen views (manual and simulated), by `ff_variant` |
| | `journey-completion-rate` | rate: `Confirmation` views / `journey_started` |
| | `payment-failures-by-method` | count of `payment_failed`, by `payment_method` |
| | `checkout-and-cart-failures` | `checkout_failed` (by `checkout_type`) and `cart_failed` counts |
| | `screen-views` | count of screen views, by `_screen_name` |

Generate traffic with the in-app **Sim 5 / Sim 10 / Sim ∞** buttons.
