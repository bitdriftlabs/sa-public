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
| Python | 3.10+ | for the backend |

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
npm run ios                        # launch iOS simulator
npm run android                    # launch Android emulator
npm start                          # Metro bundler only
```

### Cleanup

```bash
chmod +x cleanup.sh && ./cleanup.sh
```

Removes `node_modules`, iOS Pods/build, Android build outputs, Metro caches, and `.DS_Store` files.

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

## Troubleshooting

**"EMFILE: too many open files"** — Install Watchman: `brew install watchman`

**Pod install fails:**
```bash
cd ios && pod deintegrate && pod cache clean --all && pod install
```

**Build fails with `consteval` errors (Xcode 26+):** The `post_install` hook in `ios/Podfile` patches `fmt/base.h` automatically on `pod install`. If you see these errors, run `pod install` first, then rebuild.

**"Command PhaseScriptExecution failed"** — Xcode can't find Node:
```bash
echo "export NODE_BINARY=$(which node)" > ios/.xcode.env.local
```
Then clean (⌘⇧K) and rebuild.

**"No bundle URL present"** — Metro isn't running. Start it with `npm start`, then relaunch.

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

---

## Building

### iOS — Debug (simulator)

```bash
npm install
cd ios && pod install && cd ..
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
npm run android
# or: ./start.sh android
```

### Android — Release

```bash
cd android
./gradlew assembleRelease
# APK: android/app/build/outputs/apk/release/app-release.apk
# AAB (Play Store): ./gradlew bundleRelease
```
