# Bitdrift Shop — Kotlin Multiplatform

KMP e-commerce demo sharing business logic across **Android** (Jetpack Compose) and **iOS** (SwiftUI), instrumented with the bitdrift Capture SDK.

---

## Prerequisites

- JDK 17+, Android Studio, Xcode 15+
- Backend running — `cd ../backend && ./start-backend-docker.sh`

---

## Setup

### Android

1. Copy the secret properties file:
   ```bash
   cp sdk/.local.properties.example sdk/.local.properties   # or create it manually
   ```
   Fill in your values:
   ```
   BITDRIFT_SDK_KEY=<your-key>
   BITDRIFT_API_HOST=api.bitdrift.io
   ```
2. Open `kotlin-multiplatform/sdk/` in Android Studio.
3. Run the `androidApp` configuration on a device or emulator.

### iOS

1. Copy the xcconfig:
   ```bash
   cp sdk/iosApp/.local.xcconfig.example sdk/iosApp/.local.xcconfig   # or create it manually
   ```
   Fill in:
   ```
   BITDRIFT_SDK_KEY = <your-key>
   BITDRIFT_API_HOST = api.bitdrift.io
   ```
2. In Xcode: **Project → Info → Configurations** — set Debug and Release to use `sdk/iosApp/.local.xcconfig`.
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
| SDK init | `androidApp/src/main/java/com/example/bitdrift-shop/ShoppingDemoApp.kt` (`onCreate`) | `iosApp/iosApp/BitdriftShopKMPApp.swift` (`init`) |
| Screen views | `shared/src/androidMain/kotlin/com/example/bitdrift-shop/shared/ScreenLogger.android.kt` → `Logger.logScreenView` | `iosApp/iosApp/ScreenLogger.swift` → `Logger.logScreenView` |
| Network capture | `CaptureOkHttpEventListenerFactory` (OkHttp) | URLSession swizzling (`enableIntegrations([.urlSession()])`) |
| Structured logs | `Logger.logInfo` / `Logger.logError` | `Logger.logInfo` / `Logger.logError` |
| App launch TTI | — | `Logger.logAppLaunchTTI` |
| Global fields | `app_variant = kmp-demo` | `app_variant = kmp-demo` |
| SDK version | `0.22.16` | `0.22.16` |
| API host override | `BITDRIFT_API_HOST` in `.local.properties` or env var | `BITDRIFT_API_HOST` in `iosApp/.local.xcconfig` or env var |

**SDK key** — never committed. Loaded from:
- Android: `sdk/.local.properties` → `BuildConfig.BITDRIFT_SDK_KEY` (falls back to env var `BITDRIFT_SDK_KEY`)
- iOS: `sdk/iosApp/.local.xcconfig` → `iosApp/iosApp/Info.plist` `$(BITDRIFT_SDK_KEY)` / `$(BITDRIFT_API_HOST)` (falls back to env vars; host defaults to `api.bitdrift.io`)

**Dashboard filtering** — both platforms report to the same bitdrift app (same SDK key). Use the built-in `os` field (`android` / `ios`) to split by platform, or `app_variant = kmp-demo` to distinguish this app from the non-KMP Android demo.

---

## Architecture

```
shared/src/commonMain/     # Models, ApiClient, SimulationEngine, ScreenLogger (expect)
shared/src/androidMain/    # OkHttp + CaptureOkHttpEventListenerFactory, Logger actuals
shared/src/iosMain/        # Darwin engine, Logger actuals (bitdrift runs at Swift layer)
androidApp/                # Jetpack Compose UI, ShoppingDemoApp (Logger.start)
iosApp/                    # SwiftUI UI, BitdriftShopKMPApp (Logger.start), ScreenLogger.swift
```

---

## Shared Modules

| Module | Contents |
|---|---|
| `shared/src/commonMain/kotlin/com/example/bitdrift-shop/shared/Models.kt` | 20+ `@Serializable` data classes |
| `shared/src/commonMain/kotlin/com/example/bitdrift-shop/shared/ApiClient.kt` | Ktor HTTP client, 17 endpoints |
| `shared/src/commonMain/kotlin/com/example/bitdrift-shop/shared/SimulationEngine.kt` | Probabilistic state machine — runs automated journeys |
| `shared/src/commonMain/kotlin/com/example/bitdrift-shop/shared/ScreenLogger.kt` | expect/actual logging — delegates to platform bitdrift calls |
| `shared/src/commonMain/kotlin/com/example/bitdrift-shop/shared/Platform.kt` | expect/actual base URL + `createPlatformHttpClient` |

---

## 16-Screen Flow

Welcome → Browse / Search / Categories → ProductDetail / Reviews → Cart / Wishlist → Checkout → Payment → Confirmation

**Sim 10 / Sim 100 / ∞ Sim** on the Welcome screen run automated journeys through every screen via the shared `SimulationEngine`.

---

## Scripts

| Script | Purpose |
|---|---|
| `sdk/scripts/build-ios-framework.sh` | Build `Shared.xcframework` for iOS. Re-run after changing shared code. |
| `sdk/cleanup.sh` | Remove all build artifacts and caches. |
