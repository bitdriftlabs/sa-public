# Sample evaluation readout — bitdrift-shop (Android)

**Status: partial.** This is a worked example of [Step 20's](../INSTRUMENTATION_GUIDE.md#20-generate-the-evaluation-readout)
output — a criterion-by-criterion, evidence-backed readout — built from what's actually been
verified live against `ai.bitdrift.shop` so far. It is **not complete**: the CUJ/dashboard pass
(Step 19's second half) hasn't been run yet. Sections below are marked ✅ Verified or
⏳ Pending accordingly.

The point of showing it partial is that this is what an honest mid-POC readout looks like — every
row states what was actually confirmed and how, and the gaps are named rather than smoothed over.
A readout where every row is green on day three is not a readout.

App: `ai.bitdrift.shop` (Android) · SDK 0.23.10 · Date: 2026-08-17

| ID | Category | Status | Evidence |
|----|----------|--------|----------|
| SC-1 | Event Tracking (p50/p90/p99) | ⏳ Pending | Spans exist (`journey`, `checkout`, `score_products`) and `bd-shop-04` (span histograms) is now LIVE (`hy3N`) — not yet confirmed against fresh span data. |
| SC-2 | Network Monitoring | ✅ Automatic | OkHttp auto-instrumentation live since initial app instrumentation; Instant Insights Network tab populated (`o4BA`, `gELc`, `esfA` charts confirmed live in account audit). |
| SC-3 | Crash Detection | ✅ Verified (classification) / ⏳ Pending (fresh-data confirmation) | Two drifted crash-attribution workflows fixed (`Xutd` blocking-thread, `Z7ED` vendor-SDK — see [BDRL examples](crash-workflow-bdrl-examples.md)); 4 more workflows newly deployed (`dAYb`, `7bNh`, `PwPo`, `yccO`); alert `657` added on the enriched crash-breakdown workflow (`robk`). All confirmed **LIVE** via `bd workflow list`. Not yet confirmed against a fresh crash — historical baseline is ~6/day, no crash occurred during the fix session. |
| SC-4 | Memory Monitoring | ✅ Automatic | Memory-pressure level captured automatically on every crash since SDK 0.23.1 (used directly inside the blocking-thread BDRL script above); Instant Insights Resources tab live. |
| SC-5 | Debugging (ad-hoc capture) | ✅ Automatic | Entities feature live (`user_id`/entity ID set per simulated user); Record Next Online available, not exercised in this pass. |
| SC-6 | Session Management | ✅ Automatic | Fixed session strategy confirmed via app instrumentation; Instant Insights App Opens (`DKPe`) confirms sessions landing. |
| SC-7 | Insights & Visualization (2–3 dashboards) | ⏳ Pending | Only 1 dashboard exists today (`bd-shop-12` metric grouping). The 3 curated dashboards (Stability / Business-UX / Entities-Support) called for in Step 19 have not been built, though the component chart IDs are collected and ready to compose. |
| SC-8 | Log Forwarding & Integration | ✅ Automatic | Structured logs (`checkout_started`, `payment_completed`, etc.) confirmed flowing via Logs by Level (`csaK`) chart, burst-tested during a Sim 10 run (32 → 802 logs/20min). |
| SC-9 | Session Replay | Not evaluated this pass | No specific check run. |
| SC-10 | Visual Performance (jank) | ✅ Automatic (feature-flag-gated) | `bd-shop-11`/`11b` slow-rendering workflows already LIVE with a firing alert (`537`) during this session. |
| SC-11 | Customer Support | ⏳ Pending | Entities exist but no dedicated Entities-Support dashboard has been built yet (part of the Step 19 dashboard pass). |
| SC-12 | Web views | Not applicable to this app | bitdrift-shop doesn't embed WebViews; see guide Step 6 for the general solution (Android GA / iOS experimental). |

## What would complete this readout

1. Generate real traffic to confirm SC-1/SC-3's workflows populate with fresh data, not just
   structural correctness.
2. Finish the bd-cuj phases for checkout to produce the SC-1/SC-7 funnel/Sankey/SLO artifacts.
3. Build the 3 POC dashboards to close out SC-7 and SC-11 with actual portal links/screenshots.

Once done, replace the ⏳ Pending rows above with the same evidence format as SC-3/SC-4
(workflow IDs, chart IDs, portal links) and this becomes a complete, screenshot-backed
evaluation readout matching a real POC's Phase 3 milestone deliverable.
