# Demo: Feature-Flag-Gated Slow Rendering

Two workflows — one primary, one illustrative — that show a slow-rendering regression shipped
behind a feature flag, detected with zero app instrumentation, and diagnosed back to the
offending code using nothing but what bitdrift shows.

## Why

- The bug is real, working Kotlin — it type-checks, compiles, produces correct
  recommendations, and throws no exception, crash, or failed assertion.
- An AI assistant reviewing the diff that introduces it ("add a personalized recommendations
  section, gated behind `recommendations_v2`") has nothing to flag — the code does what the PR
  description says.
- The defect is a *runtime performance characteristic*, not a logic error:
  `RecommendationEngine.scoreProducts()` runs a Levenshtein-similarity pass over full product
  profiles directly in a composable body, unmemoized, so it re-executes on every recomposition.
- You cannot see that from a diff — only from watching frames render.
- bitdrift's Capture SDK already watches every frame on-device and classifies slow/frozen ones
  automatically — no manual instrumentation, no custom span, no opt-in.

## What's wired

| Piece | Where |
|---|---|
| Feature flag | `recommendations_v2` key, `ff_recommendations_v2` field — set in `SimulationManager.setVariant()` |
| UI toggle | **Rec v2** button, Advanced screen (`simulationManager.recommendationsV2Enabled`) |
| The trap | `RecommendationEngine.scoreProducts()` (`RecommendationEngine.kt`) — Levenshtein similarity over each product's **full JSON profile** (not just the description — this is what makes it slow enough to matter), called synchronously and unmemoized in the composable body of `BrowseScreen` and `ProductDetailScreen` |
| Detection (primary) | bitdrift's built-in Android dropped-frame detection (OOTB `DROPPED_FRAME`) — no app code |
| Detection (secondary, illustrative) | `Logger.trackSpan("score_products", ...)` wrapping the same call sites, tagged with an explicit `screen_name` field |

The repo intentionally ships the trap, not the fix. Fixing it live, from what bitdrift shows, is
the demo.

## The two workflows

**`bd-shop-11-slow-rendering.json` — primary.** Matches bitdrift's OOTB Android frame detection:

```json
{ "match_id": "slow-render", "ootb_match": { "android_condition": "DROPPED_FRAME",
  "generic_match": { "base_matcher": { "log_field": "_frame_issue_type", "operator": "EQUAL", "string_value": "Slow" } } } }
```

Filtered to `_frame_issue_type == "Slow"` (16ms–700ms) rather than all dropped frames, so it
doesn't blend in unrelated Frozen/ANR events from elsewhere in the app. Four actions: total
count (alert target), count by `recommendations_v2` exposure, duration histogram by exposure,
count by `_screen_name`. **Zero app instrumentation required.**

**`bd-shop-11b-slow-rendering-manual-span.json` — secondary, no alert.** Same four-chart shape,
matched on the custom `score_products` span instead
(`_span_name == "score_products" AND _span_type == "end" AND _duration_ms >= 16`). Kept only as
a worked example of what manual instrumentation looks like when OOTB detection isn't an option
(e.g. **iOS** — `DROPPED_FRAME` is Android-only; bitdrift has no frame-render-jank OOTB
condition for iOS today, backed by AndroidX's `JankStats`).

**Why both exist:** the manual span only ever fires on the two screens we happened to wrap. The
OOTB primary catches jank system-wide — in practice it also catches jank bleeding into whatever
screen gets visited right after (`Reviews`, `Cart`, `Wishlist` in the simulated journey), which
is a more honest picture of user impact. That breadth is the whole point of using OOTB over
per-screen spans, which is why it's primary and the span is just the comparison example.

## Setup

1. Check for leftover fault-injection state from a previous demo (Crash Loop/ANR-A/Force-Quit
   flags persist across restarts by design):
   ```bash
   ./scripts/check-demo-state.sh --reset
   ```
2. Backend + app running — see the main [README.md](README.md) Quick Start (Steps 0–2).
3. Deploy the primary workflow, capturing its ID:
   ```bash
   WORKFLOW_ID=$(bd workflow create workflows/bd-shop-11-slow-rendering.json \
     --chart-metadata-file workflows/chart-metadata/bd-shop-11-slow-rendering.chart.json \
     -ojson --jq '.id' -r)
   bd workflow deploy "$WORKFLOW_ID"
   ```
4. Attach the alert:
   ```bash
   AGGREGATED_ACTION_ID=$(bd workflow describe "$WORKFLOW_ID" -o json --jq \
     '.workflow.actions[] | select(.rule_id=="slow-frame-count") | .metric_chart_rule.time_series[0].aggregated_id' -r)
   bd workflow alert upsert "$WORKFLOW_ID" slow-frame-count "$AGGREGATED_ACTION_ID" \
     --name "bd-shop | Slow Rendering | Dropped Frames" \
     --type basic --threshold 3 --threshold-condition above --basic-window 5m \
     --notification "group=<existing-notification-group>,min_interval=5m"
   ```
   `threshold=3` over `5m` is a demo threshold, not a production SLO — tune after the first run.
5. (Optional) Deploy the secondary example, no alert needed:
   ```bash
   bd workflow create workflows/bd-shop-11b-slow-rendering-manual-span.json \
     --chart-metadata-file workflows/chart-metadata/bd-shop-11b-slow-rendering-manual-span.chart.json \
     -ojson --jq '.id' -r | xargs bd workflow deploy
   ```

**A deployed (`LIVE`) workflow rejects rule changes.** To edit either workflow after deploying —
via CLI or the portal — `bd workflow stop <ID>` first, make the edit, then `bd workflow deploy
<ID>` again. Deleting any alert on the workflow first is also required if the edit touches that
chart's action.

## Live trigger script

No manual navigation — the existing simulation loop drives real traffic through the buggy
screens; this just turns the flag on before running it.

1. Launch the app, land on Welcome.
2. Advanced screen → tap **Rec v2** → `ON`. Fires `Logger.setFeatureFlagExposure("recommendations_v2", "enabled")`.
3. Back on Welcome → tap **Sim ∞** (or **Sim 10** for a quick check). Simulated journeys hit
   `ProductDetail` every run and `Browse` on roughly a third — no manual scrolling/tapping needed.
4. Let it run 5–10 minutes to light up the dashboards properly.

**Don't try to eyeball which screen is stuttering while the sim runs** — a full journey flashes
past many unrelated screens too fast to attribute jank by watching. Use the `by-screen` chart;
that's exactly what it's for.

## What lights up in bitdrift

Confirmed on a live run: **59 matches, 100% on `recommendations_v2=enabled`, zero on
`disabled`**, durations clustering ~60–95ms (squarely in Android's "Slow" band, well past the
16ms budget). Screen spread: `ProductDetail` > `Reviews` > `Cart` > `Browse` > `Wishlist` — wider
than just the two instrumented screens, as expected from OOTB's system-wide detection.

- **Count** climbs within minutes of starting Sim ∞.
- **By-exposure** shows two series; `enabled` does all the climbing, `disabled` stays flat — the
  chart that proves the flag caused it, not general app jank.
- **Duration histogram** confirms severity (60–95ms here).
- **By-screen** tells you which screens are actually affected — this is the answer to "which
  screen," not impressions from watching the emulator.
- The alert fires in `/alerting` once the count crosses threshold.

## Diagnosis & fix (the live part — not pre-applied in this repo)

Starting from only what the dashboard showed:

1. **By-exposure** says the flag causes it, not general load.
2. **By-screen** says `ProductDetail`/`Browse` (plus spillover) are affected.
3. If using the secondary span workflow too: the `score_products` span names the exact operation.

That's enough to go straight to `RecommendationEngine.scoreProducts()`'s two call sites in
`Screens.kt` without grepping blind. The fix: move the call off the composable body into a
`LaunchedEffect`, dispatch with `withContext(Dispatchers.Default)`, and store the result in a
`remember`-backed `mutableStateOf` — the same shape already used by every other data-fetch in
that file. Intentionally *not* applied here — running this diagnosis live, from bitdrift's
evidence, is the demo.

## Presentation notes

- Start from the dashboard, not the source. Open `Screens.kt` only after the charts have pointed
  at a screen — that's the narrative.
- Lead with "why didn't AI catch this in review" before showing any chart.
- Business framing: "we shipped a feature flag, and found + attributed a performance regression
  before support tickets showed up." Engineering framing: "zero extra instrumentation — the
  SDK's on-device frame detection did this automatically."
