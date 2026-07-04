# bitdrift-shop Workflows

Ready-to-deploy workflow JSON files for the bitdrift-shop Android demo app. Each workflow is scoped to `ai.bitdrift.shop` and uses log events, spans, and feature flag exposures instrumented in the app.

## Deploy

Always pass the matching `--chart-metadata-file` so each panel gets a descriptive
title — without it, every chart shows as the generic "workflow chart".

```bash
bd workflow create workflows/bd-shop-01-checkout-funnel.json \
  --chart-metadata-file workflows/chart-metadata/bd-shop-01-checkout-funnel.chart.json
bd workflow create workflows/bd-shop-02-payment-errors.json \
  --chart-metadata-file workflows/chart-metadata/bd-shop-02-payment-errors.chart.json
bd workflow create workflows/bd-shop-03-crash-analytics.json \
  --chart-metadata-file workflows/chart-metadata/bd-shop-03-crash-analytics.chart.json
bd workflow create workflows/bd-shop-04-span-durations.json \
  --chart-metadata-file workflows/chart-metadata/bd-shop-04-span-durations.chart.json
bd workflow create workflows/bd-shop-05-anr-force-quit.json \
  --chart-metadata-file workflows/chart-metadata/bd-shop-05-anr-force-quit.chart.json
bd workflow create workflows/bd-shop-06-crash-foreground.json \
  --chart-metadata-file workflows/chart-metadata/bd-shop-06-crash-foreground.chart.json
bd workflow create workflows/bd-shop-07-crash-background.json \
  --chart-metadata-file workflows/chart-metadata/bd-shop-07-crash-background.chart.json
```

To rename panels on an already-deployed workflow without recreating it, pass both the
workflow file and its chart metadata to `update`:

```bash
bd workflow update --workflow-id <ID> \
  --workflow-file workflows/bd-shop-01-checkout-funnel.json \
  --chart-metadata-file workflows/chart-metadata/bd-shop-01-checkout-funnel.chart.json
```

Chart titles live in `chart-metadata/*.chart.json` — a `[PerRuleChartMetadata]` array mapping
each action's `rule_id` to a `ChartMetadata` (`title`, optional `summary`, and the **required**
`metadata_type`: `metric_chart_metadata` / `sankey_chart_metadata` / `flush_chart_metadata`).

**Reading `issue_match` BDRL scripts** (`bd-shop-03`, `bd-shop-06`, `bd-shop-07`):
`IssueMatch` is a filter — every report runs through the script, and `abort` is the only way
to reject one. Whatever does *not* hit `abort` "matches" and fires the workflow's actions.
So these scripts only ever define what to *reject*; the chart automatically counts the
complement. See [foreground-background-crashes.md](foreground-background-crashes.md) for a
worked example of why that reads backwards if you're not expecting it.

## Workflows

| File | Name | What it shows |
|------|------|---------------|
| `bd-shop-01-checkout-funnel.json` | Checkout Funnel & A/B Comparison | add_to_cart → checkout_started → payment_completed drop-off; checkout duration histogram; completions and abandons grouped by `checkout_flow` and `cart_abandon_rate` feature flag variants |
| `bd-shop-02-payment-errors.json` | Payment & Checkout Errors | payment_failed count by `payment_method` (card/apple_pay/paypal/android_pay); failures by `payment_ui` variant; checkout_failed by checkout type (guest/signin); session capture on payment failure |
| `bd-shop-03-crash-analytics.json` | Crash Distribution & Session Capture | JVM crash count total; breakdown by `crash_category` (null_pointer / stack_overflow / oom) via BDRL; session capture on crash for post-mortem log review |
| `bd-shop-04-span-durations.json` | Span Duration Histograms | `_duration_ms` histograms for `journey`, `checkout`, and `product_discovery` spans; checkout duration grouped by `checkout_flow` variant to compare A/B performance impact |
| `bd-shop-05-anr-force-quit.json` | ANR & Force-Quit Tracking | Built-in ANR count (device-unique); ANR termination count; injected ANR and force-quit counts grouped by `anr_a`/`force_quit` variants; session capture on ANR/force-quit |
| `bd-shop-06-crash-foreground.json` | Crashes in Foreground | Count of crashes where `app_metrics.running_state == "foreground"` via BDRL. See [foreground-background-crashes.md](foreground-background-crashes.md). |
| `bd-shop-07-crash-background.json` | Crashes in Background | Count of crashes where `app_metrics.running_state != "foreground"` via BDRL — Android has no dedicated "background" state, so this is everything that isn't foreground. See [foreground-background-crashes.md](foreground-background-crashes.md). |

See [foreground-background-crashes.md](foreground-background-crashes.md) for why these two
are separate workflows, the platform constraint that shapes both BDRL scripts, and how to
cross-check the split against real crash data.

## Event reference

These workflows match the following log events emitted by the app:

| Event | Source | Key fields |
|-------|--------|------------|
| `add_to_cart` | Screens.kt | `product_id`, `source_screen` |
| `checkout_started` | Screens.kt | `checkout_type` |
| `payment_completed` | Screens.kt | `payment_method`, `order_id` |
| `payment_failed` | Screens.kt | `payment_method` |
| `checkout_failed` | Screens.kt | `checkout_type` |
| `cart_abandoned` | SimulationManager.kt | — |
| `checkout_abandoned` | SimulationManager.kt | `checkout_type` |
| `guest_anr_injected` | SimulationManager.kt | `force_quit_enabled` |
| `force_quit_injected` | SimulationManager.kt | `force_quit_screen` |

Span names: `journey`, `checkout`, `product_discovery` — all emit `_duration_ms` and `_span_type: "end"`.

Feature flag keys used in `group_by`: `checkout_flow`, `payment_ui`, `cart_abandon_rate`, `anr_a`, `force_quit`.
