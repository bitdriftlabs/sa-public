# bitdrift-shop Android workflows: what each one matches

Ready-to-deploy workflow JSON files for the bitdrift-shop Android demo app. Each workflow is scoped to `ai.bitdrift.shop` and uses log events, spans, and feature flag exposures instrumented in the app.

## Deploy

See [`../README.md`](../README.md): `tools/bd-deploy.sh ai.bitdrift.shop --apply` creates whatever is missing from the account and leaves the rest alone.

## Workflows

| File | Name | What it shows |
|------|------|---------------|
| `user-journey-sankey.json` | Checkout Funnel & A/B Comparison | add_to_cart → checkout_started → payment_completed drop-off; checkout duration histogram; completions and abandons grouped by `checkout_flow` and `cart_abandon_rate` feature flag variants |
| `payment-errors.json` | Payment & Checkout Errors | payment_failed count by `payment_method` (card/apple_pay/paypal/android_pay); failures by `payment_ui` variant; checkout_failed by checkout type (guest/signin); session capture on payment failure |
| `crash-analytics.json` | Crash Distribution & Session Capture | JVM crash count total; breakdown by `crash_category` (null_pointer / stack_overflow / oom) via BDRL; session capture on crash for post-mortem log review |
| `span-durations.json` | Span Duration Histograms | `_duration_ms` histograms for `journey`, `checkout`, and `product_discovery` spans; checkout duration grouped by `checkout_flow` variant to compare A/B performance impact |
| `anr-force-quit.json` | ANR & Force-Quit Tracking | Built-in ANR count (device-unique); ANR termination count; injected ANR and force-quit counts grouped by `anr_a`/`force_quit` variants; session capture on ANR/force-quit |
| `crash-foreground.json` | Crashes in Foreground | Count of crashes where `app_metrics.running_state == "foreground"` via BDRL. See [foreground-background-crashes.md](foreground-background-crashes.md). |
| `crash-background.json` | Crashes in Background | Count of crashes where `app_metrics.running_state != "foreground"` via BDRL — Android has no dedicated "background" state, so this is everything that isn't foreground. See [foreground-background-crashes.md](foreground-background-crashes.md). |
| `blocking-thread.json` | Blocking Thread Attribution | `lock_contention` crash count grouped by `blocking_thread` (`thread_details.threads[].name`), with `blocking_thread_state`/`reporting_thread`/`memory_pressure` as secondary breakdowns. See [advanced-crash-attribution.md](advanced-crash-attribution.md). |
| `vendor-sdk-attribution.json` | Vendor SDK Attribution | JVM crash count grouped by `vendor_sdk` (`app_code`/`adsdk`/`analytics_sdk`), detected by searching all stack frames across all errors for `com.adsdk.*`/`com.analytics.fake.*` namespaces. See [advanced-crash-attribution.md](advanced-crash-attribution.md). |
| `attribution-rate.json` | Crash Attribution Rate | `rate` chart: % of all crashes attributable to a known blocking thread or vendor SDK, ties bd-shop-08/09 together. See [advanced-crash-attribution.md](advanced-crash-attribution.md). |
| `slow-rendering.json` | Slow Rendering (Recommendations v2) | **Primary.** OOTB dropped-frame count (alert target); count/duration split by `recommendations_v2` exposure and by `_screen_name`. Zero app instrumentation. See [../demo-slow-rendering.md](../demo-slow-rendering.md). |
| `slow-rendering-manual-span.json` | Slow Rendering — Manual Span Example | **Secondary/illustrative, no alert.** Same shape, matched on a custom `score_products` span instead of OOTB — shows what manual instrumentation looks like when you need to pinpoint an exact function. See [../demo-slow-rendering.md](../demo-slow-rendering.md). |
| `metric-grouping.json` | Metric Grouping | Waveform + counter metrics ported from misc-demos/metricdemo; work-latency average/histogram/table grouped by simulated `sim_app_version` — shows a regression and its fix as a shifted distribution. See [../metric-demo.md](../metric-demo.md). |
| `support-sessions.json` | Customer Support Sessions (`cWPC`) | Records support sessions: any log carrying `support=true` flushes the session for full-timeline capture, plus a count chart of those logs. See [Customer Support sessions](#customer-support-sessions-bd-shop-30) below. |
| `feature-flag-sessions.json` | Persistent Feature Flag Sessions | Flushes the session when a non-default persistent flag exposure is active (`express_checkout=enabled`, `product_card_layout=list`, `free_shipping_banner=treatment`), plus a count chart per flag. See [Persistent feature flag sessions](#persistent-feature-flag-sessions-bd-shop-31). |

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
| `cart_abandoned` | spec/journey.yaml | — |
| `checkout_abandoned` | spec/journey.yaml | `checkout_type` |
| `guest_anr_injected` | spec/journey.yaml | `force_quit_enabled` |
| `force_quit_injected` | spec/journey.yaml | `force_quit_screen` |
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
platforms, and the span names are identical**.

To be precise about what that does and doesn't buy: these workflows target the
Android app only, so each chart shows Android data alone. The shared numbering and
span names make the two platforms' configs easy to navigate between, and make a real
cross-platform chart cheap to add — `platform_targets` takes an array, so one
workflow can list both `ai.bitdrift.shop` and `ai.bitdrift.shop.ios` and group its
histogram by the `platform` field. They are deliberately kept separate here because
the platforms' absolute latencies differ enough that merging them ungrouped produces
a bimodal distribution describing neither, and because separate workflows keep each
platform's caveats (below) from bleeding into the other's charts.

| Workflow | Live id | Dashboard | Covers |
|---|---|---|---|
| `android-cold-start-span-timings.json` | `RLXS` | [Cold-Start](https://explorations.bitdrift.io/dashboards/cQJTUdHJ3NQsm_H1NVsgf) | `app_cold_start` root + `sdk_init` / `scene_render` / `state_restore` |
| `android-screen-load-timings.json` | `vokX` | [Screen Load](https://explorations.bitdrift.io/dashboards/XpcvEcjfYuZU9GdgvYvtG) | 8 spans: 7 screen loads + per-thumbnail `product_image_load` |
| `journey-subphase-timings.template.json` | `GfJa` | [Journey Sub-Phase](https://explorations.bitdrift.io/dashboards/TdQHRtJe305Xjz4lEVV4h) | `discovery_fetch`, `product_view`, `wishlist_add`, `cart_assembly`, `checkout.payment`, `checkout.confirmation` |
| `recommendation-engine-timings.template.json` | `joJr` | [Recommendation Engine](https://explorations.bitdrift.io/dashboards/b8_b4FFF8xzstrR0b9Psg) | `score_products.parse_catalog` vs `.similarity_pass` |

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

## Customer Support sessions (`bd-shop-30`)

Lets a support agent get a customer's session recorded by asking them to tap one button.

**In the app:** the **Customer Support** button on the Welcome screen (`SupportMode.kt`,
`WelcomeScreen` in `Screens.kt`) toggles support mode.

- First tap: the button turns green and `Logger.addField("support", "true")` tags every
  subsequent log, span, and network event. The app is used normally (browse, search, checkout);
  every step carries `support=true`.
- Second tap: the button goes back to white and `Logger.removeField("support")` stops the tagging.
- Each toggle also logs `support_mode_on` / `support_mode_off`, marking the start and end of the
  support window in a timeline.
- State is in memory only: killing or restarting the app resets it to off.

**In bitdrift:** `support-sessions.json` matches `log_field: support == "true"` and
attaches a `flush_rule`, so the session is uploaded as soon as the first tagged log fires. It sets
no `applied_daily_limit`, so support sessions are never dropped. A second action charts the count of
tagged logs, which also confirms the button is reaching the SDK.

- Scoped to Android app `ai.bitdrift.shop` (the `applicationId` in `app/build.gradle.kts`).
- Like every capture workflow it only sees **new** sessions after deploy (`create` leaves it `IDLE`;
  run `bd workflow deploy <ID>`).
- Don't confuse it with the older **Support Log** toggle on the Advanced screen, which sets a
  separate `supportlog` field and is not matched by this workflow.

## Persistent feature flag sessions (`bd-shop-31`)

Captures sessions from devices holding a particular value of the three install-persistent flags
(see [Persistent feature flags](../README.md#persistent-feature-flags)).

`feature-flag-sessions.json` has one flow per flag, each matching the flag's **feature flag exposure** state (`state_key` with scope `FEATURE_FLAG_EXPOSURE`, set by `Logger.setFeatureFlagExposure`), not a log field:

| Flow | Matches | Why this value |
|------|---------|----------------|
| `express-checkout-log` | `express_checkout == enabled` | the new path |
| `card-layout-list-log` | `product_card_layout == list` | the non-default layout |
| `free-shipping-treatment-log` | `free_shipping_banner == treatment` | the A/B treatment cohort |

Each flow flushes the session on the first log evaluated while the exposure holds the target value (no `applied_daily_limit`, so none are
dropped) and has a count chart of matching logs. Because the flags are persistent and attached to
every log (the exposure is re-set at each launch), a matching device is captured in every session it starts, not just one. Roughly half of
installs match each flag; change `string_value` (or add flows) to capture other values.

Same rules as the other capture workflows: scoped to `ai.bitdrift.shop`, `create` leaves it `IDLE`
(run `bd workflow deploy <ID>`), and only sessions started after deploy are evaluated.
