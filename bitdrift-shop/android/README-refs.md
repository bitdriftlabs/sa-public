# Bitdrift Shop References

## Screens

| Screen | Description |
|--------|-------------|
| `Welcome` | Entry point — simulation controls, SDK version badge, Device Code, crash loop status |
| `Advanced` | Simulation variant selector, Crash / ANR-A / Force-Quit / Slow toggles, Support Log |
| `Browse` | Product listing (8 random of 18) |
| `Search` | Keyword search |
| `Featured` | Curated featured products |
| `Categories` | Category listing |
| `CategoryBrowse` | Products within a category |
| `ProductDetail` | Full product info |
| `Reviews` | Customer reviews + ratings |
| `Cart` | Shopping cart |
| `Wishlist` | Saved items |
| `CheckoutGuest` | Guest checkout |
| `CheckoutSignIn` | Member checkout with loyalty points |
| `PaymentCard` | Credit card payment |
| `PaymentApplePay` | Apple Pay |
| `PaymentPayPal` | PayPal |
| `PaymentAndroidPay` | Android Pay |
| `Confirmation` | Order confirmation |

## Emulator Requirements

| Setting | Required value | Why |
|---------|---------------|-----|
| **API level** | **API 36** (Android 16) | App targets SDK 36; ANR behavior depends on modern ANR detection |
| **Screen resolution** | **1080×2400** (FHD+) | Watchdog script touch coordinates are calibrated for this resolution |
| **Device profile** | Medium Phone (or Pixel 7 / 6a) | Standard phone form factor |
| **RAM** | 2 GB+ | Compose + OkHttp + simulation engine need headroom |

## Entities

### Fixed Entity List

| Entity | Origin |
|--------|--------|
| Groucho | Marx Brothers |
| Harpo | Marx Brothers |
| Chico | Marx Brothers |
| Gummo | Marx Brothers |
| Zeppo | Marx Brothers |
| Moe | Three Stooges |
| Larry | Three Stooges |
| Curly | Three Stooges |
| Abbott | Abbott & Costello |
| Costello | Abbott & Costello |

### Demoing Entities

Go to **bitdrift → Entities** and search for any name above (exact match). The detail page shows all sessions, crashes, devices, and last-known location. Use **Record Next Online** to queue a recording for an entity's next session. Bookmark entities with the bookmark icon to share them in the team's **Public Bookmarked Entities** list.

---

## SDK Features & Implementation

See [INSTRUMENTATION_GUIDE.md](INSTRUMENTATION_GUIDE.md) for the 13-step walkthrough and code examples. This section contains reference data about how the app works.

---

## Simulation

### Probabilistic State Machine

At every decision point, a weighted dice roll determines the next action — producing unique, realistic journeys.

| Decision point | Control | Variant A (Guest) | Variant B (Member) |
|----------------|---------|-------------------|---------------------|
| **Discovery: Browse** | 33% | 40% | 25% |
| **Discovery: Search** | 33% | 45% | 25% |
| **Discovery: Categories** | 33% | 15% | 50% |
| **Visit Featured** | 50% | 15% | 75% |
| **Read Reviews** | 50% | 10% | 90% |
| **Visit Wishlist** | 40% | 5% | 75% |
| **Extra cart items** | 1–3 | 0–1 | 2–4 |
| **Remove cart item** | 60% | 10% | 90% |
| **Empty cart + re-add** | 20% | 5% | 60% |
| **Quantity flip** | 30% | 5% | 70% |
| **Cart abandonment** | 5% | 15% | 0% |
| **Guest vs. signin checkout** | 50/50 | 95% guest | 95% signin |
| **Checkout dropout** | 0% | 35% | 5% |
| **Payment: card** | 25% | 5% | 95% |
| **Payment: Apple Pay** | 25% | 40% | 3% |
| **Payment: PayPal** | 25% | 35% | 2% |
| **Payment: Android Pay** | 25% | 20% | 0% |
| **Payment failure (card/Apple/PayPal)** | 15% | 35% | 5% |
| **Payment failure (Android Pay)** | 30% | 20% | n/a |
| **Payment retry (on failure)** | 50% | 50% | 50% |

---

### ANR-A Guest Journey Testing

**What:** ANR injection on the `CheckoutGuest` screen for Variant A guest sessions. Creates a visible Sankey dropout at checkout, unique to Variant A.

**How it works:**

1. **ANR-A** toggle sets `anr_a.active` and records exposure `anr_a = enabled|disabled`.
2. Injection is gated to: Variant A + guest checkout path.
3. Fires after `nav(CheckoutGuest)` + `ApiClient.checkoutGuest()` complete (window focus established).
4. Probability: 25% per eligible journey; forced cadence after 6 eligible journeys in infinite mode.
5. Before freezing, writes `restart_pending` / `resume_infinite` / `restart_variant` to SharedPreferences.
6. Blocks main thread with `Thread.sleep(15s)` + infinite freeze — ANR dialog appears after ~5s.
7. Watchdog script (`scripts/watchdog.sh`) sends touch events to trigger ANR detection, monitors via `dumpsys window`, force-stops, and relaunches.
8. On relaunch, `MainActivity` consumes `restart_pending`, restores variant, and resumes simulation.

**Why a host-side script?** Android 14+ blocks background activity launches — the app cannot relaunch itself after an ANR kill.

**Running:**

```bash
# Terminal 1
./scripts/watchdog.sh

# Terminal 2: tap Advanced on Welcome → select Variant A, enable ANR-A → tap SIM ∞
```

**Sankey story:**
```
Welcome → Browse/Search/Categories → ProductDetail → Cart → CheckoutGuest → (ANR dropout)
```

**Dashboard:**
- Filter `ff_anr_a = enabled` to isolate ANR runs
- Count `guest_anr_injected` events; group by `anr_screen_name`
- Correlate with ANR issue groups and `anr_restart_resume` restart events

**Files:**

| File | Role |
|------|------|
| `SimulationManager.kt` | ANR state, gating, freeze, restart state |
| `MainActivity.kt` | `restart_pending` consumption and auto-resume |
| `Screens.kt` | ANR-A toggle, status chip (Advanced screen) |
| `scripts/watchdog.sh` | Touch → ANR detect → force-stop → relaunch |

---

### Force-Quit Journey Testing

**What:** Force quits injected at `ProductDetail` — users discover a product then abandon before cart or checkout.

**How it works:**

1. **Force Quit** toggle sets `force_quit.active` and records exposure `force_quit = enabled|disabled`.
2. Injection point: after `nav(ProductDetail)` + product API call.
3. Probability: 60%; forced after 3 eligible journeys in infinite mode.
4. Logs `force_quit_injected`, writes restart state to SharedPreferences.
5. Watchdog performs a recents swipe-dismiss, then relaunches.
6. Android records `APP_TERMINATION` with `_app_exit_reason = USER_REQUESTED`.

**Sankey story:**
```
Welcome → Browse/Search/Categories → ProductDetail → (Force Quit)
```

**Dashboard:**
- Sankey shows `ProductDetail` as the dropout point
- Correlate pre-exit screen views and requests
- Track `_app_exit_reason = USER_REQUESTED` over time

**Files:**

| File | Role |
|------|------|
| `SimulationManager.kt` | Force-quit state, gating, cadence, restart state |
| `MainActivity.kt` | `restart_pending` consumption |
| `Screens.kt` | Force Quit toggle, status chip (Advanced screen) |
| `scripts/watchdog.sh` | Recents swipe-dismiss and relaunch |

---

### Crash Loop

**What:** 20 typed crashes cycling one per journey, each firing after the Confirmation screen so a complete session is captured first.

**How it works:**

1. Enabling Crash mode sets `crash_loop.active = true`. The `order_summary` flag switches to `"v2"`.
2. After Confirmation, `maybeFireCrash()` in `SimulationManager.kt`:
   - Reads `next_index` from SharedPreferences, picks `Crashes.all[idx]`.
   - Increments `next_index` with `commit()` (not `apply()` — process dies immediately after).
   - Calls `Logger.addField("crash_kind", name)` and `Logger.logWarning { "about_to_crash" }`.
   - Calls `ShoppingDemoApp.scheduleRestart(ctx, 2000ms)` to arm an AlarmManager restart **before** the crash.
   - Waits 300ms for SDK flush, then calls `fn()`.
3. AlarmManager fires 2s after process death, relaunching through the startup splash. `crashLoopEnabled` is restored from prefs and the next crash type fires.

**Why AlarmManager?** Native signal crashes (SIGSEGV/SIGBUS/SIGABRT/SIGFPE) kill the process instantly — the JVM uncaught-exception handler never runs. The AlarmManager is armed before `fn()`, so even a hard kill still triggers restart.

**The 20 crash types** (`Crashes.kt`):

| # | Name | Category |
|---|------|----------|
| 1–13 | `null_pointer` … `unsatisfied_link` | JVM main thread |
| 14 | `runtime_background_thread` | JVM background thread |
| 15 | `coroutine_io` | JVM coroutine |
| 16 | `oom_allocator_thread` | JVM OOM |
| 17–20 | `native_sigsegv` … `native_sigfpe` | Native signals |

Each has a unique top-level method — bitdrift groups crashes by top frame, so all 20 appear as distinct issue groups.

**Running:**

```bash
# Terminal 1 (safety net for dropped alarms)
./scripts/watchdog.sh

# Terminal 2: enable Crash mode in Advanced → Crash toggle, then tap SIM ∞ on Welcome
# To stop: tap "Stop crash loop" button on the Welcome screen (appears when loop is active)
```

**Dashboard:**
- **Issues**: 20 distinct crash groups accumulating as the loop runs; each tagged with `crash_kind`
- **Session timeline**: every session ends with `about_to_crash` (Warning) + the crash event; full journey visible
- **Workflow**: trigger on `APP_CRASH` to upload logs from every crashed session

**Files:**

| File | Role |
|------|------|
| `Crashes.kt` | 20 crash types with unique top-level methods |
| `SimulationManager.kt` | `maybeFireCrash()` — pick, log, arm, fire |
| `ShoppingDemoApp.kt` | `scheduleRestart()` (AlarmManager), `installCrashLoopHandler()` |
| `Screens.kt` | Crash toggle (Advanced), "Stop crash loop" button + status chip (Welcome) |
| `scripts/watchdog.sh` | Safety net: `is_crash_loop_active()` → relaunch |

---

### Device Identification & Debugging

**What:** Three tools for locating a device's telemetry:
- **Device Code** — short-lived alphanumeric code the user reads to support; agent enters it in the dashboard to pull the exact session.
- **Support Log toggle** — sets `supportlog = "true"/"false"` global field; support filters the dashboard to one device.
- **Session URL / Device ID** — available via `Logger.sessionUrl` / `Logger.deviceId` for programmatic use.

**File:** `Screens.kt` (Welcome screen)

```kotlin
Logger.createTemporaryDeviceCode { result ->
    when (result) {
        is CaptureResult.Success -> { deviceCode = result.value; clipboardManager.setText(...) }
        is CaptureResult.Failure -> { deviceCode = "error" }
    }
}

Logger.addField("supportlog", supportLogEnabled.toString())
```

---

### Slow Frames (Performance Bug Demo)

**What:** Tapping **Slow** enables a "Recommended for You" section powered by `RecommendationEngine` — but the scoring runs synchronously in the composable body on every recomposition, blocking the main thread for 80–250ms per frame.

**The problem:** `RecommendationEngine.scoreProducts()` is called directly in `BrowseScreen` (line 270) and `ProductDetailScreen` (line 531) without `remember` or background dispatch — re-executing on every scroll, tap, and state change.

**The fix:** Move the call into `LaunchedEffect` + `withContext(Dispatchers.Default)`, storing the result in a `remember`-backed `mutableStateOf`. Fix is shown commented out in both screens.

**Dashboard:** With Slow mode on, `slow_frame` events appear correlated with `screen_view = Browse` and `screen_view = ProductDetail`, with render times of 80–250ms vs. the normal <16ms budget.

**Files:**

| File | Role |
|------|------|
| `RecommendationEngine.kt` | `scoreProducts()` (line 16), `levenshteinSimilarity()` (line 53) |
| `Screens.kt` line 270 | `BrowseScreen` — scoring in composable body |
| `Screens.kt` line 531 | `ProductDetailScreen` — scoring in composable body |
| `Components.kt` | `RecommendedSection` composable |
| `ApiClient.kt` | `getFullCatalogJson()` |

---

## Log Events

Log events emitted by this app (match on `message ==`):

| Source | Events |
|--------|--------|
| Lifecycle | `app_launched`, `app_open`, `app_close`, `memory_pressure`, `low_memory` |
| Product | `add_to_cart`, `add_to_wishlist` |
| Cart | `cart_item_removed`, `cart_failed` |
| Checkout | `checkout_started`, `checkout_failed` |
| Payment | `payment_completed`, `payment_failed`, `payment_retry` |
| Simulation | `simulation_start`, `simulation_end`, `cart_abandoned`, `checkout_abandoned` |
| Faults | `force_quit_injected`, `guest_anr_injected`, `about_to_crash` |

## Span Names

Query with `name == <span>` and `_span_type == "end"` for `_duration_ms`:

| Span | Covers |
|------|--------|
| `journey` | Full shopping journey root — Welcome through Confirmation |
| `product_discovery` | Welcome → Browse/Search → ProductDetail → first cart add |
| `checkout` | CheckoutGuest/SignIn → Payment → Confirmation |
| `score_products` | Recommendation engine scoring (Slow mode only) |

## Fields

| Field | Values |
|-------|--------|
| `ff_variant` | `Control`, `Variant A`, `Variant B` |
| `ff_checkout_flow` | `random`, `guest`, `signin` |
| `ff_payment_ui` | `random`, `digital`, `card` |
| `ff_cart_abandon_rate` | `medium`, `high`, `low` |
| `app_variant` | `sdk-demo` |
| `user_id` | entity identifier — surfaces in Timeline session header |
| `supportlog` | `true` when Support Log mode is active |

---

## Project Structure

```
app/src/main/java/ai/bitdrift/shop/
├── ShoppingDemoApp.kt         # Application class — SDK init, AlarmManager restart, crash handler
├── Crashes.kt                 # 20 typed crash variants (JVM main/bg, native signals)
├── ScreenLogger.kt            # Centralized logging wrapper (logScreenView, logInfo, logError)
├── Screen.kt                  # Navigation routes (sealed class)
├── Screens.kt                 # All screen composables
├── Components.kt              # Reusable UI components (ScreenContainer, SimulationOverlay, etc.)
├── MainActivity.kt            # Main activity — NavHost, screen view listener, TTI
├── SimulationManager.kt       # Probabilistic state machine simulator + crash cycling
├── ApiClient.kt               # OkHttp API client (singleton)
├── RecommendationEngine.kt    # Product recommendation scoring engine
├── OrderSummaryHelper.kt      # Order summary formatter
├── AppLifecycleCallbacks.kt   # App lifecycle event logging
└── ui/theme/Theme.kt          # Material 3 theme
```

## Product Images

```bash
cd backend && source venv/bin/activate && pip install Pillow && python generate_images.py
```

Creates 400×400 color-coded PNGs for all 18 products in `backend/images/`.

## Requirements

- Android API 36 (targetSdk / compileSdk), API 26+ minimum
- Emulator: 1080×2400 (Medium Phone / Pixel 7) — watchdog touch coordinates depend on this
- Kotlin + Jetpack Compose
- Backend server on port 5173
- macOS with Android SDK (`adb`) for the watchdog script
