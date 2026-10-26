# spec/ drift decisions

Phase 2a of `bitdrift-shop-PLAN.md`. Each entry: what differs (with `file:line` evidence),
the decision, the reason, and workflow impact. Path prefixes: `A:` =
`android/app/src/main/java/ai/bitdrift/shop/`, `I:` = `ios/BitdriftShop/`, `R:` =
`reactnative/`, `F:` = `flutter/lib/`.

**Ground rules applied.** Android is the reference. A name that a committed `bd-shop`
workflow matches on (`android/workflows/*.json`, `ios/workflows/*.json`,
`sessionmetricsdemo/workflows/*.json`) is never renamed on Android or iOS. Every committed
workflow targets only `ai.bitdrift.shop` (Android) or `ai.bitdrift.shop.ios` (iOS), so the
React Native (`ai.bitdrift.rn.shop`) and Flutter (`ai.bitdrift.shop.flutter`) apps have
no workflow coverage. Making them conform therefore touches **no workflow JSON**.

**Workflow impact of every DECIDED item below: none.** No decided item renames a name on
Android or iOS. The only items that could affect workflows are in the OPEN section.

**Not verified:** the live bitdrift account (the MCP connector needs auth in this
session, and `bd` was not run). "No workflow matches X" means no *committed* workflow or
dashboard JSON matches X. Live workflows edited in the UI and saved views were not
checked.

---

## Screens

### D-SCR-1: Flutter payment screen names
- **Differs:** Flutter logs `Card`, `Apple Pay`, `PayPal`, `Android Pay` (`F:ui/screens.dart:9-14`, used at `:603`). Android uses `PaymentCard`, `PaymentApplePay`, `PaymentPayPal`, `PaymentAndroidPay` (`A:MainActivity.kt:78-81`), and so do iOS (`I:Screen.swift:86-89`) and RN (`R:src/screens/ShoppingScreens.tsx:717,766,798,830`).
- **Decision:** Android names. Flutter renames.
- **Reason:** `_screen_name` drives the Sankey and the per-screen crash workflows (`bd-shop-01`, `ios bd-shop-17` matches `PaymentCard~~PaymentApplePay~~…`).
- **Workflow impact:** none (Flutter-only).

### D-SCR-2: Flutter `Diagnostics` becomes `Advanced`
- **Differs:** Flutter's settings screen logs `Diagnostics` (`F:ui/screens.dart:790`). Android, iOS and RN log `Advanced` (`A:MainActivity.kt:66`, `I:Screen.swift:74`, `R:src/screens/ShoppingScreens.tsx:944`).
- **Decision:** `Advanced`. The Flutter route key `diagnostics` may stay, because routes are not telemetry (D-SCR-3).
- **Workflow impact:** none.

### D-SCR-3: Route strings are not telemetry
- **Differs:** Android and iOS routes are byte-identical (`A:Screen.kt:17-66`, `I:Screen.swift:44-65`). RN routes use the screen names (`R:src/navigation/types.ts:3-23`). Flutter uses its own keys such as `product`, `category`, `checkout_guest` and `payment_applepay` (`F:app.dart:41-60`).
- **Decision:** `screens.yaml route` is the Android/iOS template. RN and Flutter route keys are listed under `platform_routes` and are not renamed.
- **Reason:** Nothing logs routes. Renaming Flutter routes would be churn with no benefit.

### D-SCR-4: 19 screens
All four apps have the same 19 destinations once D-SCR-1 and D-SCR-2 are applied. Screen-load spans exist only on Android and iOS (D-SPN-1).

---

## Session model

### D-SES-1: New session per launch and per journey
- **Differs:** Android and iOS use the default `SessionConfiguration()` (new session per process start) and call `startNewSession()` at every journey start, except while force-quit is enabled (`A:ShoppingDemoApp.kt:42`, `A:SimulationManager.kt:618`; `I:CaptureBridge.swift:75`, `I:SimulationManager.swift:688`). RN initializes with `SessionStrategy.Activity` and does not start a session per journey (`R:App.tsx:71`, `R:src/context/SimulationContext.tsx:362`). Flutter uses `activityBased` (`F:bd/capture.dart:25`).
- **Decision:** Android's model. Marked `optional_on: [reactnative, flutter]` until their SDKs are confirmed to support `startNewSession` (Flutter's `Bd.startNewSession` exists at `F:bd/capture.dart:102`, so this can probably be tightened in Phase 2b).
- **Reason:** The funnel and A/B workflows assume one journey per session (plan §3.2).

---

## Events

Every Flutter rename below is a Flutter-only change (D-EVT-F1 to D-EVT-F13), and the Flutter journey is rebuilt in Phase 4 anyway (plan §2).

### D-EVT-F1: `journey_start` becomes `journey_started`
- **Differs:** Flutter sends `journey_start` with fields {variant, checkout_type, entity} (`F:sim/simulator.dart:227`). Android sends `journey_started` with {run, variant} (`A:SimulationManager.kt:621`), and so do iOS (`I:SimulationManager.swift:690`) and RN (`R:src/context/SimulationContext.tsx:366`).
- **Decision:** `journey_started` with required {run, variant}. Flutter drops `checkout_type` and `entity` from this event: the entity is set via `setEntityId`, and checkout_type is on the `checkout` span.

### D-EVT-F2: `order_completed` becomes `confirmation_reached`
- **Differs:** After it navigates to Confirmation, the Flutter sim logs `order_completed` with {payment_method, order_id, variant} (`F:sim/simulator.dart:364`). Android logs `confirmation_reached` with {_screen_name, checkout_flow} (`A:SimulationManager.kt:1090`).
- **Decision:** `confirmation_reached` with Android's fields.

### D-EVT-F3: `payment_succeeded` becomes `payment_completed`
- **Differs:** `F:ui/screens.dart:627` vs `A:Screens.kt:1345`, `I:Screens.swift:1137`.
- **Decision:** `payment_completed` {payment_method, order_id, card_last4?}.

### D-EVT-F4: `checkout_created` becomes `checkout_started`
- **Differs:** Flutter logs `checkout_created` after the checkout API returns, in both the UI (`F:ui/screens.dart:522`) and the sim (`F:sim/simulator.dart:318`). Android logs `checkout_started` on the Cart screen's checkout tap (`A:Screens.kt:1113`). The extra `amount` and `variant` fields are dropped.
- **Decision:** `checkout_started` {checkout_type}.

### D-EVT-F5: `add_to_cart_tapped` becomes `add_to_cart`
`F:ui/screens.dart:290` vs `A:Screens.kt:946`. The `source_screen` field must be added.

### D-EVT-F6: `wishlist_add_tapped` becomes `add_to_wishlist`
`F:ui/screens.dart:301` vs `A:Screens.kt:954`. The `source_screen` field must be added.

### D-EVT-F7: `add_to_cart_failed` becomes `cart_failed`
Same API (`POST /api/cart`). Android logs `cart_failed` when the cart screen's addToCart call throws (`A:Screens.kt:1025`), and Flutter logs `add_to_cart_failed` (`F:ui/screens.dart:295`, at warning level). Decision: `cart_failed`, at error level.

### D-EVT-F8: `simulation_start_infinite` becomes `infinite_simulation_start`
Compare `F:sim/simulator.dart:144` with `A:SimulationManager.kt:299`. Flutter must also emit `infinite_simulation_end`.

### D-EVT-F9: `simulation_start` and `simulation_end` fields
Flutter adds `variant` to start and `completed_runs` to end (`F:sim/simulator.dart:145,163`). Android uses {total_runs} only (`A:ScreenLogger.kt:34,38`). Decision: Android's fields.

### D-EVT-F10: `journey_stopped` becomes `simulation_cancelled`
Flutter logs `journey_stopped` per aborted journey (`F:sim/simulator.dart:378`). Android logs `simulation_cancelled` {completed_runs, total_runs} once on cancel (`A:SimulationManager.kt:166`). Decision: Android's event.

### D-EVT-F11: `checkout_failed` level
Flutter's sim path logs it at warning (`F:sim/simulator.dart:326`), and its UI path at error (`F:ui/screens.dart:528`). Android uses error (`A:Screens.kt:1195`). Decision: error. `bd-shop-02` counts `checkout_failed` regardless of level, but level should match across platforms.

### D-EVT-F12: `crash_injection` becomes `about_to_crash`, plus the `crash_kind` global field
Flutter logs `crash_injection` {crash} (`F:crash.dart:48`). Android sets global fields `crash_kind` and `crash_context`, then logs `about_to_crash: <kind> (context=<ctx>)` (`A:SimulationManager.kt:576-578`). `ios bd-shop-15` matches `^about_to_crash`. Decision: Android's format.

### D-EVT-F13: Retired Flutter-only events
These events have no Android counterpart and duplicate a span or a screen view. They are removed and listed in `telemetry.yaml retired_events`:
- `discovery_completed` (`F:sim/simulator.dart:273`), which duplicates the `product_discovery` span end.
- `product_viewed` (`:281`), which duplicates the ProductDetail screen view and the `product_view` span.
- `payment_method_selected` (`:335`) and `payment_attempted` (`F:ui/screens.dart:618`), which duplicate `payment_screen_load`.
- `simulation_run_start` (`:151`), which duplicates `journey_started`.
- `sim_navigation_failed` (`:391`), a debug-only log.
- `wishlist_add_failed` (`F:ui/screens.dart:308`), which has no Android equivalent.

### D-EVT-1: Event names on Android and iOS are already identical
Every shared event (the sim lifecycle, journey, UI, lifecycle and fault events) has the same name and fields on Android and iOS. The evidence is in `telemetry.yaml` `source`. iOS deliberately kept Android's `anr_*` spelling for its hang (`I:SimulationManager.swift:424-427`).

### D-EVT-2: RN and Flutter app-level HTTP logs
`api_response`, `api_response_error` and `api_request_failed` are logged by RN (`R:src/api/ApiClient.ts:62,69,81`) and Flutter (`F:api/client.dart:66,69,76`), with the same names and fields on both. The native SDKs log HTTP automatically (`A:ApiClient.kt:22-29`, `I:CaptureBridge.swift:55-58`). Decision: keep them as `platforms: [reactnative, flutter]`. Flutter's extra `error` field is optional.

### D-EVT-3: `simulation_cancelled` level
RN logs it at warning (`R:src/context/SimulationContext.tsx:731`). Android and iOS log it at info (`A:SimulationManager.kt:165`, `I:SimulationManager.swift:186`). Decision: info.

### D-EVT-4: `confirmation_reached` fields
On success, RN always sends `payment_retried` (`"false"`) and no `checkout_flow` (`R:src/context/SimulationContext.tsx:613-617`). On the success path, Android sends {_screen_name, checkout_flow}. On the retry path it sends {_screen_name, payment_retried=true, retry_method} (`A:SimulationManager.kt:1064,1087`). Decision: Android's two shapes.

### D-EVT-5: `about_to_crash` message format
RN's sim uses `about_to_crash: <name> (idx=<n>)` (`R:src/context/SimulationContext.tsx:304`), and its Advanced-screen trigger uses `about_to_crash: <name>` (`R:src/sim/crashes.ts:199`). Android uses `about_to_crash: <kind> (context=<ctx>)`, and fast mode uses `about_to_crash (fast): …` (`A:SimulationManager.kt:578,608`). Decision: Android's format. RN must also set `crash_context`. The `^about_to_crash` prefix regex already matches all of them.

### D-EVT-6: Platform-only events are kept, not invented elsewhere
- **iOS only:** `previous_run_terminated` (`I:CaptureBridge.swift:165`, used by `ios bd-shop-15` and `bd-shop-17`), `screen_visit`, `demo_flags_resolved`, `background_crash_armed`, `watchdog_hang_armed`, `about_to_hang`, `simplified_journey_completed` and `simplified_journey_crash_point`.
- **Android only:** `support_mode_on` and `support_mode_off` (`A:SupportMode.kt:28`), and `low_memory` (`A:AppLifecycleCallbacks.kt:63`).
- **Decision:** keep each with `platforms:` set to the one platform. `previous_run_terminated` on Android is plan Phase 6 work, not a spec change.

---

## Fields and values

### D-FLD-1: `payment_method` values are snake_case
Flutter uses `applePay` and `androidPay` (`F:sim/simulator.dart:425-428`, `F:app.dart:55-57`). Everyone else uses `apple_pay` and `android_pay` (`A:SimulationManager.kt:947-952`, `I:Screens.swift:1013-1016`). Decision: snake_case. `bd-shop-02` groups by `payment_method`.

### D-FLD-2: `payment_method` value set, and RN's `visa` on the sim failure
- **Differs:** On the card screen, `payment_completed` legitimately sends the card brand (`visa`, `mastercard`, `amex`) on Android, iOS and RN (`A:Screens.kt:1345-1361`, `I:Screens.swift:1090-1092`). Method-level events and spans (`payment_failed` from the sim, `payment_retry`, the `checkout` span end, `payment_screen_load`) send `card` on Android and iOS (`A:SimulationManager.kt:948`). RN's sim maps card to `visa` for every sim event, including `payment_failed` and `payment_retry` (`R:src/context/SimulationContext.tsx:28-33,568,580`).
- **Decision:** The legal set is {card, visa, mastercard, amex, apple_pay, paypal, android_pay}. Brand values appear only on `payment_completed` from the card screen. RN's sim uses `card`.
- **Workflow impact:** none (RN has no workflows). `bd-shop-02` groups `payment_failed` by `payment_method` and sees only `card` on Android and iOS.

### D-FLD-3: Flutter error text
Flutter attaches `reason: '$e'` to `*_failed` events (`F:ui/screens.dart:528,631`) because the alpha SDK's `logError` takes no error object (`F:bd/capture.dart:43`). Android passes `throwable =` (`A:Screens.kt:1025`). Decision: `reason` is an allowed optional field on `payment_failed`, `checkout_failed` and `cart_failed`, and in practice it is used only by Flutter.

### D-FLD-4: Values that legitimately differ per platform
`app_open`/`app_close` `trigger` values differ: `onActivityStarted` on Android, `scenePhase.active` on iOS, `appstate_active` on RN (`A:AppLifecycleCallbacks.kt:38`, `I:BitdriftShopApp.swift:92`, `R:src/utils/appLifecycle.ts:43`). So does `memory_pressure` `level`: a numeric trim level on Android, `didReceiveMemoryWarning` on iOS and RN. So do `platform` and `crash_kind`. All four are marked `platform_specific: true` and are excluded from cross-platform diffs.

### D-FLD-5: Flutter-only fields
`app_version` (a global field, `F:main.dart:22`) and `sdk_started` (on `app_launched` and `app_cold_start`, `F:main.dart:27,39`) are kept as `platforms: [flutter]`. It could not be verified whether the alpha SDK reports the app version itself. If it does, drop `app_version` in Phase 2b.

### D-FLD-6: iOS screen-trail fields
`last_screen`, `screen_current` and `screen_prev_1` to `screen_prev_4` are iOS-only global fields (`I:ScreenLogger.swift:51,85,91`) used by `ios bd-shop-15` and `bd-shop-18`. Kept with `platforms: [ios]`.

---

## Flags

### D-FLG-1: Persona flag values match everywhere
The values of `checkout_flow`, `payment_ui`, `cart_abandon_rate` and `payment_android_pay` for Control, Variant A and Variant B are identical on Android (`A:SimulationManager.kt:87-117`), iOS (`I:SimulationManager.swift:119-123`), RN (`R:src/sim/variants.ts:111-130`) and Flutter (`F:sim/simulator.dart:182-201`). The toggle flags `order_summary`, `anr_a`, `force_quit` and `recommendations_v2` match on Android, iOS and RN. Flutter sets only `ff_*` fields because its SDK has no exposure API (`F:bd/capture.dart:57`), and it lacks the four toggle flags because it has no toggles. Decision: as in the code. Exposure is `optional_on: [flutter]` (plan §2), and `order_summary` is `missing_on: [flutter]`, since Flutter does have a crash loop.

### D-FLG-2: Persistent flags and `support` are Android only
`express_checkout`, `product_card_layout` and `free_shipping_banner` (`A:PersistentFeatureFlags.kt:24-26`, used by `bd-shop-31`) and the `support` global field (`A:SupportMode.kt:24`, used by `bd-shop-30`) exist only on Android. Decision: `platforms: [android]`. Porting them is a feature decision, not drift. The README lists it as a follow-up.

---

## Personas and journey

### D-PER-1: Probability tables
Android, iOS and RN are identical (`A:SimulationManager.kt:670-969`, `I:SimulationManager.swift:756-1052`, `R:src/sim/variants.ts:43-100`). Flutter has only discovery, reviews, wishlist, extra items, guest and payment weights, with the same values (`F:sim/simulator.dart:47-90`). It lacks featured, the cart edits, cart abandon, checkout dropout, payment failure and retry. Decision: Android's full table. Flutter gains the missing branches in Phase 4 (plan §2).

### D-PER-2: Entity selection
Android, iOS and RN rotate `entities[(run-1) % 10]` (`A:SimulationManager.kt:635`, `I:SimulationManager.swift:711`, `R:src/context/SimulationContext.tsx:360`). Flutter picks a random name, appends a timestamp for sign-in journeys, and clears the entity for guest journeys (`F:sim/simulator.dart:216-224`). Decision: Android's rotation. The Entities demo relies on a small, stable pool.

### D-PER-3: A/B rotation order
Android and iOS interleave personas per run (`i % 3`, `A:SimulationManager.kt:259`, `I:SimulationManager.swift:257`). RN runs blocks: Control N times, then A N times, then B N times (`R:src/context/SimulationContext.tsx:685-697`). Decision: interleaved.

### D-PER-4: Search terms
Android, iOS and RN use the same 10 terms (`A:SimulationManager.kt:377`, `I:SimulationManager.swift:344`, `R:src/context/SimulationContext.tsx:87`). Flutter uses 5 different terms, including `coffee maker` and `yoga mat` (`F:sim/simulator.dart:97`). Decision: the 10 terms.

### D-JRN-1: Flutter journey graph
Flutter skips Featured, the cart edits, abandon, dropout, payment failure injection and retry. It also ends the journey span with failure when the pay call fails (`F:sim/simulator.dart:203-372`). Decision: conform to Android in Phase 4. This is recorded in the spec through `missing_on: [flutter]` on the affected events and spans.

### D-JRN-2: Payment retry
- **Differs:** Android and iOS log `payment_failed`, navigate to PaymentFailed, then retry with probability 0.5, choosing uniformly among the *other three* methods including `android_pay` (`A:SimulationManager.kt:1013-1021`, `I:SimulationManager.swift:1069-1076`). RN goes straight to the retry without visiting PaymentFailed, and excludes `android_pay` from the alternatives (`R:src/context/SimulationContext.tsx:567-586`).
- **Decision:** Android's flow.

### D-JRN-3: Where the sim emits UI-tap events
See OPEN-5.

### D-JRN-4: Step pacing
Android, iOS and RN use 50 ms between steps and between runs (`A:SimulationManager.kt:73,226`, `I:SimulationManager.swift:100`, `R:src/context/SimulationContext.tsx:27`). Flutter uses 900 ms per navigation and 1500 ms between runs (`F:sim/simulator.dart:394,153`). Decision: 50 ms. If Flutter's route transitions need longer, raise it in Flutter's adapter and note that it is platform-specific.

---

## Spans

### D-SPN-1: Span names are frozen
Every span name used by `bd-shop-04`, `11b`, `14`, `20`, `21`, `22`, `23` and `24` is identical on Android and iOS. RN emulates spans with paired logs (`R:src/utils/logger.ts:111-135`) and lacks `discovery_fetch`, `product_view`, `wishlist_add`, `cart_assembly`, `checkout.payment`, `checkout.confirmation`, the screen-load spans and `foreground_session`. Flutter lacks those too. Decision: `missing_on: [reactnative, flutter]`, which is work for Phase 4. `app_cold_start.scene_render` and `.state_restore` are `optional_on: [reactnative, flutter]`, because they have no equivalent phase (`R:App.tsx:155-162`).

### D-SPN-2: Flutter journey span fields and parenting
Flutter's `journey` span has no `entity` field (`F:sim/simulator.dart:232`), `product_discovery` has no fields, and spans are not parented, because the alpha `startSpan` has no parent argument (`F:bd/capture.dart:113`). Decision: Android's fields. Parenting is exempt on Flutter until the SDK supports it.

### D-SPN-3: When Flutter ends the `checkout` span
Flutter ends `checkout` right after the checkout API call (`F:sim/simulator.dart:317`). Android ends it after Confirmation, with {payment_method, retried?} (`A:SimulationManager.kt:1099`). Decision: Android's timing.

---

## Faults

### D-FLT-1: The ANR/hang store is `anr_a` on Android and `app_hang` on iOS
- **Differs:** The persisted store is the SharedPreferences file `anr_a` on Android (`A:SimulationManager.kt:1134`) and the UserDefaults suite `app_hang` on iOS (`I:DemoPrefs.swift:54`). The *telemetry* is already unified: both emit flag `anr_a`, field `ff_anr_a` and event `guest_anr_injected` (`I:SimulationManager.swift:143,447`). The iOS-only `demo_flags_resolved` uses the key `app_hang` (`I:ContentView.swift:221`).
- **Decision:** Keep both store names, and record them per platform in `faults.yaml store`.
- **Reason:** Scripts and docs read them by name: `android/scripts/watchdog.sh:218,337`, `android/scripts/check-demo-state.sh:129,136` (`shared_prefs/anr_a.xml`), and `ios/scripts/demo-lib.sh:288-290` (`app_hang.*`, also usable as launch arguments). Renaming would break the scripts and existing armed devices, and gain nothing in bitdrift. Phase 5's `scripts/lib` reads the names from `faults.yaml`.

### D-FLT-2: Fault timings match on Android, iOS and RN
- **Shared values:** ANR 0.25 / force after 6 / block 15000 ms; force-quit 0.60 / force after 3; target screens CheckoutGuest and ProductDetail; crash flush 300 ms; background settle 2000 ms; restart 2000 ms; OOM restart 45000 ms (`A:SimulationManager.kt:1105-1148`, `I:SimulationManager.swift:1345-1376`, `R:src/context/SimulationContext.tsx:17-27`).
- **Platform-specific:** how the fault physically happens (Android freezes forever after the block, iOS calls `exit(0)`, RN uses its native module), the relaunch path (AlarmManager on Android, the host watchdog on iOS), and the per-crash pacing constants (`crashes.yaml timings`).
- **Decision:** as in the code.

### D-FLT-3: `restart_variant` encoding
Android persists the enum name (`CONTROL`, `VARIANT_A`; `A:SimulationManager.kt:445`), and iOS persists the raw value (`control`, `variantA`; `I:SimulationManager.swift:398`). Each is read back only by its own platform. Decision: the spec persona ids are `control`, `variant_a` and `variant_b`, which also match the plan's `--es persona variant_a` launch argument. The persisted encodings stay platform-internal (`personas.yaml persisted_name`). One observation, not a decision: both platforms write `restart_variant` into `crash_loop` but `restoreVariantFromPrefs` reads only the anr and force-quit stores (`A:SimulationManager.kt:145-161`, `I:SimulationManager.swift:172-182`), so a crash-loop resume does not restore the persona.

---

## Crashes

### D-CRS-1: Logical ids and per-platform impl keys
- **Differs:** Android has 28 entries (`A:Crashes.kt:25-62`), iOS 36 (`I:Crashes.swift:31-82`; the plan said 35), RN 20 (`R:src/sim/crashes.ts:159-183`) and Flutter 4 (`F:crash.dart:21`). Sixteen keys are identical on Android and iOS. Another nine are the same crash under a different name: null_pointer/force_unwrap_nil, class_cast/force_cast, illegal_state/precondition_failure, assertion_error/assertion_failure, runtime_background_thread/background_queue, coroutine_io/detached_task, vendor_sdk_interceptor/vendor_sdk_ads, oom_native_thread/oom_thread_exhaustion, oom_bitmap_decode/oom_image_decode. The illegal_state and assertion pairs share the exact message text.
- **Decision:** A logical id is Android's key where Android has the crash, otherwise the iOS key, otherwise the platform key. The per-platform key is kept in `impl`. **`crash_kind` keeps emitting the platform impl key; nothing is renamed.**
- **Reason:** No committed workflow matches `crash_kind` values. The workflows group by stack-derived fields (`crash_category`, `vendor_sdk`, `blocking_thread`) or by `^about_to_crash`. The Swift names are also more accurate for Swift.

### D-CRS-2: Crash catalog gaps
- **RN** is missing `lock_contention`, both vendor SDK crashes and five of the six OOMs (eight in total, matching plan §0). These are `missing_on: [reactnative]`.
- **Flutter's** `sigabrt`, `sigsegv` and `sigbus` map to `native_sig*`. Flutter's `process_exit` (`exit(1)`) becomes its own logical id, `process_exit`, which is unrelated to iOS's `watchdog_process_exit`.
- The JVM- and Swift-specific crashes are not expected on Flutter (it has no Dart exception bridge, `F:crash.dart:12-15`).
- The iOS-only crashes (watchdog_*, exc_bad_access_null, native_sigill and the six Swift traps) stay iOS-only.

---

## API

### D-API-1: Endpoints and path templates match on all four apps
The paths, methods and bodies match on all four apps and the backend (`api.yaml`). Path-template headers are identical in effect: Android and iOS pass the full `/api/...` template, and RN and Flutter prefix `/api` themselves (`R:src/api/ApiClient.ts:46`, `F:api/client.dart:41`). The only divergence is the cardinality endpoint (OPEN-6).

### D-API-2: Fake vendor SDK URLs
`https://ads.fake-vendor.example/init` and `https://ping.fake-analytics.example/batch` are identical on Android and iOS (`A:Crashes.kt:302,310`, `I:Crashes.swift:317,323`). The exception messages and namespaces differ on purpose, because each is a platform-idiomatic stack. Decision: the URLs are shared and the messages are platform-specific.

---

## KMP (best effort, out of scope)

### D-KMP-1: Noted, not used for decisions
The `wip-kotlin-multiplatform` variant drifts in several ways, none of which drove a decision:
- `app_variant` is `kmp-demo` (`wip-kotlin-multiplatform/iosApp/iosApp/ShoppingDemoKMPApp.swift:35`).
- The SDK key is `BITDRIFT_SDK_KEY` (`:14`).
- `payment_completed` uses `method` instead of `payment_method`, and `card: visa_4242` (`iosApp/iosApp/Screens.swift:580-760`, `shared/.../SimulationEngine.kt:425`).
- Flags are set to the variant name (`shared/.../SimVariants.kt:81`).
- `anr_a` and `force_quit` exposures are set to `injected` (`SimulationEngine.kt:273,387`).

KMP adopts the generated constants when it is next touched (plan §1).

---

## Needs user decision

### OPEN-1: SDK key config name: `BITDRIFT_SDK_KEY` or `BITDRIFT_API_KEY`? — **RESOLVED 2026-10-26: (a) `BITDRIFT_SDK_KEY`**
- **Decision (user):** all apps use `BITDRIFT_SDK_KEY`. iOS reads it first and falls back to `BITDRIFT_API_KEY` during a transition (code change lands in Phase 2b).
- **Evidence:**
  - Android uses `BITDRIFT_SDK_KEY` (`android/app/build.gradle.kts:75-81`).
  - RN uses it too (`R:src/config.ts:2,31`, `R:env.d.ts:2`), as do Flutter (`F:config.dart:31`) and KMP.
  - iOS uses `BITDRIFT_API_KEY` (`I:AppConfig.swift:17`, `ios/Info.plist:52`, `ios/local.xcconfig:21`). The iOS scripts also use it: `ios-1-setup.sh`, `ios-3-start-app.sh`, `release-build.sh` and `upload-symbols.sh` (for the dSYM upload).
- **Options:**
  - (a) Rename iOS to `BITDRIFT_SDK_KEY`.
  - (b) Rename the other three to `BITDRIFT_API_KEY`, which is the SDK's own parameter name (`apiKey`) and what the iOS comment argues for (`I:AppConfig.swift:11-13`).
  - (c) Leave it as is.
- **Impact:** No workflow is affected. The change breaks every developer's untracked local config file (`.local.properties`, `.env`, `.local.xcconfig`) and requires README and script edits.
- **Recommendation:** (a) Android wins with `BITDRIFT_SDK_KEY`, three apps against one. During a transition, iOS should read `BITDRIFT_SDK_KEY` and fall back to `BITDRIFT_API_KEY`, so existing `.local.xcconfig` files keep working.

### OPEN-2: `app_variant` on iOS: `ios-sdk-demo` or `sdk-demo`? — **RESOLVED 2026-10-26: (a) unify on `sdk-demo`**
- **Decision (user):** iOS sends `sdk-demo` (code change lands in Phase 2b, after a live saved-view/workflow check that nothing filters on `ios-sdk-demo`).
- **Evidence:** Android (`A:ShoppingDemoApp.kt:57`), RN (`R:src/config.ts:25`) and Flutter (`F:config.dart:21`) use `sdk-demo`. iOS uses `ios-sdk-demo` (`I:CaptureBridge.swift:90`), and KMP uses `kmp-demo`.
- **Options:**
  - (a) Unify on `sdk-demo`, since the `platform` field (added on every app) now distinguishes platforms.
  - (b) Keep the per-platform values.
- **Impact:** No committed workflow or dashboard references `app_variant` (verified by extracting every matcher and field key). Live saved views or UI-edited workflows filtering `app_variant=ios-sdk-demo` could not be checked.
- **Recommendation:** (a), after a `bd workflow list` or saved-view check in Phase 2b confirms nothing live filters on `ios-sdk-demo`.

### OPEN-3: Where in the journey does the crash loop fire?
- **Evidence:** Android fires only after Confirmation (`A:SimulationManager.kt:1074,1101`), and so does RN (`R:src/context/SimulationContext.tsx:621`). iOS picks a random point among cart, checkout, payment, payment_failed and confirmation, and records it as the global field `crash_journey_point` (`I:SimulationManager.swift:82-88,568-575,706`). Flutter fires at payment (`F:sim/simulator.dart:341`).
- **Options:**
  - (a) Adopt iOS's random back-half point on every platform.
  - (b) Keep the Android behavior.
  - (c) Keep it per platform.
- **Impact:** `ios/workflows/bd-shop-15-crashes-by-final-screen.json` groups by `crash_journey_point`. On Android, crash journeys would stop completing, which lowers `bd-shop-01` completions while the crash loop is on. `bd-shop-06` and `bd-shop-07` are unaffected.
- **Recommendation:** (a) in Phase 4 (`journey.yaml` fault point), because it makes crash-by-screen data meaningful. Until then the spec records it as `platforms: [ios]`.

### OPEN-4: Payment fails with no retry: the `checkout` and `journey` spans are left open — **RESOLVED 2026-10-26: (a) end both with FAILURE**
- **Decision (user):** Android and iOS now end `checkout` (field `payment_method`) and `journey` (field `reason=payment_failed`) as failures on an unretried payment failure, as RN already does. Flutter already ended the journey as failed.
- **Correction:** the evidence below said iOS leaves the spans open. A live tail (10 sims, 2026-10-26) showed iOS's spans did end, with `_result=unknown`, not stay open; Android's stayed open. Both are fixed by this change.
- **Workflow impact:** `bd-shop-04` (and any workflow matching `journey`/`checkout` ends with any `_result`) will now include failed journeys; add a `_result == success` filter if only successes should count.
- **Evidence:** When the 50% retry roll fails, Android returns without ending `checkout` or `journey` (`A:SimulationManager.kt:1001-1077`), and iOS does the same (`I:SimulationManager.swift:1061-1116`). RN ends both with `failure`, using reason `payment_failed` (`R:src/context/SimulationContext.tsx:587-588`).
- **Options:**
  - (a) End both with FAILURE and reason `payment_failed` everywhere, as RN does.
  - (b) Keep them open.
- **Impact:** `android/workflows/bd-shop-04-span-durations.json` matches `journey` and `checkout` end logs with any `_result`, so it would start including failed journeys. Add a `_result == success` filter if only successes should count. The Phase 3 conformance rule "spans closed" fails on Android and iOS without (a).
- **Recommendation:** (a).

### OPEN-5: Should simulated journeys emit the UI-tap events?
- **Evidence:**
  - On Android and iOS, `add_to_cart`, `add_to_wishlist`, `cart_item_removed`, `checkout_started` and `payment_completed` fire only on real taps (`A:Screens.kt:946-1516`, `I:Screens.swift:667-1137`). The sim navigates past them, so sim sessions never contain them.
  - RN's sim emits all five itself (`R:src/context/SimulationContext.tsx:437,446,469,539,602`).
  - Flutter's sim emits its equivalents (`checkout_created`, `order_completed`).
- **Options:**
  - (a) The journey engine emits them on every platform.
  - (b) Only taps emit them; RN's sim stops.
- **Impact:** No committed workflow matches these five events. `bd-shop-02` matches only `payment_failed` and `checkout_failed`. Option (a) adds volume and makes funnels on events possible.
- **Recommendation:** (a) in Phase 4, which makes sim sessions look like real user sessions. The spec marks these events `trigger: ui` with `sim_emits: {reactnative: true}` for now.

### OPEN-6: Cardinality demo: send the path template or not?
- **Evidence:** Android sends `x-capture-path-template: /api/inventory/lookup/<item>/<session>` (`A:ApiClient.kt:170`), which collapses the explosion. iOS omits it on purpose, with a "to apply, add pathTemplate" comment (`I:ApiClient.swift:200-208`). RN also omits it on purpose (`R:src/api/ApiClient.ts:26-27,151`).
- **Options:**
  - (a) Omit it by default, so the demo shows the problem.
  - (b) Send it, so the demo shows the fix.
  - (c) Add a toggle on the Advanced screen.
- **Impact:** No workflow is affected. It changes what the HTTP dashboard shows for Android.
- **Recommendation:** (c), defaulting to omitted.
