]633;E;head -n 285 /Volumes/external/code/bitdrift/bitdrift-shop/reactnative/sdk/README.md;818a1407-0e14-425d-b22e-bfd7865ac1ec]633;C# Bitdrift Shop — React Native (SDK)

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
cd ../../backend
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

This app exercises the following SDK features:

| Workshop | Feature | Where |
|----------|---------|-------|
| 1 | **SDK Init** — `init(apiKey, SessionStrategy.Activity)` | `App.tsx` |
| 2 | **Screen Views** — `logScreenView(name)` on every screen | `ScreenContainer.tsx` via `logger.ts` |
| 3 | **App Launch TTI** — measured from module eval to first render | `App.tsx` |
| 4b | **HTTP Timing** — every API call logs method, path, status, duration | `ApiClient.ts` |
| 4c | **Structured Logging** — `debug/info/warning/error` with typed fields | `logger.ts`, `SimulationContext.tsx` |
| 5 | **Global Fields** — `app_variant` + `platform` on every log | `App.tsx` |
| 6 | **Device Code** — `getDeviceID()` + POST `/v1/device/code` button on Welcome screen | `ShoppingScreens.tsx` |
| 7 | **Support Log** — `getSessionURL()` button on Welcome screen | `ShoppingScreens.tsx` |

All configuration (API key, backend URL) is centralised in `src/config.ts`.

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
| `Confirmation` | 7 | Order confirmation |

---

## Simulation Mode

The Welcome screen has **Sim 10**, **Sim 100**, and **∞ Sim** buttons that drive fully automated journeys through the shopping funnel.

Each journey uses a probabilistic state machine — random branches at every decision point produce realistic, unique sessions:

| Step | Choices |
|------|---------|
| Discovery | Browse / Search / Categories→CategoryBrowse |
| After listing | 50% visit Featured |
| Product | 50% read Reviews, 40% add to Wishlist |
| Cart | add 1–3 extra items, 60% remove one, 20% empty+re-add, 30% flip one item |
| Checkout | 50% Guest / 50% Sign-in |
| Payment | Card / Apple Pay / PayPal (equal weight) |

Every journey ends at Confirmation.

---

## Project Structure

```
sdk/
├── .env.example                     # Copy to .env and add your API key
├── App.tsx                          # SDK init, TTI, global fields, root navigator
├── index.js                         # Entry point
├── start.sh                         # Convenience launch script
├── cleanup.sh                       # Remove build artifacts
└── src/
    ├── config.ts                    # API key + backend URL (reads from .env)
    ├── api/
    │   └── ApiClient.ts             # HTTP client — all endpoints, timed + logged
    ├── components/
    │   ├── Buttons.tsx              # Primary / secondary / simulation buttons
    │   ├── ScreenContainer.tsx      # Shared layout, triggers logScreenView
    │   ├── SimulationOverlay.tsx    # Running simulation indicator + cancel
    │   ├── StepIndicator.tsx        # Journey progress dots
    │   └── index.ts
    ├── context/
    │   └── SimulationContext.tsx    # Probabilistic state machine + navigation driver
    ├── navigation/
    │   └── types.ts                 # Typed route params for all 16 screens
    ├── screens/
    │   ├── ShoppingScreens.tsx      # All 16 screen components
    │   └── index.ts
    ├── types/
    │   └── models.ts                # Typed backend response interfaces
    └── utils/
        ├── colors.ts                # Color palette
        └── logger.ts                # bitdrift + console dual-write logger
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
