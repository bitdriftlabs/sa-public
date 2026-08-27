# Bitdrift Shop — React Native (SDK)

A demo React Native app simulating an e-commerce shopping experience with realistic, randomised user journeys. This version is **instrumented with the [bitdrift Capture SDK](https://docs.bitdrift.io)** (`@bitdrift/react-native`), demonstrating screen views, structured logging, HTTP timing, app launch TTI, and global fields.

---

## Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| Node.js | 18+ | |
| npm | bundled with Node | |
| Xcode | 16+ | macOS only; iOS Simulator required |
| CocoaPods | latest | `brew install cocoapods` |
| Watchman | latest | `brew install watchman` (required by Metro) |
| ios-deploy | latest | `brew install ios-deploy` |
| Android Studio | latest | Android emulator only |
| **JDK 17** | **17 (exactly)** | **Android only. `brew install --cask temurin@17`. See below — newer JDKs do not work.** |
| Python | 3.10+ | for the backend |

### JDK 17 is required for Android

The Android build uses Gradle 8.10.2, which cannot run on Java 24+. Android Studio now
bundles a Java 25 JBR, so `./gradlew` picks that up by default and fails. Install Temurin 17
and point `JAVA_HOME` at it for Android builds:

```bash
brew install --cask temurin@17
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
```

If you cannot use `sudo` (the cask installs system-wide), the same build can be unpacked
into your home directory instead:

```bash
curl -L -o /tmp/temurin17.tar.gz \
  "https://api.adoptium.net/v3/binary/latest/17/ga/mac/aarch64/jdk/hotspot/normal/eclipse"
mkdir -p ~/Library/Java/JavaVirtualMachines
tar xzf /tmp/temurin17.tar.gz -C ~/Library/Java/JavaVirtualMachines/
export JAVA_HOME=~/Library/Java/JavaVirtualMachines/jdk-17.0.20.1+1/Contents/Home
```

Verify with `java -version` — it must report `17.x`, and for Temurin the string reads
`OpenJDK Runtime Environment Temurin-17.x`. (`java version` + `Java(TM) SE` instead of
`openjdk version` + `OpenJDK` means you are on Oracle JDK, which also works but carries
Oracle's licence terms.)

### Pinned tooling — do not "upgrade" these

| Package | Pin | Why |
|---------|-----|-----|
| `@react-native-community/cli` (+ `-platform-ios`, `-platform-android`) | `15.1.3` exact | RN 0.77.3 bundles `@react-native/community-cli-plugin@0.77.3`, which targets CLI 15.x. CLI 16+ changed the middleware contract and Metro crashes on startup with `Cannot read properties of undefined (reading 'handle')`. |
| `react-native-screens` | `3.x` | Not New-Architecture compatible; `ios/Podfile` sets `RCT_NEW_ARCH_ENABLED=0` for this reason. |

---

## Configuration

All secrets and environment-specific values live in `src/config.ts`, which reads from a `.env` file at bundle time.

### 1. Create your `.env`

```bash
cp .env.example .env
```

Edit `.env` and fill in your bitdrift API key:

```
BITDRIFT_API_KEY=your_api_key_here
```

Get a key at **https://app.bitdrift.io**. The `.env` file is gitignored — never commit it.

### 2. (Optional) Override the bitdrift API host

```
BITDRIFT_API_HOST=api.bitdrift.dev
```

When set, this value is passed as the `url` option to the SDK's `init()` call. Omit it (or leave it blank) to use the SDK's built-in default endpoint. Useful for pointing at a staging or on-premise bitdrift instance.

### 3. (Optional) Change the backend port

```
BACKEND_PORT=5173
```

The default is `5173`. The correct host for iOS Simulator (`127.0.0.1`) and Android Emulator (`10.0.2.2`) is selected automatically in `src/config.ts`.

---

## Quick Start

### 1. Start the Backend

```bash
cd ../backend
./start-backend-docker.sh
```

API server runs on `http://localhost:5173`. Docs at `http://localhost:5173/docs`.

### 2. Run the App

```bash
chmod +x start.sh

./start.sh          # install deps + start Metro bundler
./start.sh ios      # install deps + CocoaPods + launch iOS simulator
./start.sh android  # install deps + launch Android emulator
```

Or use npm scripts directly:

```bash
npm install                        # install dependencies (first time)
cd ios && pod install && cd ..     # install CocoaPods (iOS, first time)
npm start                          # Metro bundler (leave running in its own terminal)
npm run ios                        # launch iOS simulator
npm run android                    # launch Android emulator
```

**Metro must be running before the app will show anything.** `run-ios` / `run-android` try to
open Metro in a new terminal window; if you are on a headless shell (CI, ssh, an agent) that
does not happen and the app launches to a blank white screen. Start it yourself first and
confirm:

```bash
npm start                                   # or: npx react-native start --reset-cache
curl http://localhost:8081/status           # -> packager-status:running
```

Use `--reset-cache` whenever `.env` changes: `react-native-dotenv` inlines those values at
transform time, so a warm Metro cache will keep serving a bundle built with the old API key.

One Metro serves both platforms — the iOS Simulator reaches it on `localhost:8081` and the
Android emulator on `10.0.2.2:8081`, both automatically.

### Cleanup

```bash
chmod +x cleanup.sh && ./cleanup.sh
```

Removes `node_modules`, iOS Pods/build, Android build outputs, Metro caches, and `.DS_Store` files.

---

## Upgrading the bitdrift SDK

`@bitdrift/react-native` pins an exact native `BitdriftCapture` version, so a JS-side bump
always requires a matching pod resolve.

```bash
npm view @bitdrift/react-native version                    # latest published
npm install @bitdrift/react-native@<version> --save
cd ios && pod install --repo-update && cd ..               # --repo-update is required
npx tsc --noEmit                                           # catch removed/renamed APIs
```

`--repo-update` is not optional: the new `BitdriftCapture` release is usually newer than your
local spec cache, and plain `pod install` fails with *"None of your spec sources contain a spec
satisfying the dependency: BitdriftCapture (= x.y.z)"*.

Android needs no extra step — the SDK's Maven artifact resolves through Gradle on the next
build.

Everything the app imports from the SDK funnels through `src/utils/logger.ts` (plus `init`
in `App.tsx` and `getSessionURL` / `getDeviceID` in `src/screens/ShoppingScreens.tsx`), so
`tsc --noEmit` is a reliable check that an upgrade didn't drop an API this demo relies on.

---

## bitdrift Instrumentation

This app is instrumented to **match the Android app** (`../android`) feature-for-feature.
All bitdrift calls funnel through `src/utils/logger.ts`.

| Feature | API | Where |
|---------|-----|-------|
| **SDK Init** | `init(apiKey, SessionStrategy.Activity)` | `App.tsx` |
| **Screen Views** | `logScreenView(name)` on every screen | `ScreenContainer.tsx` via `logger.ts` |
| **App Launch TTI** | `logAppLaunchTTI()` from module eval to first render | `App.tsx` |
| **Lifecycle events** | `app_open` / `app_close` via AppState | `appLifecycle.ts` |
| **HTTP capture** | every API call logs method, path, status, duration | `ApiClient.ts` |
| **Path templates** | `x-capture-path-template` on dynamic routes (product/category/order) | `ApiClient.ts` |
| **Structured logs** | `info/warn/error/debug` + ~20 business events (`add_to_cart`, `checkout_started`, `payment_completed`, `payment_failed`, …) | `logger.ts`, screens, `SimulationContext.tsx` |
| **Global fields** | `app_variant=sdk-demo` + `platform` + `ff_*` mirrors | `App.tsx`, `variants.ts` |
| **Entity ID** | `setEntityId()` per journey | `logger.ts`, `SimulationContext.tsx` |
| **Feature-flag exposures** | `setFeatureFlagExposure()` ×7 (`checkout_flow`, `payment_ui`, `cart_abandon_rate`, `payment_android_pay`, `order_summary`, `anr_a`, `force_quit`) | `variants.ts` |
| **Spans** | `journey` → `product_discovery` / `checkout` (+ `_duration_ms`) | `logger.ts`, `SimulationContext.tsx` |
| **Device Code** | `getDeviceID()` + POST `/v1/device/code` button | `ShoppingScreens.tsx` |
| **Support Log** | `getSessionURL()` button + `supportlog` field toggle | `ShoppingScreens.tsx`, Advanced screen |
| **Crash reporting** | 20-entry crash catalog + native signal module | `crashes.ts`, native `BdCrash` |

All configuration (API key, backend URL) is centralised in `src/config.ts`.

### Personas, simulation modes & chaos (Advanced screen)

The **Advanced** screen (button on Welcome) ports the Android app's controls:

- **Variants** — Control / Variant A / Variant B bias every decision in the simulation
  (discovery, reviews, wishlist, cart churn, guest-vs-signin, payment mix, failure/abandon
  rates) and drive the feature-flag exposures above.
- **Simulation modes** — **Sim A/B** (5 journeys each across all variants) and **Cardinality**
  (hammers `/inventory/lookup/<item>/<session>` with unique URLs to demonstrate the path-
  template fix).
- **Fault injection** — **Slow** (heavy on-thread recommendation scoring), **Crash** (cycles
  the 20-crash catalog at journey end), **ANR-A** (Variant A + guest checkout, blocks the UI
  thread), **Quit** (hard process exit on ProductDetail). Each records a feature-flag exposure
  and an `*_injected` event.
- **Support Log** toggle sets the `supportlog` global field.

### Platform parity notes (RN SDK differences)

A few Android behaviours can't be reproduced 1:1 with `@bitdrift/react-native@0.12.x`. These
are handled gracefully and documented in code:

- **Spans** — the RN SDK has no span API, so spans are reproduced as paired start/end logs
  carrying `_duration_ms` and `_span_id` (the same data shape bitdrift's span feature emits).
- **New session per journey** — not available in the RN SDK; the app uses
  `SessionStrategy.Activity` (rotates on inactivity) and emits a `journey_started` boundary
  marker instead.
- **Memory events** (`memory_pressure` / `low_memory`) — no cross-platform RN signal; left
  unwired (would need a native `onTrimMemory` / `didReceiveMemoryWarning` hook).
- **Crash auto-restart loop** — Android re-arms via `AlarmManager`; RN/iOS can't self-relaunch,
  so the crash loop fires crashes in sequence but does not auto-restart the process.

### Native crash module (`BdCrash`)

Native-signal crashes (`SIGSEGV/SIGBUS/SIGABRT/SIGFPE`), true ANR (main-thread block) and
force-quit need a native module:

- **Android** — `android/app/src/main/java/ai/bitdrift/shop/BdCrashModule.kt` (+ `BdCrashPackage.kt`,
  registered in `MainApplication.kt`). Works after a Gradle rebuild.
- **iOS** — `ios/ShopDemoRN/BdCrash.m`. **Add it to the `ShopDemoRN` target in Xcode** (or via
  `pod install` if using a synchronized group) before it compiles.

When the module isn't present (app not yet rebuilt), these crashes fall back to a labelled JS
error so the app still runs. JS-portable crashes (null deref, stack overflow, etc.) need no
native code.

---

## Screens

| Screen | Step | Description |
|--------|------|-------------|
| `Welcome` | 1 | Entry point, simulation controls |
| `Browse` | 2 | Product listing (8 random of 18) |
| `Search` | 2 | Keyword search results |
| `Featured` | 3 | Curated featured products |
| `Categories` | 3 | Category listing |
| `CategoryBrowse` | 3 | Products within a category |
| `ProductDetail` | 4 | Full product info |
| `Reviews` | 4 | Customer reviews + ratings |
| `Cart` | 5 | Cart with add/remove |
| `Wishlist` | 5 | Saved items |
| `CheckoutGuest` | 6 | Guest checkout |
| `CheckoutSignIn` | 6 | Member checkout with loyalty points |
| `PaymentCard` | 6 | Credit card payment |
| `PaymentApplePay` | 6 | Apple Pay |
| `PaymentPayPal` | 6 | PayPal |
| `PaymentAndroidPay` | 6 | Google Pay |
| `PaymentFailed` | 6 | Payment failure / retry |
| `Confirmation` | 7 | Order confirmation |
| `Advanced` | 1 | Variants, simulation modes, fault injection |

---

## Simulation Mode

The Welcome screen has **Sim 10**, **Sim 100**, and **∞ Sim** buttons that drive fully automated journeys through the shopping funnel. The **Advanced** screen adds **Sim A/B** and **Cardinality** modes and a **persona/variant** selector.

Each journey uses a probabilistic state machine whose branch weights are **biased by the active variant** (the table below is the Control baseline; Variant A is a snap-decision digital-native, Variant B a deliberate card-paying shopper):

| Step | Choices (Control) |
|------|---------|
| Discovery | Browse / Search / Categories→CategoryBrowse |
| After listing | 50% visit Featured |
| Product | 50% read Reviews, 40% add to Wishlist |
| Cart | add 1–3 extra items, 60% remove one, 20% empty+re-add, 30% flip one item |
| Checkout | 50% Guest / 50% Sign-in |
| Payment | Card / Apple Pay / PayPal / Google Pay (equal weight) |

Exact per-variant probabilities live in `src/sim/variants.ts`. Journeys may abandon at the
cart, at checkout, or on a payment failure (with a 50% retry); successful ones end at
Confirmation. Spans (`journey`, `product_discovery`, `checkout`) and an entity ID are emitted
per journey.

---

## Project Structure

```
reactnative/
├── .env.example                     # Copy to .env and add your API key
├── App.tsx                          # SDK init, TTI, global fields, root navigator
├── index.js                         # Entry point
├── start.sh                         # Convenience launch script
├── cleanup.sh                       # Remove build artifacts
└── src/
    ├── config.ts                    # API key + backend URL + APP_VARIANT (reads from .env)
    ├── api/
    │   └── ApiClient.ts             # HTTP client — endpoints, path templates, cardinality demo
    ├── components/
    │   ├── Buttons.tsx              # Primary / secondary / simulation buttons
    │   ├── ScreenContainer.tsx      # Shared layout, triggers logScreenView
    │   ├── SimulationOverlay.tsx    # Running simulation indicator + cancel
    │   ├── StepIndicator.tsx        # Journey progress dots
    │   └── index.ts
    ├── context/
    │   └── SimulationContext.tsx    # Persona-biased state machine, spans, entity, chaos
    ├── sim/
    │   ├── variants.ts              # SimVariant personas, probabilities, feature-flag mapping
    │   └── crashes.ts               # 20-crash catalog + native-module bridge (ANR / force-quit)
    ├── navigation/
    │   └── types.ts                 # Typed route params for all 19 screens
    ├── screens/
    │   ├── ShoppingScreens.tsx      # All screens incl. Advanced + payment variants
    │   └── index.ts
    ├── types/
    │   └── models.ts                # Typed backend response interfaces
    └── utils/
        ├── colors.ts                # Color palette
        ├── appLifecycle.ts          # app_open / app_close via AppState
        └── logger.ts                # bitdrift wrappers: logs, fields, entity, flags, spans

# Native crash module (rebuild required to activate):
#   android/app/src/main/java/ai/bitdrift/shop/BdCrashModule.kt + BdCrashPackage.kt
#   ios/ShopDemoRN/BdCrash.m   (add to the Xcode target)
```

---

## Architecture

```
┌─────────────────────┐    HTTP (fetch)    ┌──────────────────────┐
│   iOS Simulator      │ ◄────────────────► │  FastAPI Server       │
│   (127.0.0.1:5173)   │                   │  (localhost:5173)     │
└─────────────────────┘                    └──────────────────────┘

┌─────────────────────┐    HTTP (fetch)    ┌──────────────────────┐
│   Android Emulator   │ ◄────────────────► │  FastAPI Server       │
│   (10.0.2.2:5173)    │                   │  (localhost:5173)     │
└─────────────────────┘                    └──────────────────────┘
```

Host selection is automatic — see `src/config.ts`.

---

## Logs & Debugging

### Runtime logs (the app itself)

Every bitdrift call in this app funnels through `src/utils/logger.ts`, which mirrors each one
to `console.*` as well — so the JS console shows the same events the SDK is shipping.

**Android** — JS logs land in `logcat` under the `ReactNativeJS` tag:

```bash
adb logcat -s ReactNativeJS:V                                   # JS console only
adb logcat ReactNativeJS:V ReactNative:V AndroidRuntime:E *:S   # + framework + crashes
```

```
I ReactNativeJS: [INFO] journey_started | run=2 | variant=Control
I ReactNativeJS: _screen_name: ProductDetail
I ReactNativeJS: [DEBUG] api_response | duration_ms=277 | method=GET | path=/product/<id> | status=200
I ReactNativeJS: [INFO] checkout | _duration_ms=302 | _result=success | _span_type=end
```

Tag guide: `ReactNativeJS` = your `console.*`, `ReactNative` = bridge/framework,
`AndroidRuntime` = Java/Kotlin crashes.

**iOS Simulator** — JS logs go to the unified log under subsystem `com.facebook.react.log`:

```bash
xcrun simctl spawn booted log stream --level info --style compact \
  --predicate 'subsystem == "com.facebook.react.log"'
```

```
09:13:05.046 I BitdriftShop[43708] [com.facebook.react.log:javascript] _screen_name: Cart
09:13:05.100 I BitdriftShop[43708] [com.facebook.react.log:javascript] [INFO] add_to_cart | product_id=prod_m4n5o6 | source_screen=categories
09:13:05.100 I BitdriftShop[43708] [com.facebook.react.log:javascript] [INFO] product_discovery | _duration_ms=1948 | _result=success | _span_type=end
```

Both flags matter:

- **`--level info` is required.** RN emits JS logs at Info, and `log stream` shows only
  Default-and-above by default — without it you see nothing but the occasional `console.error`.
- **Filter on `subsystem`, not the process.** `--predicate 'processImagePath CONTAINS
  "BitdriftShop"'` also works but drowns the app's own output in CFNetwork and
  `com.apple.network` chatter — measured here at ~7,400 lines in 10s versus ~180 for the
  subsystem filter.

A leading `getpwuid_r did not find a match for uid 502` line is harmless `simctl` noise.

Replace `booted` with a UDID (`xcrun simctl list devices booted`) if more than one simulator
is running, otherwise `booted` is ambiguous.

The CLI also ships `npx react-native log-android` / `log-ios`, but `log-android` wraps
*logkitty*, which in practice often sits silent while `adb logcat` is streaming fine. Prefer
the `adb` commands above.

**`npx react-native <anything>` must be run from this directory.** From a parent directory
there is no local `node_modules`, and you get a misleading warning:

> ⚠️ react-native depends on @react-native-community/cli for cli commands. To fix update your
> package.json to include: `"@react-native-community/cli": "latest"`

**Do not follow that advice.** `latest` installs CLI 20, which breaks Metro (see
**Pinned tooling**). The actual fix is `cd` into the project first.

### Where JS console output does *not* go

As of RN 0.77 the Metro terminal no longer prints `console.*` — it says
*"JavaScript logs have moved! They can now be viewed in React Native DevTools."* Metro now
shows only bundling and transform errors, so don't wait on it for app output.

The native log pipelines are unaffected: Android still gets `ReactNativeJS` in `logcat`, and
iOS still gets `com.facebook.react.log` in the unified log. Those two commands remain the
quickest way to watch a run, and the only way to watch one headlessly.

### Metro

`./start.sh ios|android` runs Metro in the background and logs to a file; started by hand it
logs to that terminal.

```bash
tail -f /tmp/metro-shop.log                        # bundling, transform errors, red boxes
curl http://localhost:8081/status                  # -> packager-status:running
```

To force a full bundle build (and surface any syntax/import error without launching the app):

```bash
curl -o /dev/null -w '%{http_code}\n' \
  'http://localhost:8081/index.bundle?platform=ios&dev=true&minify=false'
```

### React Native DevTools

Console, network, and the Hermes debugger. Press `j` in the Metro terminal, or open
`http://localhost:8081/debugger-frontend/` directly if Metro is running non-interactively.

### bitdrift platform

The SDK ships to bitdrift rather than to disk. Use the **Device Code** button on the Welcome
screen with `bd tail`, or the **Support Log** button to copy the session URL.

### Build logs

Neither toolchain writes a plain-text build log by default, so **redirect any build you want
to keep** — `run-ios` / `run-android` output is otherwise lost when the terminal closes:

```bash
npm run android 2>&1 | tee /tmp/android-build.log
npm run ios     2>&1 | tee /tmp/ios-build.log
```

When a build fails opaquely, re-run Gradle directly with more detail:

```bash
cd android
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
./gradlew installDebug --stacktrace --info
```

What the toolchains *do* leave on disk:

```bash
# iOS — Xcode build records. These are gzipped .xcactivitylog files, not text; read them via
# Xcode's Report navigator (⌘9), or: gunzip -c <file>.xcactivitylog | strings | less
~/Library/Developer/Xcode/DerivedData/ShopDemoRN-*/Logs/Build/

# Android — the manifest merger report (useful for permission/activity merge conflicts).
# Gradle does not persist a general build log here.
android/app/build/outputs/logs/manifest-merger-debug-report.txt
```

Note there may be several `DerivedData/ShopDemoRN-*` directories; the newest is the one the
current checkout builds into (`ls -dt` to sort).

Anything under `/tmp` is scratch — macOS clears it on reboot. Copy a log somewhere durable if
you need to keep it.

---

## Troubleshooting

**"EMFILE: too many open files"** — Install Watchman: `brew install watchman`

**`react-native depends on @react-native-community/cli for cli commands`** — you are running
`npx react-native ...` from outside this directory, so there is no local `node_modules`. `cd`
into `bitdrift-shop/reactnative` first. **Ignore the warning's suggestion to install
`@react-native-community/cli@latest`** — that installs CLI 20 and breaks Metro (see
**Pinned tooling — do not "upgrade" these**).

**Pod install fails:**
```bash
cd ios && pod deintegrate && pod cache clean --all && pod install
```

**`None of your spec sources contain a spec satisfying the dependency: BitdriftCapture (= x.y.z)`**
— your local CocoaPods spec repo predates the `BitdriftCapture` release that the current
`@bitdrift/react-native` requires. Refresh it:

```bash
cd ios && pod install --repo-update
```

The first `--repo-update` clones the whole CDN spec index and takes several minutes. Expect
this every time the bitdrift SDK is upgraded to a version newer than your spec cache.

**Build fails with `consteval` errors (Xcode 26+):** The `post_install` hook in `ios/Podfile` patches `fmt/base.h` automatically on `pod install`. If you see these errors, run `pod install` first, then rebuild.

**"Command PhaseScriptExecution failed"** — Xcode can't find Node:
```bash
echo "export NODE_BINARY=$(which node)" > ios/.xcode.env.local
```
Then clean (⌘⇧K) and rebuild.

**"No bundle URL present", or the app launches to a blank white screen** — Metro isn't
running. `run-ios` / `run-android` only auto-start it by opening a new terminal window, which
silently does nothing on a headless shell. Start it yourself, verify, then relaunch the app:

```bash
npm start
curl http://localhost:8081/status     # -> packager-status:running
```

**Metro exits immediately with `Cannot read properties of undefined (reading 'handle')`** —
`@react-native-community/cli` has been upgraded past 15.x. RN 0.77.3's bundled
`community-cli-plugin` targets CLI 15, and CLI 16+ changed the middleware contract, so
Metro's `app.use()` receives `undefined`. The stack trace points at `connect/index.js`, which
is misleading — `connect` is not the problem. Restore the pin:

```bash
npm install --save-exact --save-dev \
  @react-native-community/cli@15.1.3 \
  @react-native-community/cli-platform-android@15.1.3 \
  @react-native-community/cli-platform-ios@15.1.3
```

Note this failure does **not** break `run-ios` / `run-android` — the native build succeeds and
the app installs and launches. Only the JS bundle is missing, so it presents as a white screen.

**Build errors after updating deps:**
```bash
rm -rf node_modules ios/Pods ios/Podfile.lock
npm install && cd ios && pod install
```

**Metro cache issues:**
```bash
npx react-native start --reset-cache
```

**Android emulator `offline` / `authorizing` / `Unknown API Level`** — adb lost sync with the emulator:
```bash
adb kill-server && adb start-server
```
If still offline, kill the emulator process and cold boot:
```bash
kill $(ps aux | grep qemu-system-aarch64 | grep -v grep | awk '{print $2}') 2>/dev/null
~/Library/Android/sdk/emulator/emulator -avd <AVD_NAME> -no-snapshot-load &
```
Wait for the home screen to appear, then run `./start.sh android`.

**Android `INSTALL_FAILED_UPDATE_INCOMPATIBLE`** — An old version with a different signing key is on the emulator:
```bash
adb uninstall ai.bitdrift.shop
```
Then re-run `./start.sh android`.

**Android `INSTALL_FAILED_INSUFFICIENT_STORAGE` / `Requested internal only, but not enough
space`** — the emulator's `/data` is full. The debug APK is ~120 MB because it bundles all
four ABIs, and Android needs roughly double that free to stage an install. Check it:

```bash
adb shell df -h /data
```

A default AVD has a 6 GB data partition, of which a Google Play system image already consumes
~5 GB, so this happens easily. In increasing order of destructiveness:

```bash
adb shell pm trim-caches 3000M          # frees cached data; usually not enough on its own
adb uninstall ai.bitdrift.shop          # reclaim the previous install

# raise the partition — non-destructive, keeps installed apps, needs a restart
#   ~/.android/avd/<AVD_NAME>.avd/config.ini -> disk.dataPartition.size=12G

# factory reset the AVD — frees everything, destroys all data on the device
adb emu kill
~/Library/Android/sdk/emulator/emulator -avd <AVD_NAME> -wipe-data -no-snapshot-load &
```

Note `adb root` is unavailable on Google Play system images, so you cannot inspect `/data`
usage in detail to find the culprit — the space is nearly always the system image itself.

**Android build fails on Java version** — Gradle daemon crashes on startup, `Unsupported class
file major version`, or an unhelpful `daemon has terminated unexpectedly`. Gradle 8.10.2
cannot run on Java 24+, and Android Studio's bundled JBR is now Java 25. Set `JAVA_HOME` to a
JDK 17 (see **Prerequisites → JDK 17 is required for Android**):

```bash
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
./gradlew installDebug
```

**First Android build takes 10+ minutes** — Gradle downloads NDK 27.1.12297006 (~2.4 GB) and
CMake 3.22.1, both pinned in `android/build.gradle`. This is one-time; later builds reuse them
from `~/Library/Android/sdk/`.

---

## Building

### iOS — Debug (simulator)

```bash
npm install
cd ios && pod install && cd ..     # add --repo-update after a bitdrift SDK bump
npm start &                        # Metro, if not already running
npm run ios
# or: ./start.sh ios
```

Open `ios/ShopDemoRN.xcworkspace` in Xcode for IDE access or to run on a physical device. The scheme is `BitdriftShop`.

### iOS — Release (device)

```bash
npx react-native run-ios --scheme BitdriftShop --configuration Release --device
```

For App Store distribution, open `ios/ShopDemoRN.xcworkspace` in Xcode, select a real device target, and use **Product → Archive**.

### Android — Debug (emulator)

```bash
# Start an AVD in Android Studio first, then:
export JAVA_HOME=$(/usr/libexec/java_home -v 17)   # Gradle 8.10.2 needs JDK 17
npm start &                                        # Metro, if not already running
npm run android
# or: ./start.sh android   (handles JAVA_HOME and Metro for you)
```

The first run downloads NDK 27.1.12297006 (~2.4 GB) and CMake 3.22.1, so budget 10+ minutes.
The debug APK is ~120 MB (all four ABIs) and needs ~2x that free on the emulator — see
**Troubleshooting** if the install fails for space.

### Android — Release

```bash
cd android
./gradlew assembleRelease
# APK: android/app/build/outputs/apk/release/app-release.apk
# AAB (Play Store): ./gradlew bundleRelease
```
