# Sample evaluation readout — bitdrift-shop (Android)

A worked example of [Step 20's](../INSTRUMENTATION_GUIDE.md#20-generate-the-evaluation-readout)
output: a criterion-by-criterion readout where every row states what was actually confirmed and
how. Rows that were verified say so and name the artifact; rows that weren't say that instead. A
readout where every row is green on day one isn't a readout — the honest gaps are what make the
rest credible.

App: `ai.bitdrift.shop` (Android) · SDK 0.23.10 · Date: 2026-08-17
Traffic during validation: ~60 simulated checkout journeys against a local demo backend.

| ID | Category | Status | Evidence |
|----|----------|--------|----------|
| SC-1 | Event Tracking (p50/p90/p99) | ✅ Verified | Key-step duration histogram on the checkout funnel (`MMiD` → `histogram_key_step`) returning real percentile series — p10 observed in the 80–145ms range over the traffic window. Span-duration histograms also live (`hy3N`: journey / checkout / product_discovery). |
| SC-2 | Network Monitoring | ✅ Verified | OkHttp auto-instrumentation. Purpose-built RED workflow `GEok` returning live data across all 3 series (request count, success rate, latency), grouped by `_path_template`. Plus Instant Insights Network tab (`o4BA`, `gELc`, `esfA`). |
| SC-3 | Crash Detection | ✅ Verified (config) | Two crash-attribution workflows found **deployed with an empty `issue_match`** — silently matching every JVM crash — and fixed with their real BDRL (`Xutd` blocking-thread, `Z7ED` vendor-SDK; scripts in [crash-workflow-bdrl-examples.md](crash-workflow-bdrl-examples.md)). Four more deployed: `dAYb`, `7bNh`, `PwPo`, `yccO`. Alert `657` on `robk`. 30-day history on `robk` shows 156 classified crashes (~6/day). |
| SC-4 | Memory Monitoring | ✅ Verified | Memory-pressure captured automatically on every crash (SDK 0.23.1+) and consumed directly inside the blocking-thread BDRL to tag contention crashes occurring under low memory. |
| SC-5 | Debugging (ad-hoc capture) | ✅ Deployed | Session capture wired to the slow-key-step condition (`MMiD` → `capture_slow_key_step`, 100/day cap). 0 captures so far, which is the correct result — no journey exceeded the threshold. |
| SC-6 | Session Management | ✅ Verified | Sessions landing; confirmed via Instant Insights App Opens (`DKPe`) and by the SDK ring buffer initializing on each launch (`bd_buffer ... opening ring buffer file`). |
| SC-7 | Insights & Visualization | ✅ Verified | Two purpose-built dashboards created: **Checkout CUJ** (`5TnlhLhE7WLfqYO6BLu_y`) — Sankey + funnel + completion rate + key-step duration, plus a Network tab with the full RED set; and **POC — Stability** (`oL5WAVzuuVUUEgqe05itG`) — 8 crash panels spanning totals, type, fg/bg split, attribution rate, blocking thread, vendor SDK, and the enriched breakdown. |
| SC-8 | Log Forwarding & Integration | ✅ Verified | Structured logs flowing (`checkout_started`, `payment_completed`, …) via Logs by Level (`csaK`); burst-verified at 32 → 802 logs/20min under simulated load. |
| SC-9 | Session Replay | ⏳ Not evaluated | Out of scope for this pass; no check run. Guide Step 17 covers enablement. |
| SC-10 | Visual Performance (jank) | ✅ Verified | Slow-rendering workflows `bd-shop-11`/`11b` LIVE, with alert `537` observed firing during the session. |
| SC-11 | Customer Support | ⏳ Partial | Entity IDs set per simulated user and Entities usable for per-user lookup, but no dedicated Support dashboard was built — the Stability and CUJ dashboards cover the diagnostic need for now. |
| SC-12 | Web views | n/a | This app embeds no WebViews. General solution in guide Step 6 (Android GA, iOS experimental as of 0.23.11). |

## Journey monitoring detail (SC-1 / SC-7)

| Artifact | ID | Status |
|---|---|---|
| Checkout path discovery (Sankey) | `5uKY` | **LIVE, returning data** — real nodes observed: Cart, CheckoutGuest, CheckoutSignIn, Confirmation |
| Checkout funnel (+ key-step timing, slow capture) | `MMiD` | **LIVE, returning data** — `27 → 27 → 27 → 27 → 2` |
| Checkout completion rate (ungrouped, for SLO) | `8S4s` | **LIVE, returning data** |
| Checkout network RED | `GEok` | **LIVE, returning data** (3/3 series) |
| Completion-rate SLO alert (90% / 30d, MWMBR) | `658` | Created. Target is a 0.90 starting default, to revisit against 30d of real data |

**The funnel is the headline finding.** `27 → 27 → 27 → 27 → 2`: every session that opened a
product reached a payment screen, and only 2 of 27 reached Confirmation. A ~7% completion rate with
zero attrition in the first four steps points at the payment-confirmation step specifically, not at
discovery or cart friction — which is exactly the kind of conclusion a funnel is supposed to hand
you on day one. (Worth stressing for POC purposes: this is a demo app with deliberately seeded
failure behaviour, so the number is a property of the simulation, not a real product defect.)

Caveats stated plainly rather than smoothed over:

- **No notification group exists on this account**, so alerts `657` and `658` will fire and appear
  in the UI but route nowhere. Creating one is a prerequisite before this counts as real alerting.
- **The network workflow is scoped to `10.0.2.2`**, the emulator loopback to the local demo
  backend. A real POC substitutes the production API hostname; the workflow shape is otherwise
  production-ready.
- The funnel's slow-capture threshold is still a placeholder **5s**. It should be reset to ~1.5×
  the observed p95 once enough duration data exists — which is also why the p95 alert was
  deliberately *not* created yet: setting a threshold before seeing a baseline just manufactures
  false positives.

## How the gaps close

1. Set the key-step p95 alert and correct the 5s capture threshold from the observed percentiles
   (the histogram now has data, so this is a matter of reading p95 and applying ~1.5×).
2. Create a notification group so both alerts route somewhere.
3. Add a Support-oriented dashboard view if SC-11 needs to be fully green.
4. Point the network workflow at a production hostname when moving off the demo backend.
