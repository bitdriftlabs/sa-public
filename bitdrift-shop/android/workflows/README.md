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
bd workflow create workflows/bd-shop-08-blocking-thread.json \
  --chart-metadata-file workflows/chart-metadata/bd-shop-08-blocking-thread.chart.json
bd workflow create workflows/bd-shop-09-vendor-sdk-attribution.json \
  --chart-metadata-file workflows/chart-metadata/bd-shop-09-vendor-sdk-attribution.chart.json
bd workflow create workflows/bd-shop-10-attribution-rate.json \
  --chart-metadata-file workflows/chart-metadata/bd-shop-10-attribution-rate.chart.json
bd workflow create workflows/bd-shop-11-slow-rendering.json \
  --chart-metadata-file workflows/chart-metadata/bd-shop-11-slow-rendering.chart.json
bd workflow create workflows/bd-shop-11b-slow-rendering-manual-span.json \
  --chart-metadata-file workflows/chart-metadata/bd-shop-11b-slow-rendering-manual-span.chart.json
bd workflow create workflows/bd-shop-12-metric-grouping.json \
  --chart-metadata-file workflows/chart-metadata/bd-shop-12-metric-grouping.chart.json
```

**`create` does not deploy.** A newly created workflow sits in `IDLE` state — it won't
match anything until you also run `bd workflow deploy <ID>` (the ID is in `create`'s
response). Verify with `bd workflow list -ojson --jq '[.items[] | {id: .workflow.id, name:
.workflow.name, state: .workflow.state}]'` — several `IDLE` entries in there are workflows
that were created but never deployed.

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

**Reading `issue_match` BDRL scripts** (`bd-shop-03`, `bd-shop-06` through `bd-shop-10`):
`IssueMatch` is a filter — every report runs through the script, and `abort` is the only way
to reject one. Whatever does *not* hit `abort` "matches" and fires the workflow's actions.
So these scripts only ever define what to *reject*; the chart automatically counts the
complement. See [foreground-background-crashes.md](foreground-background-crashes.md) for a
worked example of why that reads backwards if you're not expecting it.

**Matching a custom log by its name/message — `log_body`, not `log_field`.** A silent-zero-matches
bug that shipped in `bd-shop-02` and `bd-shop-05` (fixed alongside `bd-shop-12`): `Logger.logInfo(fields)
{ "payment_failed" }` sets the log's *body/message*, not a custom field named `message` — the
fields map never contains a key literally called `message`. Matching with
`"generic_match": {"base_matcher": {"log_field": "message", "operator": "EQUAL", "string_value": "payment_failed"}}`
therefore matches nothing, forever, with no error — the workflow deploys fine and just never fires.
The correct matcher for "the log's name/message equals X" is `log_body`, a boolean flag on the same
`base_matcher`, not a field-name lookup:
```json
{ "base_matcher": { "log_body": true, "operator": "EQUAL", "string_value": "payment_failed" } }
```
`log_field: "<name>"` is only for matching an actual key in the fields map (e.g. `checkout_type`,
`_screen_name`, `_span_name` — real emitted fields). Confirmed live: `bd-shop-12`'s workflow chart
stayed empty for ~50 minutes with 1000+ matching events already sitting in the raw session
timeline (`bd timeline logs <session-id>`) before this was caught — an Instant Insight
(`csaK` Logs by Level) confirmed the ingestion pipeline itself was current and healthy the whole
time, which is what pointed at the match rule instead of a platform delay.

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
| `bd-shop-08-blocking-thread.json` | Blocking Thread Attribution | `lock_contention` crash count grouped by `blocking_thread` (`thread_details.threads[].name`), with `blocking_thread_state`/`reporting_thread`/`memory_pressure` as secondary breakdowns. See [advanced-crash-attribution.md](advanced-crash-attribution.md). |
| `bd-shop-09-vendor-sdk-attribution.json` | Vendor SDK Attribution | JVM crash count grouped by `vendor_sdk` (`app_code`/`adsdk`/`analytics_sdk`), detected by searching all stack frames across all errors for `com.adsdk.*`/`com.analytics.fake.*` namespaces. See [advanced-crash-attribution.md](advanced-crash-attribution.md). |
| `bd-shop-10-attribution-rate.json` | Crash Attribution Rate | `rate` chart: % of all crashes attributable to a known blocking thread or vendor SDK, ties bd-shop-08/09 together. See [advanced-crash-attribution.md](advanced-crash-attribution.md). |
| `bd-shop-11-slow-rendering.json` | Slow Rendering (Recommendations v2) | **Primary.** OOTB dropped-frame count (alert target); count/duration split by `recommendations_v2` exposure and by `_screen_name`. Zero app instrumentation. See [../demo-slow-rendering.md](../demo-slow-rendering.md). |
| `bd-shop-11b-slow-rendering-manual-span.json` | Slow Rendering — Manual Span Example | **Secondary/illustrative, no alert.** Same shape, matched on a custom `score_products` span instead of OOTB — shows what manual instrumentation looks like when you need to pinpoint an exact function. See [../demo-slow-rendering.md](../demo-slow-rendering.md). |
| `bd-shop-12-metric-grouping.json` | Metric Grouping | Waveform + counter metrics ported from misc-demos/metricdemo; work-latency average/histogram/table grouped by simulated `sim_app_version` — shows a regression and its fix as a shifted distribution. See [../metric-demo.md](../metric-demo.md). |

See [foreground-background-crashes.md](foreground-background-crashes.md) for why bd-shop-06/07 are
separate workflows, the platform constraint that shapes both BDRL scripts, and how to
cross-check the split against real crash data. See
[advanced-crash-attribution.md](advanced-crash-attribution.md) for bd-shop-08/09/10.

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
| `metric_values` | MetricsDemo.kt | `metric_sine`, `metric_square`, `metric_sawtooth`, `metric_triangle`, `metric_dc`, `metric_counter`, `metric_work_latency_ms` |

Span names: `journey`, `checkout`, `product_discovery` — all emit `_duration_ms` and `_span_type: "end"`. `score_products` (recommendations_v2 flag only) also emits `_duration_ms`. See [Span-timing workflows](#span-timing-workflows-bd-shop-20-through-bd-shop-23) below for the ~18 finer-grained spans added on top of these.

OOTB match used by `bd-shop-11`: `DROPPED_FRAME` / `_frame_issue_type == "Slow"` — bitdrift's built-in Android frame-rendering detection, no app instrumentation required.

Feature flag keys used in `group_by` (`state_value` / `FEATURE_FLAG_EXPOSURE`): `checkout_flow`, `payment_ui`, `cart_abandon_rate`, `anr_a`, `force_quit`, `recommendations_v2`.

`bd-shop-12` groups by `sim_app_version` instead — a plain `Logger.addField()` value, not a feature
flag exposure, so its `group_by` uses `field_key` rather than `state_value`. Use `field_key` for any
regular log/global field; reserve `state_value`/`FEATURE_FLAG_EXPOSURE` for values set via
`Logger.setFeatureFlagExposure()`.

## Span-timing workflows (`bd-shop-20` through `bd-shop-23`)

Granular latency spans throughout the app, beyond the three coarse `journey` /
`product_discovery` / `checkout` spans above. **Numbered to match the iOS app's
`bd-shop-20`–`23` deliberately: the same number is the same purpose on both
platforms, and the span names are identical**, so a chart can compare Android and
iOS directly (filter on `platform` if you need them apart).

| Workflow | Live id | Dashboard | Covers |
|---|---|---|---|
| `bd-shop-20-android-cold-start-span-timings.json` | `RLXS` | [Cold-Start](https://explorations.bitdrift.io/dashboards/cQJTUdHJ3NQsm_H1NVsgf) | `app_cold_start` root + `sdk_init` / `scene_render` / `state_restore` |
| `bd-shop-21-android-screen-load-timings.json` | `vokX` | [Screen Load](https://explorations.bitdrift.io/dashboards/XpcvEcjfYuZU9GdgvYvtG) | 8 spans: 7 screen loads + per-thumbnail `product_image_load` |
| `bd-shop-22-android-journey-subphase-timings.json` | `GfJa` | [Journey Sub-Phase](https://explorations.bitdrift.io/dashboards/TdQHRtJe305Xjz4lEVV4h) | `discovery_fetch`, `product_view`, `wishlist_add`, `cart_assembly`, `checkout.payment`, `checkout.confirmation` |
| `bd-shop-23-android-recommendation-engine-timings.json` | `joJr` | [Recommendation Engine](https://explorations.bitdrift.io/dashboards/b8_b4FFF8xzstrR0b9Psg) | `score_products.parse_catalog` vs `.similarity_pass` |

### Why these don't use the SDK's own `Logger.trackSpan`

`CaptureBridge.trackSpanSuspend` / `trackSpanNested` (in `CaptureBridge.kt`) exist
because the SDK helper has three gaps that all bite here:

1. **No `parentSpanId`.** `Logger.startSpan` accepts one, but `trackSpan` doesn't
   forward it — so nothing wrapped in it can nest under a journey or checkout span.
2. **Not suspend-capable.** Its block is `() -> T`, and every screen-load and
   journey-phase span in this app wraps suspending work.
3. **Maps every throwable to `FAILURE`, including `CancellationException`** — which
   on Android is the common case, not an edge case: `LaunchedEffect(key)` cancels
   whenever the key changes or the composable leaves composition, so ordinary
   scrolling would log a stream of "failed" spans whose partial durations then skew
   every histogram. The wrappers map cancellation to `CANCELED` instead.

### Android-specific notes (vs. the iOS app)

- **No `catalog_serialize` span.** iOS re-serializes the product list locally
  (real CPU work worth isolating); Android fetches the catalog over the network
  instead, so there's nothing local to measure.
- **No `bd-shop-24` (persistence I/O).** iOS spans a UserDefaults write on every
  screen transition and an atomic JSON state-file write. Neither exists here:
  Android's `ScreenLogger.logScreenView` has no shift-register/prefs write, and
  the demo-state file is iOS-only (it exists so `watchdog.sh` can relaunch an app
  that can't relaunch itself — Android uses `AlarmManager`).
- **`wishlist_add` populates normally.** On iOS it's empty whenever the app runs
  in simplified-journey mode, whose fixed path skips Wishlist. Android has no
  simplified mode, so the span is just a probability roll on the one journey.
- **`product_image_load` uses Coil's `onState`** rather than a hand-rolled loader
  (iOS had to replace `AsyncImage` outright, since SwiftUI exposes no load hook).
  Its chart filters out `_result == canceled`, since scrolling produces those
  constantly.
- **Cold-start back-dating needs a clock conversion.** `appStartUptimeMs` is
  `SystemClock.uptimeMillis()` (monotonic), but a custom span start time is fed to
  `LogAttributesOverrides.OccurredAt(occurredAtTimestampMs)` — an *epoch*
  timestamp. `CaptureBridge.processStartEpochMs` converts; passing uptime directly
  would stamp the span's start log in 1970. No iOS equivalent, where the value was
  already a wall-clock `Date`.
- **`sdk_init` is missing on a fresh install's first launch.** It ends ~570ms
  into the process — before the on-device workflow engine has fetched and applied
  its config — so nothing can match it yet, while `scene_render` / `state_restore`
  (ending ~14s in) match fine. From the second launch config is cached and it
  lands normally. A first-launch config-arrival artifact, not a span bug, and it
  affects only the chart: the span is in the Timeline waterfall either way.
- Same session-boundary rule as every other workflow here: they only evaluate
  sessions that start *after* deployment.
