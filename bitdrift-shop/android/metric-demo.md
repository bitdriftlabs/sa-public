# Demo: Metric Grouping (Synthetic Waveforms + Latency by App Version)

A single toggle button on the **Advanced** screen. Ports the old standalone `metricdemo` app
(waveforms + counter) and adds `metric_work_latency_ms`, a metric built to demo **grouping**
("latency by app version") with a fake `sim_app_version` dimension that auto-rotates across five
values on its own — no manual control needed.

## Setup

1. App running — see main [README.md](README.md) Quick Start: Step 0 (bitdrift credentials) and
   Step 2 (run the app). **Step 1 (start the backend) is not required for this demo** —
   `MetricsDemoManager` only calls the bitdrift `Logger` directly and never touches
   `ApiClient`/the local FastAPI server, so Metrics works standalone even with the backend never
   started.
2. Deploy the workflow:
   ```bash
   WORKFLOW_ID=$(bd workflow create workflows/bd-shop-12-metric-grouping.json \
     --chart-metadata-file workflows/chart-metadata/bd-shop-12-metric-grouping.chart.json \
     -ojson --jq '.id' -r)
   bd workflow deploy "$WORKFLOW_ID"
   ```

## Live trigger script

1. Launch the app → Welcome → **Advanced**.
2. Tap **Metrics** → `ON`. Starts logging `metric_values` once/sec. Starts a new session (and
   rotates one every 60s — see [Session handling](#session-handling)); auto-rotates to a random
   simulated version every 30s (see [Auto-rotation](#auto-rotation)) so all five show up without
   touching anything else.
3. Leave it running ~3–5 min so each of the five versions gets at least one 30s turn.
4. Open **Work Latency by App Version** histogram + average charts in the bitdrift dashboard.
   If a chart looks empty right after toggling **Metrics** on, wait one 60s rotation cycle first.

## What lights up

- **Average chart**: a stepped line, one flat segment per version turn, jumping between
  ~90–340ms as the auto-rotation cycles versions underneath it.
- **Histogram (p50/p90/p99), grouped by `sim_app_version`**: five distributions side by side via
  **Customize Dimensions** — the actual "grouped by app version" answer, with enough series to
  look like a real fleet instead of a three-point toy example.
- **Table view**: same five versions as rows, for numeric side-by-side comparison.

## Presentation notes

- Frame it against: *"one dashboard, metrics grouped by things like work latency by app version."*
- Lead with the histogram, not the average — it shows grouping preserves distribution shape
  (p90/p99), not just a blended average.
- Don't run **Metrics** alongside a shopping-journey demo you need read as one continuous session
  — Metrics rotates the app-wide session (see [Session handling](#session-handling)).
- If CloudWatch cross-validation matters, open with the counter consistency check (below) —
  a concrete, already-explained discrepancy beats an abstract "the two systems agree."

## What's wired

| Piece | Where |
|---|---|
| Metric engine (waveforms + latency) | [`MetricsDemo.kt`](app/src/main/java/ai/bitdrift/shop/MetricsDemo.kt) |
| UI toggle | **Metrics** button, Advanced screen (`MetricsDemoManager`) |
| Simulated dimension | `sim_app_version` field, set via `Logger.addField()` automatically every 30s in the tick loop (same pattern as `app_variant`/`ff_*`) — no manual control, purely automatic |
| Session rotation | `Logger.startNewSession()` on start, then every 60s while running |
| Version auto-rotation | Random pick (shuffled bag, even coverage) every 30s while running — see [Auto-rotation](#auto-rotation) |
| Workflow | [`workflows/bd-shop-12-metric-grouping.json`](workflows/bd-shop-12-metric-grouping.json) |

## Auto-rotation

A histogram/average chart grouped by version only looks like *grouping* once more than one
version's worth of data actually exists — with just one, it's indistinguishable from an ungrouped
chart. Requiring a manual tap through all versions before the chart means anything doesn't scale
past a live narrated demo, so the tick loop auto-rotates on its own: every 30 seconds it draws the
next version from a shuffled bag of all five (refilled and reshuffled once exhausted, so every
version gets even representation instead of a short run happening to land on the same one or two
repeatedly) and re-tags subsequent ticks with it. Left running for a few minutes, this alone
produces a fully populated five-series grouped chart with no interaction required beyond toggling
**Metrics** on.

## Session handling

A workflow only evaluates sessions that started **after** it went live — an already-open session
never retroactively shows up in a newly created/redeployed workflow's charts, even while it's
actively emitting matching events. Confirmed live once: 1000+ `metric_values` events sitting in a
session's raw timeline, correct fields and all, with the workflow chart showing nothing — because
the session had been open since before the workflow was deployed.

Fix: `MetricsDemoManager` calls `Logger.startNewSession()` immediately when **Metrics** is toggled
on, then again every 60s while it runs — so there's always a recent session boundary for whatever
workflow is currently deployed to pick up.

**Trade-off:** this rotates the app-wide session, not just metrics telemetry — avoid running
**Metrics** at the same time as a shopping-journey demo you need as one continuous session
(checkout funnel, journey Sankey, etc.). Consistent with `SimulationManager`, which rotates a
session per simulated journey for the same reason.

## The metric event

Once a second, while **Metrics** is `ON`, one `metric_values` log event:

```kotlin
Logger.logInfo(
    mapOf(
        "metric_sine"            to "%.4f".format(sine),
        "metric_square"          to "%.4f".format(square),
        "metric_sawtooth"        to "%.4f".format(sawtooth),
        "metric_triangle"        to "%.4f".format(triangle),
        "metric_dc"              to "%.4f".format(dc),
        "metric_counter"         to "%.4f".format(counter),
        "metric_work_latency_ms" to "%.2f".format(latency),
    )
) { "metric_values" }
```

`metric_sine` … `metric_counter` are unchanged from the original app (same formulas, 5-min periods).

## Latency by version

| Simulated version | Mean latency | Jitter | Story |
|---|---|---|---|
| `4.0.0` (baseline) | 120ms | ±20ms | Healthy release |
| `4.1.0` (regressed) | 340ms | ±40ms | Perf regression shipped |
| `4.2.0` (fixed) | 140ms | ±20ms | Regression fixed |
| `4.3.0` (minor regression) | 220ms | ±30ms | A smaller regression shipped later |
| `4.4.0` (optimized) | 90ms | ±15ms | An optimization release, faster than baseline |

Tapping **Version** cycles through all five in that order, re-tagging every subsequent tick. The
tick loop separately auto-rotates to a random one of the five every 30 seconds (see
[Auto-rotation](#auto-rotation)) regardless of whether the button is ever tapped.

## The workflow's charts

| Rule ID | Chart type | What it shows |
|---|---|---|
| `metrics-chart` | Line (average) | Five original waveforms, one line each |
| `counter-chart` | Line (count) | CloudWatch consistency check — sum should equal seconds elapsed |
| `work-latency-average` | Line (average), grouped by `sim_app_version` | Mean latency per version |
| `work-latency-histogram` | Histogram, grouped by `sim_app_version` | p50/p90/p99 per version |
| `work-latency-table` | Table, grouped by `sim_app_version` | Same data as per-version rows |

## Dashboard

All five charts above are also composed into a two-tab dashboard —
[`dashboards/bd-shop-01-metric-grouping.json`](dashboards/bd-shop-01-metric-grouping.json) — so a
viewer gets the grouping story and the CloudWatch-comparison story as one curated view instead of
five separate workflow charts. `sim_app_version` is promoted to the dashboard header as a
**Collected Dimension**, so anyone can filter the whole dashboard to a single simulated version
without editing a chart. See [`dashboards/README.md`](dashboards/README.md) for deploy instructions
(one extra step versus a workflow: the dashboard JSON references `bd-shop-12`'s workflow ID, which
has to be resolved before it can be created).

## Theory

**Why a fake field instead of three real app builds?** In a real app this dimension is just the
SDK's built-in `app_version` field, auto-tagged on every log. Reproducing that live in one demo
session would mean building/installing/running three separate APKs. `sim_app_version` fakes the
*dimension*, not the *mechanism* — the workflow groups on a log field the same way it would group
on real `app_version`; it's just populated by a button instead of a build number. Same trade-off as
`app_variant`/`ff_*` elsewhere in this app.

**Why this metric specifically:** grouping is the harder half of "custom metrics" to demo
convincingly — it needs a dimension with more than one real value, and a metric whose shape
actually *differs* across it, or the grouped chart just shows overlapping flat lines.
`metric_work_latency_ms` has three visibly different distributions, one per version, so grouping
by version produces something worth looking at.

**Averages, bitdrift vs. CloudWatch:** bitdrift uses an `average_count` rollup — accumulates a sum
and a count on-device per window, flushes both, and divides them for display. CloudWatch never sees
raw per-second values — the connector exports sum/count as two separate custom metrics, so
reconstructing the average there needs `numerator / denominator`, not either metric alone.

**Bucket-width mismatch:** bitdrift auto-scales bucket size by time range (<4h → 1min, 4–36h →
15min, >36h → 2h); CloudWatch uses a fixed period you set explicitly. Same data can look different
in each system purely from this — a 5-min-period wave looks smoother in a 15-min bitdrift bucket
than a 1-min CloudWatch one. `metric_dc` (flat 5.0) is unaffected at any bucket size, so it's a
good baseline to confirm the export pipeline works before debugging shape differences.

**The counter as a consistency check:** `metric_counter` emits exactly `1.0`/sec, so any N-second
window should read count/sum = N in both systems.

A real observed gap: over 15 min, bitdrift's SUM read 828 vs. CloudWatch's 897 (expected 900), a
~7.7% gap — not data loss. bitdrift's SUM only includes **completed** windows, excluding the
current in-progress one, so a 15-min query systematically misses ~1 of 15 windows (~60 events).
CloudWatch includes the still-open boundary window, so it lands closer to true count. Gap shrinks
with longer windows (~1–2% over 1h, <0.1% over 24h). **Methodology:** compare over 1h+ windows, use
CloudWatch's Sum (not Average), expect ~1–2% residual gap at that scale — a gap well above ~2%
sustained over 1h+ would warrant investigating real event loss.

**CloudWatch export isn't wired by default** — add `connector_export_config` entries under a series
in the chart-metadata file ([Actions > Metric export](https://docs.bitdrift.io/product/workflows/actions#metric-export))
and a `cloudwatch-export` connector (`bd connector upsert cloudwatch ...`) to reproduce the above.
