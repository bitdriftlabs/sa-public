# Bitdrift Shop

A full-stack e-commerce demo project with **Android**, **iOS**, **React Native**, and **Kotlin Multiplatform** apps backed by a **FastAPI** server. Designed for generating realistic mobile shopping traffic — browsing, searching, cart management, checkout, and payment — with built-in simulation and chaos testing capabilities.

The Python back-end e-commerce server has been tested on Mac. Each app has been built and tested in simulators on Mac. They use `localhost` to rquest the back-end e-commerce service.  

## Quick Start

### 1. Start the Backend (required for all apps)

```bash
cd backend
./start-backend-docker.sh
```

Server runs on `http://localhost:5173`. API docs at `http://localhost:5173/docs`.

### 2. Run an App

**Android** — Open `android/nosdk` in Android Studio and run on an emulator. Connects via `http://10.0.2.2:5173` (emulator → host mapping).

**iOS** — Open `ios/nosdk/bitdrift-shop.xcodeproj` in Xcode and run on the iOS Simulator. Connects via `http://127.0.0.1:5173` (explicit IPv4 to avoid IPv6 resolution issues).

**React Native** — From `reactnative/nosdk`:

```bash
./start.sh          # install deps + start Metro bundler
./start.sh ios      # install deps + CocoaPods + launch iOS simulator
./start.sh android  # install deps + launch Android emulator
```

**Kotlin Multiplatform** — Open `kotlin-multiplatform` in Android Studio to run on Android. For iOS, build the shared framework first then open the Xcode project:

```bash
cd kotlin-multiplatform
./scripts/build-ios-framework.sh
open iosApp/iosApp.xcodeproj
```

## Tech Stack

| Component | Stack | Networking |
|-----------|-------|------------|
| **Backend** | Python 3.10+, FastAPI, Uvicorn | — |
| **Android** | Kotlin, Jetpack Compose, Material 3 | OkHttp |
| **iOS** | Swift, SwiftUI | URLSession (async/await) |
| **React Native** | TypeScript, React Native 0.74, React Navigation | fetch (platform-aware) |
| **Kotlin Multiplatform** | Kotlin 2.1, Compose (Android) + SwiftUI (iOS) | Ktor (shared, platform engines) |

All four apps share the same 16-screen flow, identical simulation logic, and connect to the same backend.

## How It Works

The backend serves a catalog of **18 products** across categories (Electronics, Clothing, Home & Kitchen, Sports, Books). Each request randomizes the selection, so browsing feels different every time.

Each app provides a full shopping experience across **16 screens**:

| Screen | Description |
|--------|-------------|
| Welcome | Entry point, simulation controls |
| Browse | Product listing from catalog (8 random of 18) |
| Search | Keyword search with results |
| Featured | Curated featured products |
| Categories | Category listing |
| CategoryBrowse | Products within a specific category |
| ProductDetail | Full product info with images |
| Reviews | Customer reviews + ratings |
| Cart | Shopping cart with add/remove items |
| Wishlist | Saved items for later |
| CheckoutGuest | Guest checkout flow |
| CheckoutSignIn | Member checkout with loyalty points |
| PaymentCard | Credit card payment (Visa/MC/Amex) |
| PaymentApplePay | Apple Pay payment |
| PaymentPayPal | PayPal payment |
| Confirmation | Order confirmation |

## Automated Simulation

The Welcome screen has simulation buttons (**Sim 10**, **Sim 100**, **∞ Sim**) that run automated user journeys. The simulator is a **probabilistic state machine** — at every screen, a dice roll determines the next action:

The Android SDK variant also has **variant preset buttons** (**Variant A**, **Variant B**, **Control**) that bias the simulator toward a specific user persona before running:

- **Variant A — Guest / High-Abandon:** non-member, skips reviews and wishlist, 1–2 items, guest checkout, Apple Pay or PayPal, high cart abandon rate.
- **Variant B — Member / Low-Abandon:** signed-in loyalty member, reads reviews, saves to wishlist, 2–4 items, sign-in checkout, card payment, low cart abandon rate.
- **Control:** fully random baseline with no persona bias.

Each variant still produces unique journeys — the biases are probabilistic, not deterministic.

| State | Possible Actions |
|-------|------------------|
| **Discovery** | 40% browse, 30% search, 30% categories |
| **After Listing** | 35% view detail, 20% featured, 15% reviews, 10% go back, 10% quick-add to cart, 10% abandon |
| **Product Detail** | 30% add to cart, 15% wishlist, 20% reviews, 20% back to discovery, 15% abandon |
| **Reviews** | 35% add to cart, 15% wishlist, 25% browse more, 15% view detail, 10% abandon |
| **Wishlist** | 35% move to cart, 30% keep browsing, 15% checkout, 20% abandon |
| **Cart** | 30% checkout, 15% delete + keep shopping, 10% delete + re-add, 15% back to browse, 10% move to wishlist, 20% abandon |
| **Checkout** | 50% payment, 15% switch guest↔sign-in, 15% back to cart, 20% abandon |
| **Payment** | 35% card, 25% Apple Pay, 20% PayPal, 10% back to cart, 10% abandon |
| **After Payment** | 80% confirmation, 15% switch payment method, 5% abandon |

This produces unique journeys that naturally include:
- Browsing multiple categories before buying
- Adding items to cart, removing them, and re-adding
- Switching between guest and member checkout
- Comparing products via search before purchasing
- Adding to wishlist → continuing to shop → eventually moving to cart
- Cart abandonment at various stages

## Chaos Mode

The backend supports **chaos mode** for resilience testing — injecting random faults into API responses. Activate with:

```bash
cd backend
./start-backend-chaos-docker.sh
```

Or toggle at runtime:

```bash
curl -X POST http://localhost:5173/api/chaos/enable
curl -X POST http://localhost:5173/api/chaos/disable
```

Or per-request:

```bash
curl -H "X-Chaos: on" http://localhost:5173/api/browse
```

### Fault Types

| Fault | Default Probability | Effect |
|-------|-------------------|--------|
| `slow_response` | 15% | 2–12 second delay |
| `http_404` | 8% | Not Found |
| `http_500` | 6% | Internal Server Error |
| `http_503` | 4% | Service Unavailable with Retry-After |
| `slow_images` | 25% | 3–8 second delay on image requests |
| `truncated_json` | 4% | Malformed JSON body |
| `empty_lists` | 7% | Arrays replaced with `[]` |
| `stale_data` | 8% | Mutated price, zero stock, or "[DISCONTINUED]" name on product detail |
| `payment_failure` | 12% | Payment endpoints return decline/timeout error |
| `session_expiry` | 8% | 401 Unauthorized on checkout/payment |
| `rate_limiting` | 4% | 429 Too Many Requests |

See [backend/README.md](backend/README.md) for chaos control endpoints and configuration examples.

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/health` | Health check |
| GET | `/api/welcome` | Store info + promotions |
| GET | `/api/browse` | Product listing (8 random of 18) |
| GET | `/api/search?q=` | Search products by keyword |
| GET | `/api/featured` | Featured products with badges |
| GET | `/api/categories` | Category listing |
| GET | `/api/categories/{name}` | Products in a specific category |
| GET | `/api/product/{id}` | Product detail with images |
| GET | `/api/product/{id}/reviews` | Product reviews + ratings |
| GET | `/api/cart` | Get current cart contents |
| POST | `/api/cart` | Add item to cart |
| DELETE | `/api/cart/{product_id}` | Remove item from cart |
| POST | `/api/wishlist` | Add to wishlist |
| POST | `/api/checkout/guest` | Guest checkout session |
| POST | `/api/checkout/signin` | Member checkout session |
| POST | `/api/payment/card` | Card payment → transaction ID |
| POST | `/api/payment/applepay` | Apple Pay → transaction ID |
| POST | `/api/payment/paypal` | PayPal → transaction ID |
| GET | `/api/confirmation/{id}` | Order confirmation details |

## Prerequisites

| Requirement | Needed For |
|-------------|------------|
| Docker | Backend |
| Android Studio + emulator | Android app |
| Xcode 15+ with iOS Simulator | iOS app |
| Node.js 18+ and npm | React Native app |
| Watchman (`brew install watchman`) | React Native (Metro bundler) |
| CocoaPods (`brew install cocoapods`) | React Native iOS |
| JDK 17+ | Kotlin Multiplatform |

## React Native Troubleshooting

**"EMFILE: too many open files"** — Install Watchman: `brew install watchman`

**Pod install fails** — Clean and retry:
```bash
cd reactnative/nosdk/ios
pod deintegrate && pod cache clean --all && pod install
```

**"Command PhaseScriptExecution failed"** — Xcode can't find Node:
```bash
echo "export NODE_BINARY=$(which node)" > reactnative/nosdk/ios/.xcode.env.local
```

## Component READMEs

- **[backend/README.md](backend/README.md)** — API endpoints, chaos mode, OpenTelemetry, image generation
- **[android/nosdk/README.md](android/nosdk/README.md)** — Android app (no SDK), project structure
- **[android/sdk/README.md](android/sdk/README.md)** — Android app with Bitdrift SDK, workshop elements
- **[ios/nosdk/README.md](ios/nosdk/README.md)** — iOS app (no SDK), project structure
- **[ios/sdk/README.md](ios/sdk/README.md)** — iOS app with Bitdrift SDK, workshop elements
- **[reactnative/nosdk/README.md](reactnative/nosdk/README.md)** — React Native app (no SDK), setup, scripts, project structure
- **[reactnative/sdk/README.md](reactnative/sdk/README.md)** — React Native app with Bitdrift SDK, workshop elements
- **[kotlin-multiplatform/nosdk/README.md](kotlin-multiplatform/nosdk/README.md)** — KMP architecture, shared module, platform setup

## Project Structure

```
bitdrift-shop/
├── backend/                          # FastAPI server (Python)
│   ├── shopping_server.py            # Main server — 18 products, cart, checkout, payments
│   ├── generate_images.py            # Placeholder product image generator (Pillow)
│   ├── requirements.txt              # fastapi, uvicorn
│   ├── start-backend-docker.sh       # Pull and run from Docker Hub
│   ├── start-backend-chaos-docker.sh # Same with chaos mode enabled
│   ├── stop-backend-docker.sh        # Stop the running container
│   ├── cleanup.sh                    # Remove generated files
│   └── images/                       # Product images served at /images/{id}.png
│
├── android/
│   └── nosdk/                        # Android app (Kotlin, Jetpack Compose)
│       └── app/src/main/java/com/example/bitdrift-shop/
│           ├── MainActivity.kt       # Entry point with NavHost
│           ├── Screen.kt             # 16 navigation routes (sealed class)
│           ├── Screens.kt            # All screen composables
│           ├── Components.kt         # Reusable UI components
│           ├── ApiClient.kt          # OkHttp client → backend
│           ├── SimulationManager.kt  # Probabilistic state machine
│           ├── ScreenLogger.kt       # Centralized logging
│           ├── ShoppingDemoApp.kt    # Application class
│           ├── AppLifecycleCallbacks.kt # App lifecycle event logging
│           └── ui/theme/Theme.kt     # Material 3 theme
│
├── ios/
│   └── nosdk/                        # iOS app (Swift, SwiftUI)
│       ├── bitdrift-shop.xcodeproj        # Xcode project
│       └── BitdriftShop/
│           ├── BitdriftShopApp.swift      # @main entry point
│           ├── ContentView.swift      # NavigationStack + routing
│           ├── Screen.swift           # AppScreen enum (16 cases)
│           ├── ApiClient.swift        # URLSession actor (async/await)
│           ├── SimulationManager.swift # Probabilistic state machine
│           ├── Components.swift       # Reusable UI components
│           ├── ScreenLogger.swift     # os.log Logger wrapper
│           └── Screens/              # 16 individual screen files
│
├── reactnative/
│   └── nosdk/                        # React Native app (TypeScript)
│       ├── App.tsx                    # Root navigator + SimulationProvider
│       ├── index.js                   # Entry point
│       ├── start.sh                   # Convenience launch script
│       ├── cleanup.sh                 # Remove build artifacts
│       └── src/
│           ├── api/ApiClient.ts       # Platform-aware HTTP client
│           ├── components/            # Buttons, ScreenContainer, SimulationOverlay
│           ├── context/SimulationContext.tsx  # State machine + navigation driver
│           ├── navigation/types.ts    # Typed route params
│           ├── screens/ShoppingScreens.tsx   # All 16 screen components
│           ├── types/models.ts        # Backend response interfaces
│           └── utils/                 # Colors, logger
│
└── kotlin-multiplatform/              # Kotlin Multiplatform (shared logic)
    ├── shared/                        # CommonMain: Models, ApiClient, SimulationEngine
    ├── androidApp/                    # Jetpack Compose UI consuming shared module
    ├── iosApp/                        # SwiftUI app consuming Shared.framework
    └── scripts/                       # iOS framework build scripts
```