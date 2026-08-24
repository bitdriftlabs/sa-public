# Bitdrift Shop (iOS — SDK)

**Version 2.0**

Native SwiftUI demo app simulating an e-commerce shopping experience, **already
instrumented with the bitdrift Capture SDK** (`capture-ios` 0.23.11 via Swift
Package Manager). It pairs with the same FastAPI backend the Android app uses, so
it produces realistic sessions, network traffic, crashes, and performance signals
out of the box.

**100% native Swift.** No Kotlin Multiplatform, no shared framework, no
Objective-C sources or bridging header, no CocoaPods — just Swift + SwiftUI with
one SPM dependency. The crash catalog uses Swift language and standard-library
traps plus POSIX signals rather than `NSException` tricks, and the app lifecycle
runs on SwiftUI's `scenePhase` rather than a `UIApplicationDelegate`.

This is a port of [`android/`](../android/) — same 19 screens, same probabilistic
simulation, same event and field names — so both platforms feed the same
`bd-shop-*` workflows and dashboards and can be compared side by side.

For the no-SDK comparison target, see [`ios-clean/`](../ios-clean/). It keeps the
same app flow and backend integration without Capture SDK configuration.

This is community-contributed content provided for educational purposes only.

> ⚠️ **Run `./scripts/watchdog.sh` before enabling Crash, OOMs, Hang-A, or Quit**
> (Advanced screen). These modes deliberately crash, freeze, or kill the app, and
> **iOS gives an app no way to relaunch itself** — without the host-side watchdog
> the simulator just sits on a dead app. Fast Crash Mode fires too quickly to stop
> from the UI; use `./scripts/watchdog.sh --stop`.
>
> **These flags persist across restarts by design**, so leaving one on and later
> starting an unrelated demo leaves it silently armed. Run
> `./scripts/check-demo-state.sh` (add `--reset` to clear) before any demo session.

## Quick Start

### Step 0: Configure your bitdrift credentials

Create `.local.xcconfig` in this directory (gitignored — your real values go here,
overlaying the blank `local.xcconfig` template that it is `#include?`d from):

```
BITDRIFT_API_KEY = <your-api-key>
BITDRIFT_API_HOST = api.bitdrift.io
```

Get the API key from the **bitdrift dashboard → Settings**. It determines which
project your data lands in — crashes, sessions, and workflows only appear in the
project that owns this key. The same key authorizes both jobs it's needed for:
`Logger.start(withAPIKey:)` at runtime, and the dSYM upload for crash
symbolication at build time.

> Named `BITDRIFT_API_KEY` to match what bitdrift calls it — the SDK's own
> parameter is `withAPIKey:` and the CLI's flag is `--api-key`. The Android app
> calls the same credential `BITDRIFT_SDK_KEY` in its `local.properties`.

For bitdrift-internal testing against a non-production environment, point
`BITDRIFT_API_HOST` at that environment instead (e.g. `api.bitdrift.dev`), making
sure the key was issued by that same environment's dashboard.

Without a key the app still runs and the UI works; the SDK logs
`failed to authenticate with the backend` and the Device Code button returns
`⚠ needs_api_key`.

These two settings are the whole configuration surface — the same pair the
Android app reads from `.local.properties`.

### Step 1: Start the backend

```bash
cd ../backend
./start-backend-docker.sh
```

Needs a running Docker daemon — see [backend/README.md](../backend/README.md) if
`docker ps` isn't already working. Without Docker you can run it directly:

```bash
cd ../backend && python3 -m uvicorn shopping_server:app --host 0.0.0.0 --port 5173
```

The **iOS Simulator shares the host's network stack**, so the app reaches the
backend at plain `http://localhost:5173` with no aliasing — unlike the Android
emulator, which needs the `10.0.2.2` alias.

On a **physical device** `localhost` means the phone, which has no route to your
Mac's loopback — so set `SHOP_BACKEND_URL` in `.local.xcconfig` to your Mac's LAN
address. No source changes needed:

```
SHOP_BACKEND_URL = http:/$()/192.168.1.20:5173
```

`ipconfig getifaddr en0` prints the address. Keep the `$()` between the slashes:
`//` starts a comment in xcconfig, so without it the value truncates to `http:`.

`en0` is Wi-Fi on most Macs, but not all — a Mac connected via a USB-Ethernet
adapter or dock can have `en0` come back empty while the real address sits on
`en5`/`en6`/etc. If `ipconfig getifaddr en0` prints nothing, run
`ifconfig | awk '/^[a-z]/{i=$1} /inet /{print i, $2}'` to see every interface's
address and pick the one matching your LAN's subnet (check `networksetup
-listnetworkserviceorder` if more than one looks plausible).

(A physical *Android* device has the same problem — its `10.0.2.2` alias is
emulator-only. The emulator hides it rather than solving it.)

### Step 2: Run the app

Open `BitdriftShop.xcodeproj` in Xcode and run on any iOS 16+ simulator or device.
From the command line:

```bash
xcodebuild -project BitdriftShop.xcodeproj -scheme BitdriftShop \
  -configuration Debug -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```

The app opens on a 5-second **startup config** screen (crash mode, fast crash,
OOM-only, auto ∞ sim), then goes to Welcome. **Skip → Normal App** bypasses it and
clears the crash flags.

### Optional: run on a physical device, without opening Xcode

Build, install, and launch are all CLI. Signing is the only catch — the account
credential has to exist locally first, either from one Xcode → Settings →
Accounts sign-in, or from an App Store Connect API key
(`-authenticationKeyPath`/`-authenticationKeyID`/`-authenticationKeyIssuerID`,
which needs Account Holder rights to create).

```bash
DEV=<device-udid>        # xcrun devicectl list devices
TEAM=<your-team-id>      # developer.apple.com -> Account -> Membership details

xcodebuild -project BitdriftShop.xcodeproj -scheme BitdriftShop -configuration Debug \
  -destination "id=$DEV" -allowProvisioningUpdates DEVELOPMENT_TEAM=$TEAM \
  -derivedDataPath build/dev build

xcrun devicectl device install app --device $DEV \
  build/dev/Build/Products/Debug-iphoneos/BitdriftShop.app
xcrun devicectl device process launch --device $DEV ai.bitdrift.shop.ios
```

Things that will stop you the first time:

- **"Untrusted Developer" on first launch.** Expected for *any* development-signed
  build, paid team or free — Xcode's Run button shows it too. Trust the
  certificate once per signing identity: Settings → General → VPN & Device
  Management → Developer App → Trust.
- **"Device isn't registered in your developer account."** `-allowProvisioningUpdates`
  can only auto-register if your role on that team allows it. Otherwise an Admin
  adds the UDID at developer.apple.com → Devices. A free personal team
  auto-registers, but its profile expires after **7 days**.
- **Product screens will be empty.** The backend URL is hardcoded to `localhost`,
  which on a phone means the phone. Point `ApiClient.swift` at your Mac's LAN IP.
  bitdrift reporting is unaffected — that goes to `api.bitdrift.io`.

### Step 3: Generate data

On Welcome, tap **Sim 10** for ten journeys or **SIM ∞** for continuous
simulation. The Sankey, network calls, spans, and session timelines populate in
the dashboard in real time.

---

## What's already instrumented

| Feature | SDK surface | Where it lives |
|---------|-------------|----------------|
| **SDK dependency** | `capture-ios` 0.23.11 (SPM, `Capture` product) | [project.pbxproj](BitdriftShop.xcodeproj/project.pbxproj) |
| **Logger startup** | `Logger.start(withAPIKey:sessionStrategy:configuration:fieldProviders:)` in `App.init()` | [CaptureBridge.swift](BitdriftShop/CaptureBridge.swift), [BitdriftShopApp.swift](BitdriftShop/BitdriftShopApp.swift) |
| **Session strategy** | `.activityBased()` — resumes the same session across a crash + relaunch if it lands within `inactivityThresholdMins`, which is what lets `bd-shop-19`'s crash-terminal Sankey close | [CaptureBridge.swift](BitdriftShop/CaptureBridge.swift) |
| **Network capture** | `.enableIntegrations([.urlSession()])` — automatic, no per-call code | [CaptureBridge.swift](BitdriftShop/CaptureBridge.swift) |
| **Path templates** | `x-capture-path-template` header on parameterised routes | [ApiClient.swift](BitdriftShop/ApiClient.swift) |
| **Screen views** | `Logger.logScreenView(screenName:)`, centrally from `Navigator` | [Navigator.swift](BitdriftShop/Navigator.swift), [ScreenLogger.swift](BitdriftShop/ScreenLogger.swift) |
| **User identity** | `Logger.setEntityID("demo")` on launch, then rotated per simulated user | [CaptureBridge.swift](BitdriftShop/CaptureBridge.swift), [SimulationManager.swift](BitdriftShop/SimulationManager.swift) |
| **Structured logs** | `logInfo`/`logWarning`/`logError` (`add_to_cart`, `checkout_started`, `payment_completed`, …) | [Screens.swift](BitdriftShop/Screens.swift), [SimulationManager.swift](BitdriftShop/SimulationManager.swift) |
| **Global fields** | `Logger.addField(withKey:value:)` + a `FieldProvider` — `user_id`, `app_variant`, `platform`, `ff_*`, `supportlog`, `sim_app_version` | [CaptureBridge.swift](BitdriftShop/CaptureBridge.swift), [SimulationManager.swift](BitdriftShop/SimulationManager.swift), [MetricsDemo.swift](BitdriftShop/MetricsDemo.swift) |
| **Feature flags** | `Logger.setFeatureFlagExposure(withName:variant:)` for `checkout_flow`, `payment_ui`, `cart_abandon_rate`, `recommendations_v2`, … | [SimulationManager.swift](BitdriftShop/SimulationManager.swift) |
| **Custom metrics** | `metric_values` ticking once/sec, with `metric_work_latency_ms` auto-rotating across `sim_app_version` — same event/field names as Android, so both feed `bd-shop-12`; walkthrough in [android/metric-demo.md](../android/metric-demo.md) | [MetricsDemo.swift](BitdriftShop/MetricsDemo.swift) |
| **App launch TTI** | `Logger.logAppLaunchTTI()` after first frame | [ContentView.swift](BitdriftShop/ContentView.swift) |
| **Custom spans** | `Logger.startSpan()` (`journey` → `product_discovery`, `checkout`) and a `trackSpan` helper wrapping `score_products` | [SimulationManager.swift](BitdriftShop/SimulationManager.swift), [CaptureBridge.swift](BitdriftShop/CaptureBridge.swift) |
| **Support tooling** | `Logger.createTemporaryDeviceCode()`, Support Log toggle | [Screens.swift](BitdriftShop/Screens.swift) |
| **Session boundaries** | `Logger.startNewSession()` per simulated journey, and every 60s while the metrics demo runs | [SimulationManager.swift](BitdriftShop/SimulationManager.swift), [MetricsDemo.swift](BitdriftShop/MetricsDemo.swift) |
| **Crash symbolication** | dSYM upload via `bd debug-files upload` in a post-build phase | [scripts/upload-symbols.sh](scripts/upload-symbols.sh) |
| **Lifecycle events** | `app_open` / `app_close` from SwiftUI `scenePhase`; `memory_pressure` from the UIKit memory-warning notification | [BitdriftShopApp.swift](BitdriftShop/BitdriftShopApp.swift) |

`Logger.trackSpan { }` exists in the Kotlin API but not the Swift one, so
[`CaptureBridge.trackSpan`](BitdriftShop/CaptureBridge.swift) reimplements the
scoped form (SUCCESS on return, FAILURE on throw) over `startSpan`/`Span.end`.

## Simulation

The simulator walks the full funnel, choosing branches probabilistically at each
decision point. Three persona presets bias those choices, exactly as on Android:

| Variant | Behaviour |
|---------|-----------|
| **Control** | Baseline — unbiased random at every branch |
| **Variant A** | Digital native: snap decisions, skips reviews, guest checkout, digital payment, high cart abandonment |
| **Variant B** | Deliberate shopper: reads everything, heavy cart churn, signs in, pays by card, rarely abandons |

Every probability, event name, field name, and span name matches the Android
implementation, so cross-platform comparisons in a dashboard are apples to apples.

### Simplified journey

`SIMPLIFIED_JOURNEY_ENABLED = YES` in `.local.xcconfig` replaces the randomized
funnel above with a fixed, non-random 7-step path, matching
[`bd-shop-17`](workflows/bd-shop-17-ios-journey-vs-crashes.json)'s funnel stages
1:1 so the funnel chart reads as a clean staircase:

```
Welcome → Browse → ProductDetail → Cart → CheckoutGuest → PaymentCard → Confirmation
```

Built for a concrete before/after test of whether a workflow's Sankey or flow
actually closes on a crash, rather than reasoning about it against a randomized
journey with a probabilistic crash point. With the crash loop **off**, every
journey completes all 7 steps — a clean baseline proving the path itself
populates a Sankey/funnel end to end. With it **on**, every journey crashes
**unconditionally at step 5** (`CheckoutGuest`) — no random branching, no
probabilistic crash-point selection, so there is never any ambiguity about
which step a workflow's flow died at. See
[`SimulationManager.runSimplifiedJourney`](BitdriftShop/SimulationManager.swift).

Step 5 is chosen deliberately: it is exactly where `ScreenLogger`'s 5-deep
screen shift register fills, so a crash report carries `screen_current` plus
four real `screen_prev_N` values with no `none` padding — the full path from
Welcome to the crash, readable straight off the report's Custom Fields.

A few things behave differently in this mode, all deliberately:

- **The startup config splash is skipped.** There is nothing to configure —
  the path and crash point are both fixed by the build flag — so every
  relaunch goes straight to the app instead of paying a 5s countdown. A small
  "MIN JOURNEY" / "FULL JOURNEY" pill floats over the top-right corner of every
  screen so it's still obvious at a glance which build is installed.
- **The crash draw excludes every hang-shaped combo**, not just the ones
  targeted at the crash catalog's `watchdog_*` entries. `lock_contention` is
  also excluded — it deliberately blocks the main thread for a fixed delay
  before a separate thread converts it to a crash, which is exactly the kind
  of hang this mode exists to rule out. The crash *kind* still rotates through
  the rest of the catalog on every firing; only the hang-shaped ones are
  removed. See `Crashes.combo(excludeHangs:)`.
- **`app_hang` and `force_quit` modes are unaffected** — this flag only
  changes which screens the simulator walks and how its own crash draw is
  filtered, not the other fault-injection toggles below.

## Fault injection

All toggles live on the **Advanced** screen unless noted. Each one persists across
launches.

| Mode | What it does |
|------|--------------|
| **Crash** | After each completed journey, fires the next crash in a deterministic sweep of 32 crash kinds × {foreground, background} |
| **OOMs** | Same loop restricted to the 6 memory-exhaustion variants |
| **Fast crash mode** *(startup screen)* | Skips the journey entirely and fires the next crash immediately on every launch |
| **Hang-A** | Blocks the main thread on CheckoutGuest (Variant A only) — the iOS analogue of Android's ANR |
| **Quit** | Terminates the process on ProductDetail, simulating an app-switcher swipe-away |
| **Rec v2** | Enables the deliberately slow, unmemoized recommendation scoring — see below |

### Crash catalog

[`Crashes.swift`](BitdriftShop/Crashes.swift) defines 36 variants, each with its
own `@inline(never)` top frame so bitdrift's issue grouper keeps them apart.

**30 run in the default sweep** — the 6 memory variants are excluded unless
`ENABLE_OOM_CRASHES = YES`, since each blocks for ~35s and needs a 45s restart.

- **Swift language traps** (13) — force-unwrap nil, array index, force cast,
  divide by zero, number format, arithmetic overflow, precondition, assertion,
  fatalError, string index, negative array size, unowned-after-dealloc, stack
  overflow
- **Standard-library traps** (3) — missing dictionary key, invalid `Range`
  (upperBound < lowerBound), `try!` decode of a mismatched payload
- **Off-main-thread** (2) — background `DispatchQueue`, detached `Task`
- **Watchdog terminations** (3) — `0x8BADF00D`, reported as **App Hang**:
  `scene-create` (blocks during launch), `scene-update` (blocks on resume),
  `process-exit` (blocks on SIGTERM). Not exceptions — the OS killing a process
  that overran a lifecycle budget. These arm a flag and `scripts/watchdog.sh`
  drives the transition, since an app cannot launch, resume or terminate itself
- **Memory access faults** (1) — `exc_bad_access_null`, a real bad dereference, so
  the report carries a faulting address (a raised `SIGSEGV` carries none)
- **Lock contention** (1) — three genuinely uncorrelated thread states captured
- **Vendor SDK attribution** (2) — frames from `AdSDKFake` / `AnalyticsSDKFake`,
  standing in for Android's `com.adsdk.fake` / `com.analytics.fake`
- **Native signals** (5) — SIGSEGV, SIGBUS, SIGABRT, SIGFPE, SIGILL, each calling
  `raise()` directly
- **Memory exhaustion** (6) — background allocator, main thread, single huge
  allocation, thread exhaustion, image buffers, unbounded cache

### Slow-rendering demo

`RecommendationEngine.scoreProducts()` runs a Levenshtein-similarity pass over
full product profiles, called synchronously and unmemoized from a SwiftUI view
body, so it re-executes on every render. The code is correct and throws nothing —
the defect is a runtime performance characteristic.

On Android this is caught by the OOTB `DROPPED_FRAME` condition. **That condition
is Android-only**, so on iOS the `score_products` span wrapped around each call
site is the detection path — the shape
[`bd-shop-11b-slow-rendering-manual-span.json`](../android/workflows/bd-shop-11b-slow-rendering-manual-span.json)
matches on. Background and walkthrough:
[demo-slow-rendering.md](../android/demo-slow-rendering.md).

---

## How this differs from the Android app

Everything observable in the dashboard is deliberately identical. The differences
are all places where the platform left no choice:

| Area | Android | iOS |
|------|---------|-----|
| **Backend host** | `10.0.2.2:5173` (emulator alias) | `localhost:5173` (Simulator shares the host network stack) |
| **Relaunch after a fault** | `AlarmManager` armed before the crash; the app restarts itself | **Not possible.** `scripts/watchdog.sh` polls and relaunches, on a Simulator (`simctl`) or a device (`devicectl`) |
| **ANR** | Real ANR + system dialog | No such concept. A blocked main thread is reported through MetricKit hang diagnostics. Event/field names keep the `anr_*` spelling so `bd-shop-05` matches both platforms; the UI calls it **Hang-A** |
| **Hang duration** | Unbounded freeze until the watchdog dismisses the dialog | Bounded (15s), then exits — nothing host-side can detect or clear a hung iOS app, so the alternative is a permanently frozen simulator |
| **Backgrounding for background crashes** | `Activity.moveTaskToBack()` | No public API exists, and the private `suspend` selector is useless anyway — a *suspended* app's main queue is frozen, so a crash scheduled on it never runs. Instead the crash is **armed** and fires once the app genuinely backgrounds (Home button, or the watchdog), held alive by a `beginBackgroundTask` assertion long enough to land while `running_state` reads background. This is what `bd-shop-06`/`07` chart |
| **App lifecycle** | `ActivityLifecycleCallbacks` | SwiftUI `scenePhase`, filtered to real foreground/background edges so `app_open`/`app_close` counts stay comparable |
| **OOM** | `OutOfMemoryError` with a stack | Jetsam kill; surfaced via out-of-memory / unexpected-termination detection, not a crash report. Far more predictable on a physical device than on the Simulator, where limits track the host machine |
| **Frame jank** | OOTB `DROPPED_FRAME` detection | Not available on iOS — use the `score_products` span |
| **Preferences** | `SharedPreferences` + `commit()` | `UserDefaults` + `synchronize()`, namespaced by suite in [DemoPrefs.swift](BitdriftShop/DemoPrefs.swift) |
| **Android Pay screen** | Native to the platform | Kept as-is. The route, `_screen_name`, and `payment_method` values stay `PaymentAndroidPay` / `android_pay` so the shared funnel and payment-error workflows line up across platforms |
| **`payment_completed`** | Emitted only on the card screen | Emitted for **every** payment method. Android's omission silently drops Apple Pay / PayPal / Android Pay from the checkout-funnel conversion numbers — an Android bug worth fixing there, not a behaviour worth copying. Expect iOS completion counts to exceed Android's until it is |
| **`user_id` on member checkout** | Reads `user.id`, which the backend never returns — so it is never set | Falls back to `user.email`, the only stable identifier `/api/checkout/signin` actually provides. Android has the same latent bug |

## Scripts

```bash
./scripts/release-build.sh                # Release build + dSYM upload (see below)
./scripts/watchdog.sh                     # relaunch on death; background the app when a background crash is armed
./scripts/watchdog.sh --stop              # stop the watchdog and terminate the app
./scripts/check-demo-state.sh             # show which fault flags are armed
./scripts/check-demo-state.sh --reset     # simulator only
```

Both work against a Simulator or a physical device:

| Flag | Target |
|------|--------|
| *(none)* | Auto — booted simulator if there is one, else a connected device |
| `--simulator [UDID]` | Force the simulator (`simctl`) |
| `--device [UDID]` | Force a physical device (`devicectl`) |

Both work on a device too:

- **Backgrounding** for the background half of the crash sweep. The Simulator gets
  there by launching SpringBoard; a device has no equivalent, so the watchdog
  launches **Settings** to take the foreground instead. Expect the phone to flip
  to Settings periodically during a crash loop.
- **`--reset`** can't delete a device's `UserDefaults` plist, so it disarms by
  relaunching the app with every flag explicitly `0`. Launch arguments land in
  `NSArgumentDomain`, and the app persists whatever it resolves at startup, so one
  disarmed launch sticks.

**Stuck in Fast Crash Mode?** That's what `--reset` is for:

```bash
./scripts/check-demo-state.sh --device --reset
```

Fast crash mode fires before you can reach the UI, so the on-screen "Stop crash
loop" button is unusable — this is the way out.

The app publishes its fault state to
`<container>/Library/Application Support/bitdrift-demo-state.json`, and the
scripts read that rather than the app's `UserDefaults` plist. On the Simulator
that plist is owned by `cfprefsd`, which caches the domain in memory — a
host-side read can return values the app abandoned minutes ago, and a host-side
write is silently overwritten on the daemon's next flush. On a device the plist
isn't reachable at all, but the JSON file can be pulled with
`devicectl device copy from`. `--reset` works around the daemon by terminating
the app, deleting the plist, and bouncing it.

### Crash symbolication (dSYM upload)

The **Upload bitdrift Symbols** post-build phase runs
[scripts/upload-symbols.sh](scripts/upload-symbols.sh), the counterpart of the
Android app's `bdUpload*` Gradle tasks. It needs the `bd` CLI on `PATH` and a
platform API key:

```
BITDRIFT_API_KEY = <platform-api-key>
```

It reuses `BITDRIFT_API_KEY` — the same key the app starts the SDK with. Xcode
exports build settings into script phases, so defining it in `.local.xcconfig` is
all that's needed.

The phase skips quietly and never fails the build when there's no key, no `bd`,
or no dSYM. **Debug builds produce no dSYM** (`DEBUG_INFORMATION_FORMAT = dwarf`),
so symbols only upload from Release.

#### Doing a Release build

```bash
./scripts/release-build.sh --simulator            # no signing needed
./scripts/release-build.sh --device              # signed, matches phone crashes
./scripts/release-build.sh --device --install     # ...and install it
./scripts/release-build.sh --device --team ABCDE12345
```

With no flag it targets a booted simulator, else a connected device. A **device**
build needs a signing team — pass `--team`, or put it in `.local.xcconfig` once:

```
DEVELOPMENT_TEAM = <your-team-id>
```

The script warns up front if `BITDRIFT_API_KEY` is missing, then prints the app
and dSYM paths and **verifies the upload actually landed** by counting debug files
before and after:

```
debug files on the platform: 0 -> 1
Symbols uploaded.
```

That check exists because **`bd` exits 0 whether or not the upload worked** —
verified against bd 0.2.18, a deliberately invalid API key printed no error and
still exited 0, uploading nothing. The exit code is useless, so both layers key
off other signals: the build phase looks for `bd`'s explicit "File uploaded"
line, and this script diffs the platform's debug-file count. If the count doesn't
move, the key is missing or rejected.

Note that `bd debug-files list` prints its `total=N` summary on **stderr**, not
stdout — discarding stderr when scripting it silently yields no count.

For a device build, prefer the device dSYM: it's the one whose UUID matches
crashes coming off the phone.

```bash
# manual / CI equivalent
BITDRIFT_API_KEY=<key> ./scripts/upload-symbols.sh <path-to-dSYMs>
```

### Arming a demo from the command line

Any flag can be set as a launch argument, which is handy for scripted or
unattended runs:

```bash
xcrun simctl launch <UDID> ai.bitdrift.shop.ios \
  -crash_loop.active 1 -crash_loop.fast_mode 1
```

The app promotes whatever it resolves at startup into its persistent store, so
the setting survives the watchdog's subsequent relaunches. Clear it with
`./scripts/check-demo-state.sh --reset`. Available keys: `crash_loop.active`,
`crash_loop.fast_mode`, `crash_loop.oom_only`, `app_hang.active`,
`force_quit.active`, `auto_infinite.active`.

## Deploy workflows and dashboards

The `bd-shop-*` workflows and dashboards in [`../android/workflows/`](../android/workflows/)
and [`../android/dashboards/`](../android/dashboards/) apply to this app too — the
event names, field names, screen names, and span names all match. Two caveats:

- `bd-shop-11-slow-rendering.json` matches Android-only frame detection; use
  `bd-shop-11b` for iOS.
- `bd-shop-05-anr-force-quit.json` matches on `anr_*` fields, which this app emits
  for main-thread hangs.

Use the **bd-cli** skill to deploy them, then filter by `platform == "ios"` (a
global field set at startup) to separate the two apps, or leave it off to compare
them.

iOS-specific workflows live in [`workflows/`](workflows/) and the dashboard
payload in [`dashboards/`](dashboards/). Everything is re-deployable as code:

```bash
./scripts/deploy-workflows.sh
```

That creates and deploys every `bd-shop-*` iOS workflow plus the two-tab
**Journey vs Crashes** dashboard. See [`workflows/README.md`](workflows/README.md)
for what each one shows, the `stop`/`update`/`deploy` rule for editing a live
workflow, and — measured, not inferred — the conditions under which a crash
*can* be the terminal node of a Sankey on iOS (`.activityBased()` sessions plus
a relaunch inside `inactivityThresholdMins`, which is what `bd-shop-19` needs)
and what `bd-shop-18` does instead when those conditions do not hold.

Two API quirks the committed payloads work around: `bd dashboard get` returns
neither `layout_settings` nor row positions, so the checked-in dashboard JSON is
the only complete record of its layout; and multi-entry chart-metadata files must
be sent alongside `--workflow-file`, never on their own.

### Span-timing workflows and dashboards

Beyond the crash/journey workflows above, `workflows/bd-shop-20` through
`bd-shop-24` cover every span added throughout the app — cold start, screen
loads, journey sub-phases, the recommendation engine, and local persistence
I/O — each with its own dashboard. Pull these up when demoing performance
instrumentation specifically:

| Dashboard | Live id | What it shows |
|---|---|---|
| [Cold-Start Span Timings](https://explorations.bitdrift.io/dashboards/1rik5G13l_cOcZMr_Oxka) | `1rik5G13l_cOcZMr_Oxka` | `app_cold_start` waterfall: `sdk_init` / `scene_render` / `state_restore` |
| [Screen Load Timings](https://explorations.bitdrift.io/dashboards/6nkAoIli6rgustvUJA2Es) | `6nkAoIli6rgustvUJA2Es` | 9 spans: "time to data ready" for 7 screens (Welcome, Browse, ProductDetail, Cart, Checkout, Payment, Confirmation — not every screen in the app) plus 2 sub-operations (catalog re-serialize, per-image load) |
| [Journey Sub-Phase Timings](https://explorations.bitdrift.io/dashboards/7jSnw6WcGPFxYA3D9YtF8) | `7jSnw6WcGPFxYA3D9YtF8` | `discovery_fetch` / `product_view` / `wishlist_add` / `cart_assembly` / `checkout.payment` / `checkout.confirmation` |
| [Recommendation Engine Timings](https://explorations.bitdrift.io/dashboards/gBqNwTjMdc0KKL4bRD64C) | `gBqNwTjMdc0KKL4bRD64C` | `score_products`: parse vs. the O(n·m) similarity pass |
| [Persistence I/O Timings](https://explorations.bitdrift.io/dashboards/GuxEP0btHJDxhTv5TtNrb) | `GuxEP0btHJDxhTv5TtNrb` | `screen_view_persist` vs. `demo_state_publish` |

These links are tied to *this* account's dashboard IDs (the table above) *and*
workflow IDs (`0pTX`, `t8u9`, `beLW`, `49io`, `qt3D` — see the "Live id" column
in [`workflows/README.md`](workflows/README.md#span-timings-beyond-cold-start-bd-shop-21-through-bd-shop-24)'s
table, not the dashboard table above). Deploying to a fresh account means
creating new workflows and dashboards, whose IDs will differ from both. Each
dashboard file's `chart_id.workflow.workflow_id` fields reference the
*workflow* id, so **edit those before creating the dashboard, not after** —
running `bd dashboard create` against the committed files as-is produces a
dashboard whose charts still point at the *old* account's workflows:

```bash
./scripts/deploy-workflows.sh --no-dash   # bd-shop-13 through bd-shop-24, prints each new id

cd workflows
# Each dashboard file has exactly one workflow_id to replace (grep -o
# '"workflow_id": "[^"]*"' <file> to confirm which). Substitute the old id
# for the new one deploy-workflows.sh just printed, THEN create — same as the
# guided crash dashboard's deploy-workflows.sh substitution, just not
# automated here since each of these five only has one workflow behind it.
sed -i '' 's/0pTX/<new-bd-shop-20-id>/' ../dashboards/ios-cold-start-span-timings.dashboard.json
bd dashboard create --request-file ../dashboards/ios-cold-start-span-timings.dashboard.json

sed -i '' 's/t8u9/<new-bd-shop-21-id>/' ../dashboards/ios-screen-load-timings.dashboard.json
bd dashboard create --request-file ../dashboards/ios-screen-load-timings.dashboard.json

sed -i '' 's/beLW/<new-bd-shop-22-id>/' ../dashboards/ios-journey-subphase-timings.dashboard.json
bd dashboard create --request-file ../dashboards/ios-journey-subphase-timings.dashboard.json

sed -i '' 's/49io/<new-bd-shop-23-id>/' ../dashboards/ios-recommendation-engine-timings.dashboard.json
bd dashboard create --request-file ../dashboards/ios-recommendation-engine-timings.dashboard.json

sed -i '' 's/qt3D/<new-bd-shop-24-id>/' ../dashboards/ios-persistence-timings.dashboard.json
bd dashboard create --request-file ../dashboards/ios-persistence-timings.dashboard.json
```

Don't run these `sed` commands against *this* account's own copies of the
files — they're meant for a one-time substitution when standing up a fresh
account, not for the checked-in files, which must keep referencing this
account's real IDs.

Before demoing these, two things worth doing first:

- **Make sure the backend is actually reachable.** Every span behind an API
  call (most of the Screen Load Timings dashboard) times out identically and
  silently if `.local.xcconfig`'s `SHOP_BACKEND_URL` has drifted — see the
  comment there and [`workflows/README.md`](workflows/README.md#a-live-example-of-why-the-unitslabels-matter-silent-backend-drift)
  for what that looks like on a chart (several unrelated spans reporting the
  exact same duration) and how it was caught.
- **Toggle Rec v2** if you want the Recommendation Engine dashboard populated
  — off by default, and nothing in the automated sim turns it on:
  ```bash
  xcrun simctl launch <udid> ai.bitdrift.shop.ios -recommendations.active 1
  ```

See [`workflows/README.md`](workflows/README.md) for the full per-workflow
breakdown, caveats (which spans are conditional/per-row, which only populate
under the full journey vs. the simplified one, session-boundary rules), and
the `ColdStartSpans`/`SpannedAsyncImage`/`CaptureBridge.trackSpan` source
pointers for each span.

## Project layout

```
ios/
├── BitdriftShop.xcodeproj/     Xcode project (SPM: capture-ios 0.23.11)
├── Info.plist                  Bundle config; xcconfig values surface here
├── local.xcconfig              Blank template; includes .local.xcconfig
├── scripts/                    watchdog.sh, check-demo-state.sh, demo-lib.sh
└── BitdriftShop/
    ├── BitdriftShopApp.swift   App entry, SDK start, scenePhase lifecycle logging
    ├── CaptureBridge.swift     SDK lifecycle, trackSpan, FieldProvider
    ├── ScreenLogger.swift      Central logging surface
    ├── AppConfig.swift         Info.plist/env-backed build config
    ├── DemoPrefs.swift         Namespaced UserDefaults
    ├── DemoStateFile.swift     Fault state published for the shell scripts
    ├── ApiClient.swift         Backend API
    ├── JSON.swift              Dynamic JSON reader
    ├── Screen.swift            Routes and screen names
    ├── Navigator.swift         NavigationStack driver + screen-view logging
    ├── ContentView.swift       Startup config, nav host, resume logic
    ├── Screens.swift           All 19 screens
    ├── Components.swift        Shared UI
    ├── SimulationManager.swift Journey simulator, fault injection, crash cycling
    ├── Crashes.swift           32-variant crash catalog
    ├── VendorSDKs.swift        Fake vendor namespaces for crash attribution
    ├── MetricsDemo.swift       Waveform + latency metrics
    ├── RecommendationEngine.swift  The slow-rendering trap
    └── OrderSummaryHelper.swift
```

## Requirements

- Xcode 16 or later (developed against Xcode 26)
- iOS 16.0+ deployment target
- The [backend](../backend/) running on port 5173
