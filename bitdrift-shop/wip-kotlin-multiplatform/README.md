# Bitdrift Shop — Kotlin Multiplatform

KMP e-commerce demo sharing business logic across **Android** (Jetpack Compose) and **iOS** (SwiftUI), instrumented with the bitdrift Capture SDK.

KMP is not fully officially supported by bitdrift SDK yet- this is a work in process and results will vary.

---

## Prerequisites

- JDK 17+, Android Studio, Xcode 15+
- Backend running — `cd ../backend && ./start-backend-docker.sh`

---

## Setup

### Android

1. Copy the secret properties file:
   ```bash
   cp .local.properties.example .local.properties   # or create it manually
   ```
   Fill in your values:
   ```
   BITDRIFT_SDK_KEY=<your-key>
   BITDRIFT_API_HOST=api.bitdrift.io
   ```
2. Open `kotlin-multiplatform/` in Android Studio.
3. Run the `androidApp` configuration on a device or emulator.

### iOS

1. Copy the xcconfig:
   ```bash
   cp iosApp/iosApp/.local.xcconfig.example iosApp/iosApp/.local.xcconfig   # or create it manually
   ```
   Fill in:
   ```
   BITDRIFT_SDK_KEY = <your-key>
   BITDRIFT_API_HOST = api.bitdrift.io
   ```
2. In Xcode: **Project → Info → Configurations** — set Debug and Release to use `iosApp/iosApp/.local.xcconfig`.
3. Build the shared framework:
   ```bash
   ./scripts/build-ios-framework.sh
   ```
4. Open and run:
   ```bash
   open iosApp/iosApp.xcodeproj
   ```
   Select a simulator and run.

---

## bitdrift Instrumentation

| Feature | Android | iOS |
|---|---|---|
| SDK init | `ShoppingDemoApp.kt` (`onCreate`) | `ShoppingDemoKMPApp.swift` (`init`) |
| SDK version | `0.23.6` | `0.23.6` |
| Screen views | `ScreenLogger.android.kt` → `Logger.logScreenView` | `ScreenLogger.swift` → `Logger.logScreenView` |
| Network capture | `CaptureOkHttpEventListenerFactory` (OkHttp) | URLSession swizzling (`enableIntegrations([.urlSession()])`) |
| Path templates | `x-capture-path-template` header on dynamic routes | same (via Ktor) |
| Structured logs | `Logger.logInfo/Debug/Warning/Error` | `Logger.logInfo/Debug/Warning/Error` |
| Spans | `ScreenLogger.startSpan` + `Span.end` (journey / discovery / checkout) | same |
| Business events | `add_to_cart`, `checkout_started`, `payment_completed`, `payment_failed`, `cart_abandoned`, `cart_item_removed`, `add_to_wishlist`, `checkout_abandoned`, `journey_started` | same |
| Feature flag exposures | `Logger.setFeatureFlagExposure` for 7 flags | same |
| Entity IDs | `Logger.setEntityId` (Marx Brothers + Stooges + Abbott & Costello) | same |
| App launch TTI | `Logger.logAppLaunchTTI()` | `Logger.logAppLaunchTTI` |
| Global fields | `app_variant=kmp-demo`, `platform=android` | `app_variant=kmp-demo`, `platform=ios` |
| 20-crash catalog | `Crashes.kt` / `Crashes.android.kt` | `Crashes.kt` / `Crashes.ios.kt` |
| ANR injection | Variant A + guest checkout path | main-thread sleep (iOS) |
| Force-quit injection | `Process.killProcess` at ProductDetail | `exitProcess(0)` at ProductDetail |
| A/B simulation | 3 variants × 5 journeys | same |
| Cardinality demo | `/inventory/lookup/:item/:sessionId` with unique 16-char hex IDs | same |
| API host override | `BITDRIFT_API_HOST` in `.local.properties` or env var | `BITDRIFT_API_HOST` in `.local.xcconfig` or env var |

**SDK key** — never committed. Loaded from:
- Android: `.local.properties` → `BuildConfig.BITDRIFT_SDK_KEY` (falls back to env var `BITDRIFT_SDK_KEY`)
- iOS: `iosApp/iosApp/.local.xcconfig` → `Info.plist` `$(BITDRIFT_SDK_KEY)` / `$(BITDRIFT_API_HOST)` (falls back to env vars; host defaults to `api.bitdrift.io`)

**Dashboard filtering** — both platforms report to the same bitdrift app (same SDK key). Use the built-in `os` field (`android` / `ios`) to split by platform, or `app_variant = kmp-demo` to distinguish from the non-KMP Android demo.

---

## Architecture

```
shared/src/commonMain/     # Models, ApiClient, SimulationEngine, ScreenLogger, SimVariants, Crashes (expect)
shared/src/androidMain/    # OkHttp + CaptureOkHttpEventListenerFactory, Logger actuals, Crashes.android
shared/src/iosMain/        # Darwin engine, Logger actuals (bitdrift runs at Swift layer), Crashes.ios, IosAsyncHelper
androidApp/                # Jetpack Compose UI, ShoppingDemoApp (Logger.start)
iosApp/                    # SwiftUI UI, ShoppingDemoKMPApp (Logger.start), ScreenLogger.swift
```

---

## Shared Modules

| Module | Contents |
|---|---|
| `shared/src/commonMain/.../Models.kt` | 20+ `@Serializable` data classes |
| `shared/src/commonMain/.../ApiClient.kt` | Ktor HTTP client, 19 endpoints + path-template headers |
| `shared/src/commonMain/.../SimulationEngine.kt` | Variant-biased journey engine with spans, business events, chaos |
| `shared/src/commonMain/.../ScreenLogger.kt` | expect/actual logging — delegates to platform bitdrift calls |
| `shared/src/commonMain/.../SimVariants.kt` | Control / Variant A / Variant B probability profiles |
| `shared/src/commonMain/.../Crashes.kt` | 20-crash catalog (Kotlin + native) |
| `shared/src/commonMain/.../Platform.kt` | expect/actual base URL + `createPlatformHttpClient` |

---

## 19-Screen Flow

Welcome → Browse / Search / Categories → ProductDetail / Reviews → Cart / Wishlist → Checkout (Guest/SignIn) → Payment (Card / Apple Pay / PayPal / Android Pay) → Payment Failed → Confirmation

**Advanced screen** (accessible from Welcome) exposes:
- Simulation variant selector (Control / Variant A / Variant B)
- Chaos toggles: Crash Loop, ANR Injection, Force Quit
- A/B Simulation (3 variants × 5 journeys each)
- Cardinality Simulation (10 journeys with unique session IDs)

**Sim 10 / Sim 100 / ∞ Sim** on the Welcome screen run fully automated journeys via the shared `SimulationEngine`.

---

## Scripts

| Script | Purpose |
|---|---|
| `scripts/build-ios-framework.sh` | Build `Shared.xcframework` for iOS. Re-run after changing shared code. |
