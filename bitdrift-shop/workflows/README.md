# bd-shop workflows and dashboards

One set of workflows and dashboards for every app, deployed with one command per app. [`manifest.json`](manifest.json)
is the source of truth: each entry has a unique `key`, the exact workflow `name` (how an account is searched), the
platform it targets, and its files. The old `bd-shop-NN` numbers collided between Android and iOS, so files are named
by slug now; the number is kept as `legacy` in the manifest and in the last table column for old notes.

## Deploy

```bash
tools/bd-deploy.sh ai.bitdrift.shop              # Android app: show what exists and what would be created (dry run)
tools/bd-deploy.sh ai.bitdrift.shop --apply      # create the missing ones (asks first), then the dashboards
tools/bd-deploy.sh ai.bitdrift.shop.ios --apply  # the iOS app's set
```

- **Safe against an existing account.** Workflows are matched by exact name, so anything already there is left alone
  (`EXISTS`); only what is missing is created and deployed. Nothing is ever deleted, and live `bd-shop` workflows that
  are not in the manifest are listed but untouched.
- **Dashboards** are matched by title. Their charts reference workflows through `__WF_<key>__` placeholders, which are
  replaced with the account's workflow IDs (existing or just created) before the dashboard is created.
- `--platform android|apple` overrides the platform guessed from the app id; `--include-shared` also deploys the two
  workflows that target both platforms (foreground session count and duration); `--only KEY[,KEY]` narrows the set.
- `--update KEY[,KEY]` replaces the config of existing workflows (stop, update, deploy). A deployed workflow's config
  is locked, and redeploying restarts its data window, so this only runs when you name the workflows, and it asks first.
  Metadata-only edits (titles, descriptions, chart display) can be applied to a live workflow without that: use
  `bd workflow update --metadata-file ...` directly.
- `--update-dashboards` updates dashboards that already exist. `--name-suffix " (trial)"` renames everything it creates
  so a trial run cannot collide with the real set. `--check` validates the manifest and files offline (run by
  `./test.sh ... unit`).

Templates: `templates/*.template.json` hold the workflow JSON shared by Android and iOS (journey sub-phase timings,
recommendation engine timings), with `{{platform_key}}`, `{{app_id}}` and `{{platform_label}}` filled in per
platform at deploy time. Metadata and chart-metadata stay per platform because their descriptions differ.

## Workflows

| key | platform | name | source | legacy |
|---|---|---|---|---|
| `android_cold_start_span_timings` | Android | Android Cold-Start Span Timings | file | bd-shop-20 |
| `android_journey_subphase_timings` | Android | Android Journey Sub-Phase Timings | template | bd-shop-22 |
| `android_recommendation_engine_timings` | Android | Android Recommendation Engine Timings | template | bd-shop-23 |
| `android_screen_load_timings` | Android | Android Screen Load Timings | file | bd-shop-21 |
| `android_anr_force_quit` | Android | ANR & Force-Quit Tracking | file | bd-shop-05 |
| `android_attribution_rate` | Android | Crash Attribution Rate | file | bd-shop-10 |
| `android_blocking_thread` | Android | Blocking Thread Attribution | file | bd-shop-08 |
| `android_crash_analytics` | Android | Crash Distribution & Session Capture | file | bd-shop-03 |
| `android_crash_background` | Android | Crashes in Background | file | bd-shop-07 |
| `android_crash_foreground` | Android | Crashes in Foreground | file | bd-shop-06 |
| `android_crash_rate_per_foreground` | Android | Crash Rate per Foreground Session (WIP) | file | bd-shop-15 |
| `android_feature_flag_sessions` | Android | Persistent Feature Flag Sessions | file | bd-shop-31 |
| `android_metric_grouping` | Android | Metric Grouping (Waveforms + Latency by Version) | file | bd-shop-12 |
| `android_payment_errors` | Android | Payment & Checkout Errors | file | bd-shop-02 |
| `android_slow_rendering` | Android | Slow Rendering (Recommendations v2) | file | bd-shop-11 |
| `android_slow_rendering_manual_span` | Android | Slow Rendering (Recommendations v2) — Manual Span Example | file | bd-shop-11b |
| `android_span_durations` | Android | Span Duration Histograms | file | bd-shop-04 |
| `android_support_sessions` | Android | Customer Support Sessions | file | bd-shop-30 |
| `android_user_journey_sankey` | Android | User Journey Sankey | file | bd-shop-01 |
| `android_vendor_sdk_attribution` | Android | Vendor SDK Attribution | file | bd-shop-09 |
| `ios_crashes_by_final_screen` | iOS | Crashes by Final Screen | file | bd-shop-15 |
| `ios_app_hang_sessions` | iOS | iOS App Hang Sessions | file | bd-shop-13 |
| `ios_cold_start_span_timings` | iOS | iOS Cold-Start Span Timings | file | bd-shop-20 |
| `ios_crash_terminal_sankey` | iOS | iOS Crash-Terminal Sankey | file | bd-shop-19 |
| `ios_crashes_by_last_screen_live` | iOS | iOS Crashes by Last Screen (live crash reports, Ripsaw) | file | bd-shop-18 |
| `ios_journey_subphase_timings` | iOS | iOS Journey Sub-Phase Timings | template | bd-shop-22 |
| `ios_journey_vs_crashes` | iOS | iOS Journey vs Crashes by Screen | file | bd-shop-17 |
| `ios_paths_to_force_quit` | iOS | iOS Paths to Force Quit | file | bd-shop-14 |
| `ios_persistence_timings` | iOS | iOS Persistence I/O Timings | file | bd-shop-24 |
| `ios_recommendation_engine_timings` | iOS | iOS Recommendation Engine Timings | template | bd-shop-23 |
| `ios_screen_load_timings` | iOS | iOS Screen Load Timings | file | bd-shop-21 |
| `shared_foreground_session_count` | Both | Foreground Session Count (WIP) | file | bd-shop-13 |
| `shared_foreground_session_duration` | Both | Foreground Session Duration (WIP) | file | bd-shop-14 |

## Dashboards (in [`../dashboards/`](../dashboards/))

| slug | platform | title | workflows |
|---|---|---|---|
| `android-cold-start-span-timings` | Android | Android — Cold-Start Span Timings | `android_cold_start_span_timings` |
| `android-journey-subphase-timings` | Android | Android — Journey Sub-Phase Timings | `android_journey_subphase_timings` |
| `android-recommendation-engine-timings` | Android | Android — Recommendation Engine Timings | `android_recommendation_engine_timings` |
| `android-screen-load-timings` | Android | Android — Screen Load Timings | `android_screen_load_timings` |
| `metric-grouping` | Android | bd-shop — Metric Grouping | `android_metric_grouping` |
| `ios-cold-start-span-timings` | iOS | iOS — Cold-Start Span Timings | `ios_cold_start_span_timings` |
| `ios-journey-subphase-timings` | iOS | iOS — Journey Sub-Phase Timings | `ios_journey_subphase_timings` |
| `ios-journey-vs-crashes-guided` | iOS | iOS — Journey vs Crashes by Screen (guided) | `ios_crash_terminal_sankey`, `ios_crashes_by_last_screen_live`, `ios_journey_vs_crashes` |
| `ios-persistence-timings` | iOS | iOS — Persistence I/O Timings | `ios_persistence_timings` |
| `ios-recommendation-engine-timings` | iOS | iOS — Recommendation Engine Timings | `ios_recommendation_engine_timings` |
| `ios-screen-load-timings` | iOS | iOS — Screen Load Timings | `ios_screen_load_timings` |

Longer notes on specific workflows live in [`docs/`](docs/).
