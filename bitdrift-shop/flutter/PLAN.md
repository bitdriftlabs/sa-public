# Flutter Shop — Plan

**One-line task:** Best-effort build of a Flutter port of the bitdrift shop (same backend, same shopping flow, bitdrift alpha instrumentation), plus CLI-only scripts to install Flutter, set up the Android SDK, create/boot an emulator, and run the app on it — **no Android Studio**.

This plan is the current deliverable. **Nothing is built yet** — confirm the decisions below first.

---

## Decisions to confirm before I build

1. **Install Flutter via git** to `~/development/flutter` (stable branch) and add `bin/` to `PATH`. No brew, no Studio. *OK?*
2. **Minimal deps only:** `http` (REST) + `cupertino_icons` (icons). No router package — use Flutter's built-in `Navigator`. *OK?*
3. **Simulation fidelity (alpha-limited):** port a **simplified** variant-driven journey (Control / Variant A / Variant B) that navigates the screens and logs screen views / spans / `ff_*` fields. **Drop** ANR injection, force-quit, and crash-loop injection — those need native bridges that the alpha SDK does not expose (see gaps). *OK, or do you want the chaos toggles kept as no-ops?*
4. **Target = Android emulator only** (per the task). iOS build is out of scope for this pass even though the alpha lists it. *OK?*
5. **Backend from the emulator** uses `10.0.2.2:5173` (Android's alias for the host loopback). *OK?*

---

## Alpha SDK: what it lets me do vs. what it doesn't

`capture_flutter` from `git tag flutter-prototype-0.0.1` (`platform/capture_flutter`).

| Concern | Alpha status | What the Flutter app will do |
|---|---|---|
| `Capture.start(apiKey, apiUrl, sessionStrategy, enableSessionReplay)` | ✅ | Start with activity-style session; `enableSessionReplay: true` (Android-only effect) |
| `logTrace/Debug/Info/Warning/Error`, `log` | ✅ | Same structured logging as the RN app's `ScreenLogger` |
| `logScreenView` | ✅ | Log a screen view per screen, matching RN screen names |
| `addField` / `removeField` | ✅ | Global fields (`app_variant`, `platform`, `ff_*` mirrors) |
| `startSpan` / `endSpan` | ✅ | Journey/discovery/checkout spans, `app_cold_start` (+ `.sdk_init` child) |
| `sessionId` / `sessionUrl` / `deviceId` / `getSdkStatus` | ✅ | Show in an "Advanced / Diagnostics" screen |
| `createTemporaryDeviceCode` | ✅ | Diagnostics screen button |
| **Network request/response capture** | ❌ not exposed | Still send `x-capture-path-template` header + log `api_response` / `api_response_error` (structured logs). OOTB *network* instant-insights won't auto-populate the same way as native — expected under alpha |
| **`setFeatureFlagExposure`** | ❌ not exposed | Record via `ff_*` global fields (filterable), not first-class flag exposures |
| **`setEntityId`** | ❌ not exposed | Record the demo entity as a global field |
| **App-launch TTI** | ❌ not exposed | Emit as a completed-span log pair (`_span_type` start/end + `_duration_ms`), matching the RN convention |
| **Dart/Flutter exception → native crash** | ❌ not prototyped | No automatic Dart-crash capture; no `logError(error, stackTrace)` param. Chaos crash/ANR/force-quit therefore **omitted** (see decision 3) |
| **Session Replay (iOS)** | ❌ | Not relevant (Android target) |

---

## App architecture (best-effort)

Flat, small, readable. No generated code, no mocks.

```
flutter/
├── README.md                     # how to set up + run (CLI only)
├── PLAN.md                       # this file
├── .env.example                  # BITDRIFT_SDK_KEY / BITDRIFT_API_HOST / BACKEND_PORT
├── pubspec.yaml                  # capture_flutter (git), http, cupertino_icons
├── analysis_options.yaml
├── lib/
│   ├── main.dart                 # Capture.start early, global fields, runApp
│   ├── app.dart                  # MaterialApp, theme, home = Welcome
│   ├── config.dart               # app version, variant, backend base URL, bd key/host
│   ├── bd/
│   │   └── capture.dart          # thin wrapper over capture_flutter (log/spans/fields/session)
│   ├── api/
│   │   └── client.dart           # typed endpoints + x-capture-path-template + response logging
│   ├── models/
│   │   └── models.dart           # Product, CartItem, CheckoutSession, Payment, Confirmation, ...
│   ├── sim/
│   │   └── simulator.dart        # variant profiles + a simplified scripted journey driver
│   └── ui/
│       ├── widgets.dart          # shared shells (ScreenContainer, ProductCard, Loading/Error)
│       ├── welcome.dart          # variant picker + start simulation (entry screen)
│       └── screens.dart          # Browse, Search, Featured, Categories, Category,
│                                 #   ProductDetail, Reviews, Cart, Wishlist,
│                                 #   Checkout(Guest/Signin), Payment methods, Failed, Confirmation, Diagnostics
└── scripts/
    ├── install-flutter.sh
    ├── setup-android.sh
    ├── start-emulator.sh
    └── run-app.sh
```

### Screen set (matches the other apps' core flow)
`Welcome` → `Browse` / `Search` / `Featured` / `Categories` → `CategoryBrowse` → `ProductDetail` → `Reviews` → `Cart` → `Wishlist` → `CheckoutGuest` / `CheckoutSignIn` → `PaymentCard` / `PaymentApplePay` / `PaymentPayPal` / `PaymentAndroidPay` → `PaymentFailed` → `Confirmation`, plus `Diagnostics` (session id/url, device code, SDK status, entity).

### Instrumentation mapping (RN → Flutter alpha)
- RN `init(...)` + `SessionStrategy.Activity` → `Capture.start(apiKey, apiUrl, enableSessionReplay: true)`.
- RN `addField` → `Capture.addField`.
- RN `setFeatureFlagExposure(name, v)` → `Capture.addField('ff_'+name, v)` (alpha has no flag API).
- RN `setEntityId(e)` → `Capture.addField('entity_id', e)`.
- RN span approximations (`_span_id/_span_type/_duration_ms/_result`) → **native** `Capture.startSpan` / `endSpan`.
- RN `logAppLaunchTTI` (no alpha API) → completed-span log pair under `app_cold_start`.
- Every API call → send `x-capture-path-template` for dynamic routes; log `api_response` (debug) / `api_response_error` (warning) / `api_request_failed` (error) exactly as `ApiClient.ts` does.

### Simulation (simplified, per decision 3)
- Port `VARIANT_PROFILES` (Control / A / B) and the `ff_*` flag set from `variants.ts`.
- A single async "journey" driver: pick a discovery path (browse/search/categories/featured), view a product (+ optional reviews/wishlist), build a cart, choose guest/signin, attempt payment (with the variant's failure probabilities → `PaymentFailed`), then `Confirmation`. Steps log screen views + spans + fields, with small delays so it reads as a human.
- Runs N times or "infinite" from the Welcome screen; an overlay shows run progress (like RN's `SimulationOverlay`).
- **Not ported** (alpha gap): crash-loop, ANR, force-quit, slow-mode heavy scoring.

---

## CLI-only Android path (no Android Studio)

Already present: emulator, `adb`, build-tools, platforms, licenses, an arm64 `android-36.1` system image. **Missing:** `cmdline-tools` (`sdkmanager`/`avdmanager`) and an AVD.

| Script | What it does (all idempotent) |
|---|---|
| `install-flutter.sh` | `git clone --depth 1 -b stable https://github.com/flutter/flutter ~/development/flutter`, print the `PATH` line to add, then `flutter doctor` |
| `setup-android.sh` | If `cmdline-tools` missing, `curl` the latest commandline-tools zip from `dl.google.com` into `~/Library/Android/sdk/cmdline-tools/latest`; run `sdkmanager --licenses` (auto-accept); ensure `system-images;android-36.1;google_apis_playstore;arm64-v8a` + `platform-tools` + `build-tools` present; `avdmanager create avd -n bitdrift_shop -k <image> -d pixel_7` |
| `start-emulator.sh` | `emulator -avd bitdrift_shop -no-window -no-audio -no-boot-anim &` then `adb wait-for-device` + poll `sys.boot_completed` |
| `run-app.sh` | Ensure backend reachable on `10.0.2.2:5173`; `flutter run -d <emulator-id> --release` (or `flutter build apk` → `adb install` → launch) |

`README.md` documents prerequisites (Xcode CLT for CMake/NDK already in SDK; the backend `./start-backend-docker.sh`), the four scripts, the `.env` credentials step, and how to stop the emulator (`adb emu kill`).

---

## Verification
1. `flutter analyze` clean; `flutter test` (a couple of model/API-client unit tests) green.
2. Backend up (`curl localhost:5173/api/health`), emulator booted, app launched, Welcome → one scripted journey completes end-to-end (visible screen transitions + `Confirmation`).
3. bitdrift: with a real `BITDRIFT_SDK_KEY`, logs / screen views / spans / `ff_*` fields appear in the dashboard for a Flutter session (session id surfaced on Diagnostics screen).
4. All four scripts re-run cleanly (idempotent) on a fresh shell.

---

## Out of scope (flag, don't do)
- iOS build/run for this pass.
- Dart-crash → native bridge, ANR/force-quit/crash-loop, real session-replay parity, network-instrumentation parity — all blocked by the alpha SDK (see table). If you want any of these stubbed as explicit "unsupported" no-ops, say so and I'll add them.
- A `flutter-clean` (no-SDK) counterpart (the repo pattern has clean copies) — not requested; I'll skip unless you want it.
