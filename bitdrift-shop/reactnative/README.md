# Bitdrift Shop — React Native (SDK)

**Version 5.0**

A demo React Native app simulating an e-commerce shopping experience with realistic, randomised user journeys, **instrumented with the [bitdrift Capture SDK](https://docs.bitdrift.io)** (`@bitdrift/react-native`) — screen views, structured logging, HTTP timing, app launch TTI, spans, feature flags, and crash reporting.

---

## Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| Node.js | 18+ | |
| Xcode | 16+ | macOS only; iOS Simulator required |
| CocoaPods | latest | `brew install cocoapods` |
| Watchman | latest | `brew install watchman` (required by Metro) |
| Android Studio | latest | Android emulator only |
| **JDK 17** | **17 exactly** | Android only — newer JDKs fail, see below |
| Docker | latest | For the backend. This repo uses [Colima](https://github.com/abiosoft/colima), not Docker Desktop |
| ios-deploy | latest | Physical iOS device only. `brew install ios-deploy` |

### JDK 17 (Android only)

Gradle 8.10.2 cannot run on Java 24+, and Android Studio bundles a Java 25 JBR that `./gradlew` picks up by default.

```bash
brew install --cask temurin@17
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
```

No sudo? Unpack the same build into your home directory instead:

```bash
curl -L -o /tmp/t17.tar.gz "https://api.adoptium.net/v3/binary/latest/17/ga/mac/aarch64/jdk/hotspot/normal/eclipse"
mkdir -p ~/Library/Java/JavaVirtualMachines && tar xzf /tmp/t17.tar.gz -C ~/Library/Java/JavaVirtualMachines/
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
```

`./start.sh android` finds a JDK 17 automatically if one is installed.

### Pinned tooling — do not "upgrade" these

| Package | Pin | Why |
|---------|-----|-----|
| `@react-native-community/cli` (+ both platform packages) | `15.1.3` exact | RN 0.77.3 targets CLI 15.x. CLI 16+ changed the middleware contract and Metro dies at startup with `Cannot read properties of undefined (reading 'handle')`. |
| `react-native-screens` | `3.x` | Not New-Architecture compatible; `ios/Podfile` sets `RCT_NEW_ARCH_ENABLED=0`. |

---

## Configuration

All environment-specific values live in `src/config.ts`, which reads `.env` at bundle time.

```bash
cp .env.example .env
```

| Variable | Required | Notes |
|----------|----------|-------|
| `BITDRIFT_API_KEY` | yes | Your bitdrift SDK key — get one at [app.bitdrift.io](https://app.bitdrift.io) |
| `BITDRIFT_API_HOST` | no | Passed as `url` to `init()`. Omit for the default endpoint; set for staging/on-premise |
| `BACKEND_PORT` | no | Defaults to `5173` |

`.env` is gitignored — never commit it. The correct backend host for iOS Simulator (`127.0.0.1`) and Android Emulator (`10.0.2.2`) is selected automatically.

---

## Quick Start

### 1. Start the backend

```bash
colima start          # first time, or if `docker ps` errors
cd ../backend && ./start-backend-docker.sh
```

Runs on `http://localhost:5173` (docs at `/docs`). See `../backend/README.md` for full Colima setup.

### 2. Run the app

```bash
./start.sh          # install deps + start Metro
./start.sh ios      # + CocoaPods + launch iOS simulator
./start.sh android  # + launch Android emulator (handles JAVA_HOME and Metro)
```

Or manually:

```bash
npm install
cd ios && pod install && cd ..     # iOS, first time
npm start                          # Metro — leave running in its own terminal
npm run ios                        # or: npm run android
```

**Metro must be running or the app shows a blank white screen.** `run-ios` / `run-android` try to open Metro in a new terminal window, which silently does nothing on a headless shell (CI, ssh, an agent). Verify with `curl http://localhost:8081/status` → `packager-status:running`.

Two more things worth knowing:

- **After changing `.env`,** restart Metro with `--reset-cache`. Values are inlined at transform time, so a warm cache keeps serving the old SDK key.
- **On a headless shell,** boot the simulator/emulator yourself first — neither command does it for you:
  ```bash
  xcrun simctl boot "iPhone 16e"     # or: open -a Simulator
  emulator -avd <AVD_NAME> &         # list with: emulator -list-avds
  ```

One Metro serves both platforms.

### Cleanup

```bash
./cleanup.sh     # removes node_modules, Pods, build outputs, Metro caches
```

---

## bitdrift Instrumentation

Every bitdrift call funnels through `src/utils/logger.ts`.

| Feature | API | Where |
|---------|-----|-------|
| **SDK Init** | `init(apiKey, SessionStrategy.Activity)` | `App.tsx` |
| **Screen Views** | `logScreenView(name)` on every screen | `ScreenContainer.tsx` |
| **App Launch TTI** | `logAppLaunchTTI()` + `app_cold_start` span | `App.tsx` |
| **Lifecycle** | `app_open` / `app_close`; `memory_pressure` (iOS) | `appLifecycle.ts` |
| **HTTP capture** | method, path, status, duration on every call | `ApiClient.ts` |
| **Path templates** | `x-capture-path-template` on dynamic routes | `ApiClient.ts` |
| **Structured logs** | ~20 business events (`add_to_cart`, `checkout_started`, `payment_completed`, `payment_failed`, …) | `logger.ts`, screens |
| **Global fields** | `app_variant=sdk-demo` + `platform` + `ff_*` mirrors | `App.tsx`, `variants.ts` |
| **Entity ID** | `setEntityId()` per journey | `logger.ts` |
| **Feature flags** | `setFeatureFlagExposure()` ×8 (`checkout_flow`, `payment_ui`, `cart_abandon_rate`, `payment_android_pay`, `order_summary`, `anr_a`, `force_quit`, `recommendations_v2`) | `variants.ts` |
| **Spans** | `journey` → `product_discovery` / `checkout`, `score_products` | `logger.ts` |
| **Device Code** | `getDeviceID()` + button on Welcome | `ShoppingScreens.tsx` |
| **Support Log** | `getSessionURL()` button + `supportlog` field | `ShoppingScreens.tsx` |
| **Crash reporting** | 20-entry crash catalog + native signal module | `crashes.ts`, `BdCrash` |

### Advanced screen (button on Welcome)

- **Variants** — Control / A / B bias every decision in the simulation and drive the feature-flag exposures.
- **Simulation modes** — **Sim A/B** (5 journeys per variant) and **Cardinality** (hammers `/inventory/lookup/<item>/<session>` with unique URLs to demonstrate the path-template fix).
- **Fault injection** — **Slow** (heavy on-thread recommendation scoring, drives `recommendations_v2`), **Crash** (cycles the 20-crash catalog), **ANR-A** (blocks the UI thread), **Quit** (hard process exit). Each records a flag exposure and an `*_injected` event.
- **Support Log** toggle sets the `supportlog` global field.

### RN SDK differences

The RN SDK has no span API, so spans are emitted as paired start/end logs carrying `_span_id` and `_duration_ms` — the same shape bitdrift's span feature produces. It also has no "new session" call, so the app uses `SessionStrategy.Activity` and emits a `journey_started` marker per journey. `memory_pressure` is wired on iOS only (Android would need a native module), and the crash loop does not auto-restart the process the way the Android demo does.

### Native crash module (`BdCrash`)

Native-signal crashes (`SIGSEGV/SIGBUS/SIGABRT/SIGFPE`), true ANR and force-quit need a native module:

- **Android** — `android/app/src/main/java/ai/bitdrift/shop/BdCrashModule.kt` (+ `BdCrashPackage.kt`). Works after a Gradle rebuild.
- **iOS** — `ios/ShopDemoRN/BdCrash.m`. **Add it to the `ShopDemoRN` target in Xcode** before it compiles.

Without it these fall back to a labelled JS error so the app still runs. JS-portable crashes (null deref, stack overflow, …) need no native code.

---

## Simulation Mode

Welcome has **Sim 10**, **Sim 100** and **∞ Sim** buttons driving fully automated journeys through the funnel:

`Welcome → Browse / Search / Categories → ProductDetail → Reviews / Wishlist → Cart → Checkout (Guest or Sign-in) → Payment (Card / Apple Pay / PayPal / Google Pay) → Confirmation`

Each journey is a probabilistic state machine whose branch weights are biased by the active variant (Control baseline below; Variant A is a snap-decision digital native, Variant B a deliberate card payer):

| Step | Choices (Control) |
|------|---------|
| Discovery | Browse / Search / Categories→CategoryBrowse |
| After listing | 50% visit Featured |
| Product | 50% read Reviews, 40% add to Wishlist |
| Cart | add 1–3 extra items, 60% remove one, 20% empty+re-add, 30% flip one |
| Checkout | 50% Guest / 50% Sign-in |
| Payment | Card / Apple Pay / PayPal / Google Pay (equal weight) |

Journeys may abandon at cart or checkout, or hit a payment failure (50% retry). Exact per-variant probabilities are in `src/sim/variants.ts`.

---

## Key files

```
App.tsx                        SDK init, TTI, global fields, root navigator
src/config.ts                  SDK key + backend URL (reads .env)
src/api/ApiClient.ts           HTTP client, path templates, cardinality demo
src/utils/logger.ts            All bitdrift wrappers: logs, fields, entity, flags, spans
src/utils/appLifecycle.ts      app_open / app_close / memory_pressure
src/context/SimulationContext.tsx   Variant-biased state machine, spans, chaos
src/sim/variants.ts            Personas, probabilities, feature-flag mapping
src/sim/crashes.ts             20-crash catalog + native-module bridge
src/sim/recommendations.ts     Levenshtein scoring behind the Slow toggle
src/screens/ShoppingScreens.tsx     All 19 screens incl. Advanced
```

The app talks to the FastAPI backend over plain `fetch`; host selection per platform is automatic in `src/config.ts`.

---

## Logs & Debugging

`logger.ts` mirrors every bitdrift call to `console.*`, so the JS console shows the same events the SDK ships.

**Android:**
```bash
adb logcat -s ReactNativeJS:V                                   # JS console only
adb logcat ReactNativeJS:V ReactNative:V AndroidRuntime:E *:S   # + framework + crashes
```

**iOS Simulator:**
```bash
xcrun simctl spawn booted log stream --level info --style compact \
  --predicate 'subsystem == "com.facebook.react.log"'
```

Both flags matter: `--level info` is required (RN logs at Info, and `log stream` defaults to Default-and-above, so without it you see almost nothing), and filtering on `subsystem` rather than the process keeps CFNetwork chatter out — roughly 180 useful lines instead of 7,400. Use a UDID instead of `booted` if several simulators are running.

Expect output like:

```
I ReactNativeJS: [INFO] journey_started | run=2 | variant=Control
I ReactNativeJS: _screen_name: ProductDetail
I ReactNativeJS: [DEBUG] api_response | duration_ms=277 | method=GET | path=/product/<id> | status=200
```

**Note:** as of RN 0.77 the Metro terminal no longer prints `console.*` — it only shows bundling and transform errors. The two commands above are the quickest way to watch a run, and the only way to watch one headlessly.

**Metro itself:**
```bash
tail -f /tmp/metro-shop.log                   # when started by ./start.sh
curl http://localhost:8081/status             # -> packager-status:running

# force a full bundle build to surface syntax/import errors without launching:
curl -o /dev/null -w '%{http_code}\n' 'http://localhost:8081/index.bundle?platform=ios&dev=true&minify=false'
```

**React Native DevTools** — press `j` in the Metro terminal, or open `http://localhost:8081/debugger-frontend/`.

**bitdrift platform** — the SDK ships to bitdrift, not to disk. Use the **Device Code** button with `bd tail`, or **Support Log** to copy the session URL.

**Build logs** — neither toolchain writes a plain-text log, so redirect anything you want to keep (`npm run android 2>&1 | tee /tmp/android-build.log`). When Gradle fails opaquely, re-run it directly with `./gradlew installDebug --stacktrace --info`.

---

## Troubleshooting

**Blank white screen / "No bundle URL present"** — Metro isn't running. Start it (`npm start`) and confirm `curl http://localhost:8081/status`.

**Metro exits with `Cannot read properties of undefined (reading 'handle')`** — `@react-native-community/cli` was upgraded past 15.x. The trace blames `connect`, which is misleading. This does *not* break the native build, so it shows up as a white screen. Restore the pin:
```bash
npm install --save-exact --save-dev @react-native-community/cli@15.1.3 \
  @react-native-community/cli-platform-android@15.1.3 @react-native-community/cli-platform-ios@15.1.3
```

**`react-native depends on @react-native-community/cli for cli commands`** — you ran `npx react-native ...` from outside this directory. `cd` here first. **Do not** follow the warning's advice to install `@react-native-community/cli@latest` — that installs CLI 20 and breaks Metro.

**`None of your spec sources contain a spec satisfying BitdriftCapture (= x.y.z)`** — your CocoaPods spec cache predates the release. `cd ios && pod install --repo-update` (the first one clones the whole CDN index and takes several minutes).

**Pod install otherwise fails** — `cd ios && pod deintegrate && pod cache clean --all && pod install`

**`consteval` errors (Xcode 26+)** — the `post_install` hook in `ios/Podfile` patches `fmt/base.h`. Run `pod install`, then rebuild.

**"Command PhaseScriptExecution failed"** — Xcode can't find Node:
```bash
echo "export NODE_BINARY=$(which node)" > ios/.xcode.env.local
```
Then clean (⌘⇧K) and rebuild.

**"EMFILE: too many open files"** — `brew install watchman`

**Metro cache issues** — `npx react-native start --reset-cache`

**Build errors after updating deps** — `rm -rf node_modules ios/Pods ios/Podfile.lock && npm install && cd ios && pod install`

**Android build fails on Java version** (`Unsupported class file major version`, or the daemon dies at startup) — Gradle 8.10.2 needs JDK 17; Android Studio's JBR is Java 25. `export JAVA_HOME=$(/usr/libexec/java_home -v 17)`.

**First Android build takes 10+ minutes** — Gradle downloads NDK 27.1.12297006 (~2.4 GB) and CMake 3.22.1. One-time.

**Android emulator `offline` / `authorizing`** — `adb kill-server && adb start-server`. If still offline, cold boot it: `adb emu kill`, wait for it to exit, then `emulator -avd <AVD_NAME> -no-snapshot-load &`.

**`INSTALL_FAILED_UPDATE_INCOMPATIBLE`** — an old build with a different signing key is installed. `adb uninstall ai.bitdrift.shop`.

**`INSTALL_FAILED_INSUFFICIENT_STORAGE`** — the emulator's `/data` is full (`adb shell df -h /data`). The debug APK is ~120 MB across four ABIs and needs roughly double that free; a default 6 GB AVD is mostly consumed by the Google Play system image. In increasing order of destructiveness:
```bash
adb shell pm trim-caches 3000M          # rarely enough alone
adb uninstall ai.bitdrift.shop
# raise the partition (non-destructive, needs restart):
#   ~/.android/avd/<AVD_NAME>.avd/config.ini -> disk.dataPartition.size=12G
# factory reset (destroys all device data) — stop the emulator first or this fails:
adb emu kill
emulator -avd <AVD_NAME> -wipe-data -no-snapshot-load &
```

---

## Upgrading the bitdrift SDK

`@bitdrift/react-native` pins an exact native `BitdriftCapture` version, so a JS bump always needs a matching pod resolve.

```bash
npm view @bitdrift/react-native version        # latest published
npm install @bitdrift/react-native@<version> --save
cd ios && pod install --repo-update && cd ..   # --repo-update is required
npx tsc --noEmit                               # catch removed/renamed APIs
```

Android needs no extra step — Gradle resolves the Maven artifact on the next build. Because everything the app imports funnels through `logger.ts`, `tsc --noEmit` reliably catches an upgrade that drops an API this demo uses.

---

## Building

**iOS release (device)**
```bash
npx react-native run-ios --scheme BitdriftShop --configuration Release --device
```
For App Store distribution open `ios/ShopDemoRN.xcworkspace` in Xcode and use **Product → Archive**. The scheme is `BitdriftShop`.

**Android release**
```bash
cd android && ./gradlew assembleRelease     # APK: app/build/outputs/apk/release/
cd android && ./gradlew bundleRelease       # AAB for Play Store
```

---

## VS Code (optional)

Everything above works from a terminal alone. This is only for people who want live logs in VS Code's **Debug Console** via the `msjsdiag.vscode-react-native` extension.

This app runs on **Hermes**, and the extension ships two attach configs that look interchangeable but are not:

| Config | `type` | Result on Hermes |
| --- | --- | --- |
| "Attach to packager" | `reactnative` | Connects and logs *"Established a connection with the Proxy (Packager)"* — but the Debug Console stays **empty forever** |
| "Attach to Hermes application - Experimental" | `reactnativedirect` | Connects **and** streams console output |

The trap is that the wrong one reports success, so a clean "connection established" message is not proof you are seeing logs.

Both configs are checked in at [`.vscode/launch.json`](.vscode/launch.json). To use it: launch the app first (`./start.sh ios|android`), then Run and Debug (⇧⌘D) → select **"Attach to Hermes application - Experimental"** → F5, and watch the **Debug Console** tab.
