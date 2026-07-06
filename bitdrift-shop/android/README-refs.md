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

See [INSTRUMENTATION_GUIDE.md](../../instrumentation-guide/INSTRUMENTATION_GUIDE.md) for the 13-step walkthrough and code examples. This section contains reference data about how the app works.

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

**What:** 23 typed crashes cycling one per journey, each firing after the Confirmation screen so a complete session is captured first.

**How it works:**

1. Enabling Crash mode sets `crash_loop.active = true`. The `order_summary` flag switches to `"v2"`.
2. After Confirmation, `maybeFireCrash()` in `SimulationManager.kt`:
   - Reads `next_combo_index` from SharedPreferences via `pickNextCrashCombo()` — a single
     index cycling 0 until `Crashes.all.size * 2` (46), so every crash type is guaranteed to
     occur in **both** foreground and background exactly once per full sweep, rather than
     relying on independent random coin-flips to eventually cover every combination.
     `comboIdx / 2` selects the crash type; `comboIdx % 2` selects foreground (0) vs.
     background (1).
   - Increments `next_combo_index` with `commit()` (not `apply()` — process dies immediately
     after).
   - Calls `Logger.addField("crash_kind", name)`, `Logger.addField("crash_context", "foreground"|"background")`, and `Logger.logWarning { "about_to_crash" }`.
   - Calls `ShoppingDemoApp.scheduleRestart(ctx, 2000ms)` to arm an AlarmManager restart **before** the crash.
   - **Foreground path** (`dispatchCrash()` in `SimulationManager.kt`): waits 300ms for SDK flush, then calls `fn()`.
   - **Background path:** calls `activity.moveTaskToBack(true)` (same effect as pressing Home), waits 2000ms (`BACKGROUND_SETTLE_MS`) for Android to actually demote process importance away from foreground, then calls `fn()`. Falls back to the foreground path if no `Activity` is available.
3. AlarmManager fires 2s after process death, relaunching through the startup splash. `crashLoopEnabled` is restored from prefs and the next crash combo fires.

**Fast Crash Mode:** a "Fast crash mode" toggle on the startup splash screen (next to "Crash
mode") skips the shopping journey entirely. `SimulationManager.fireFastCrash()` picks the
next combo and fires immediately on every relaunch — no `Sim ∞`, no navigation, no API
calls. It's self-sustaining across restarts: `MainActivity`'s Welcome-screen effect
re-invokes it on every cold start when `crash_loop.active && crash_loop.fast_mode` are both
true, and the startup splash's own 5s countdown is skipped on those restarts too (otherwise
the countdown alone would dominate the cycle time). Because the crash lands within a second
or two of the splash screen's config write, that write uses `commit()`, not `apply()`, for
the same reason as the combo index above — this bit us once as fast mode's toggle silently
reverting after the first crash.

**Stopping Fast Crash Mode:** it fires far too quickly to reliably tap "Stop crash loop" in
the UI. Two `adb` commands, run in order, stop it from outside the app:

```bash
# 1. Kill the process. force-stop also cancels the package's pending AlarmManager
#    alarms, so it won't just relaunch itself. Verified: it stays dead indefinitely,
#    not just until the next alarm would have fired.
adb shell am force-stop ai.bitdrift.shop

# 2. Flip fast_mode off directly in the persisted prefs, while the process is dead so
#    nothing overwrites the file back to fast_mode=true on its next commit().
adb shell "run-as ai.bitdrift.shop sed -i 's/name=\"fast_mode\" value=\"true\"/name=\"fast_mode\" value=\"false\"/' /data/data/ai.bitdrift.shop/shared_prefs/crash_loop.xml"
```

**Quoting matters here** — `adb shell` re-joins its arguments into one string before the
device's shell re-parses them, so local shell quoting doesn't survive the trip the way
you'd expect. Wrapping the *entire* `run-as ...` command in one pair of double quotes, with
the `sed` script itself single-quoted and its internal double quotes backslash-escaped (as
above), is what actually works — verified directly against a running emulator. A more
naturally-quoted version that looks equally reasonable (single-quoting just the `sed`
script, unescaped) fails with `sed: bad pattern` on Android's `toybox sed`.

This alone stops the rapid loop — the app comes back up with crash mode still configured
but nothing auto-firing until `Sim ∞` is pressed manually. To fully reset (also turn off
crash mode itself), add a second `-e` expression for `active`:

```bash
adb shell am force-stop ai.bitdrift.shop
adb shell "run-as ai.bitdrift.shop sed -i -e 's/name=\"active\" value=\"true\"/name=\"active\" value=\"false\"/' -e 's/name=\"fast_mode\" value=\"true\"/name=\"fast_mode\" value=\"false\"/' /data/data/ai.bitdrift.shop/shared_prefs/crash_loop.xml"
```

The `am force-stop` step must come first both times — editing the XML while the process is
still alive doesn't help, since any subsequent `SharedPreferences.commit()` from that
process (which happens on every single crash iteration) rewrites its whole in-memory
snapshot back to disk and silently clobbers the out-of-band edit.

Sanity-check either command actually took effect before relaunching:
```bash
adb shell run-as ai.bitdrift.shop cat /data/data/ai.bitdrift.shop/shared_prefs/crash_loop.xml
```

`scripts/check-demo-state.sh --reset` automates this full-reset sequence (and does the same for
ANR-A/Force-Quit) — run it before starting any other demo to catch fault-injection state left
active from a previous session, since all three flags persist across restarts by design.

**Why foreground vs. background matters:** every crash type can now be observed in either app state, which is what the [`bd-shop-06-crash-foreground.json` / `bd-shop-07-crash-background.json`](workflows/foreground-background-crashes.md) workflows chart. Crash *type* grouping is unaffected — foreground/background is an orthogonal dimension read from `app_metrics.running_state`, not a new set of issue groups. Android has no dedicated `"background"` value for that field (only `foreground`/`foreground_service`/`perceptible`), so the background workflow defines it as "anything that isn't exactly foreground" — see the linked doc for why that's unavoidable, not a workaround.

Both workflows' BDRL only defines what to *reject* (`abort`) — `IssueMatch` counts whatever
survives, so "counts background" really means "rejects everything that isn't background."
See [foreground-background-crashes.md](workflows/foreground-background-crashes.md) for why
that inversion matters when reading the actual scripts.

**Why AlarmManager?** Native signal crashes (SIGSEGV/SIGBUS/SIGABRT/SIGFPE) kill the process instantly — the JVM uncaught-exception handler never runs. The AlarmManager is armed before `fn()`, so even a hard kill still triggers restart.

**Prerequisite fix — JVM crashes now actually produce a captured report:** `installCrashLoopHandler()` in `ShoppingDemoApp.kt` used to skip bitdrift's own `CaptureUncaughtExceptionHandler` entirely whenever crash-loop mode was active (the only branch that ever runs, in practice), so no JVM crash — main-thread, background-thread, or coroutine — ever produced a real captured Report while the loop was running; only the 4 native-signal crash types did, since those go through a separate, JNI-bridged handler this Java-level chain never touches. The handler now always calls the previously-installed default handler (bitdrift's) first, then proceeds with the crash-loop's own restart/kill logic — so all 23 crash types below now produce real captured issues.

**The 23 crash types** (`Crashes.kt`):

| # | Name | Category |
|---|------|----------|
| 1–13 | `null_pointer` … `unsatisfied_link` | JVM main thread |
| 14 | `runtime_background_thread` | JVM background thread |
| 15 | `coroutine_io` | JVM coroutine |
| 16 | `oom_allocator_thread` | JVM OOM |
| 17 | `lock_contention` | JVM lock contention (synthetic ANR-to-crash) |
| 18 | `vendor_sdk_interceptor` | JVM vendor SDK (fake ad SDK) |
| 19 | `vendor_sdk_analytics` | JVM vendor SDK (fake analytics SDK) |
| 20–23 | `native_sigsegv` … `native_sigfpe` | Native signals |

Each has a unique top-level method — bitdrift groups crashes by top frame, so all 23 appear as distinct issue groups.

**Why `lock_contention` and `vendor_sdk_*` work the way they do:**
- `lock_contention` uses three separate threads on purpose: `image-decode-thread` holds a
  monitor and is genuinely `TIMED_WAITING`, the main thread is genuinely `BLOCKED` on that
  same monitor, and an uninvolved `anr-watchdog-thread` converts the block into a crash after
  a fixed 300ms delay — independent of the 2000ms hold window, so there's real margin against
  scheduler jitter. It's a synthetic stand-in for a real ANR (deliberately turned into a crash
  so it's guaranteed to land in the existing capture pipeline), not a real ANR — see
  `Crashes.kt`'s own comments for the full reasoning.
- `vendor_sdk_interceptor`/`vendor_sdk_analytics` throw from two fake OkHttp interceptors
  (`com.adsdk.fake.AdRequestInterceptor`, `com.analytics.fake.AnalyticsPingInterceptor`)
  before any network I/O starts, so the crash carries real third-party-looking stack frames
  (`com.adsdk.fake.*` / `com.analytics.fake.*`) with no dependency on network reachability.

**Why `bd-shop-08`/`09`/`10` work the way they do:**
- `bd-shop-08` (blocking thread) and `bd-shop-09` (vendor SDK) are single-flow `IssueMatch`
  workflows, same "define what to reject" pattern as `bd-shop-06`/`07` above.
- `bd-shop-10` (the rate chart tying the other two together) is structurally different: it's
  **two independent flows**, not one. One flow (shown as "Match Issue 1.1" in the workflow
  UI) is the *denominator* — every crash, unconditionally — and its entire `bdrl_program` is
  the literal `true`. That's not a placeholder: since `IssueMatch` only ever rejects via
  `abort`, a program that never calls `abort` matches every report that reaches it, and
  `true` is just the smallest real statement that does that. (A comment-only program matches
  identically but has no actual statement for the workflow graph to summarize, so the UI
  renders it as an empty match group — `true` fixes that display issue without changing
  behavior.) The other flow ("Match Issue 2.1") is the *numerator* — it inspects
  `.thread_details.threads` and stack frames across all errors, and `abort`s for anything it
  can't attribute to a known thread or vendor SDK — and the `rate` action divides the two.

See [advanced-crash-attribution.md](workflows/advanced-crash-attribution.md) for the full
BDRL scripts, the compiler gotchas that shaped them, and the presentation notes for demoing
these three workflows.

**Running:**

```bash
# Terminal 1 (safety net for dropped alarms)
./scripts/watchdog.sh

# Terminal 2, slow (journey-based): enable Crash mode in Advanced → Crash toggle,
# then tap SIM ∞ on Welcome. To stop: tap "Stop crash loop" on Welcome (loop active).

# Terminal 2, fast: enable both "Crash mode" and "Fast crash mode" on the startup
# splash screen. No Sim button needed -- self-sustaining across restarts.
# To stop: see "Stopping Fast Crash Mode" above (the UI button is too slow to tap).
```

**Dashboard:**
- **Issues**: 23 distinct crash groups accumulating as the loop runs; each tagged with `crash_kind` and `crash_context` (`foreground`/`background` — the app's own intent, independent of the BDRL-observed `app_metrics.running_state`)
- **Session timeline**: every session ends with `about_to_crash` (Warning) + the crash event; full journey visible
- **Workflow**: trigger on `APP_CRASH` to upload logs from every crashed session; `bd-shop-06-crash-foreground.json`/`bd-shop-07-crash-background.json` chart the foreground/background split, `bd-shop-08-blocking-thread.json`/`bd-shop-09-vendor-sdk-attribution.json`/`bd-shop-10-attribution-rate.json` chart thread- and vendor-SDK-based attribution — see [advanced-crash-attribution.md](workflows/advanced-crash-attribution.md)

**Files:**

| File | Role |
|------|------|
| `Crashes.kt` | 23 crash types with unique top-level methods |
| `SimulationManager.kt` | `pickNextCrashCombo()`/`dispatchCrash()` (shared), `maybeFireCrash()` (journey-based), `fireFastCrash()` (fast mode) |
| `ShoppingDemoApp.kt` | `scheduleRestart()` (AlarmManager), `installCrashLoopHandler()`, `KEY_FAST_MODE`/`KEY_NEXT_COMBO_INDEX` |
| `MainActivity.kt` | Fast crash mode toggle (startup splash), phase-skip on fast-mode restarts, Welcome-screen resume/fire wiring |
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

See [../demo-slow-rendering.md](../demo-slow-rendering.md) for the full setup, live trigger,
dashboard/alert walkthrough, and fix-diagnosis script. Toggle: **Rec v2** button on the
Advanced screen (`simulationManager.recommendationsV2Enabled`, feature flag key
`recommendations_v2`). The bug lives in `RecommendationEngine.scoreProducts()`
(`RecommendationEngine.kt:16`), called synchronously in the composable body of
`BrowseScreen` (`Screens.kt:498`) and `ProductDetailScreen` (`Screens.kt:759`), detected via
bitdrift's built-in Android dropped-frame detection — no app-side slow-frame instrumentation
required.

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
| `score_products` | Recommendation engine scoring (`recommendations_v2` flag only) |

## Fields

| Field | Values |
|-------|--------|
| `ff_variant` | `Control`, `Variant A`, `Variant B` |
| `ff_checkout_flow` | `random`, `guest`, `signin` |
| `ff_payment_ui` | `random`, `digital`, `card` |
| `ff_cart_abandon_rate` | `medium`, `high`, `low` |
| `ff_recommendations_v2` | `enabled`, `disabled` |
| `app_variant` | `sdk-demo` |
| `user_id` | entity identifier — surfaces in Timeline session header |
| `supportlog` | `true` when Support Log mode is active |

---

## Project Structure

```
app/src/main/java/ai/bitdrift/shop/
├── ShoppingDemoApp.kt         # Application class — SDK init, AlarmManager restart, crash handler
├── Crashes.kt                 # 23 typed crash variants (JVM main/bg, lock contention, vendor SDK, native signals)
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
