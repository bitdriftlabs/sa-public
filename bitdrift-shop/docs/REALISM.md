# Realism: sessions, crashes and commands that look like a real app's

Part of the [bitdrift Shop README](../README.md). Android and iOS only; React Native and Flutter pick these up later
through the shared [spec](SPEC.md) where their SDKs support them.

Early versions of the demo *announced* their crashes (`about_to_crash: …`) and started a new session for every journey. These
features make the sessions read more like a real app's, for crash triage and session-analysis agents as much as for people.

## Realistic crashes

Two crashes fail inside plausible app code instead of a catalog trap, and log what a real app would have logged first:

| Crash | Where it fails | Precursor logs (no `about_to_crash`, no `crash_kind`) |
|-------|----------------|--------------------------------------------------------|
| `app_coupon_empty_cart` | `CartPricing.applyCoupon` on an empty cart (no guard) | `coupon_apply_failed` (error, `coupon_code`) |
| `app_promo_banner_payload` | `PromoBannerParser.parse` on a banner whose `discount_percent` is `"20%"` | `promo_banner_parse_failed` (error, `attempt=1`), `promo_banner_retry` (`attempt=2`); the retry crashes |

They are in the crash catalog like the others (`spec/crashes.yaml`, `realistic: true`) and fire when the crash loop reaches them. To fire one on
demand, launch with `--es crash <name>` (Android) or `-crash <name>` (iOS) plus `sim_runs`; see [TESTING.md](TESTING.md). Relaunch afterwards so the
SDK uploads the report.

**Symbolication.** On Android a release build is minified with R8 and `android/scripts/release-build.sh [--install]` uploads the mapping, so the issue
reads `CartPricing.applyCoupon(CartPricing.kt:28)`. Keep rules in `proguard-rules.pro` stop R8 merging the two crash sites into a synthetic accessor.
On iOS `ios/scripts/release-build.sh` uploads the dSYM; only a build for a physical device can be symbolicated, because the simulator's binaries are not
accepted as debug files, so the iOS crash is verified as firing in the app code but not as symbolicated.

## Sessions

`session_mode` (a global field on every log) is `per_journey` by default: the simulator starts a new session for each journey, which is what the funnel,
sankey and A/B workflows assume. Switch to `realistic` on the **Advanced screen, Realism section ("Sessions")**: the SDK is started with
`SessionConfiguration(inactivityTimeout: 30 minutes)`, so one session spans several journeys and background/foreground transitions. The SDK reads the
setting only at start, so it applies on the next launch. Both platforms log `previous_run_terminated` at launch (termination reason, fatal or not).

## Correlation fields

Every log, span, network request and crash report inside a journey carries `journey_id` (a short id per journey) and `step` (the screen the journey is on),
both global fields.

## Business-critical failure and cart data

- **`order_lost`** is logged with `logCritical` when payment succeeded but the order confirmation cannot be fetched. Turn on **Lose orders** (Advanced,
  Realism) to make confirmation lookups fail.
- **`cart_json`** on `checkout_started` is the cart as one JSON string, `{"items":[{"id","category","price","quantity"}],"total":…}`, for JSON-path
  workflow metrics such as revenue by category (`items[].category`, `items[].price`). No workflow using it ships yet.

## Commands

Two handlers are registered with the SDK so an SE or an agent can pull state from a live device:

| Command | Does |
|---------|------|
| `dump_cart_state` | returns the cart as a JSON attachment, with item count and total in the context |
| `flip_flag` (`flag`: string) | flips one of the three install-persistent feature flags (`express_checkout`, `product_card_layout`, `free_shipping_banner`), re-recording the exposure and its `ff_*` field; an unknown flag is rejected |

Commands are registered in the account (not by the app) with `tools/bd-deploy.sh <app_id> --apply`, which reads `workflows/manifest.json`. Then, with the app
running:

```bash
bd command invoke dump_cart_state --entity-id demo
bd command invoke flip_flag --entity-id demo --argument 'flag={"string_data":"express_checkout"}'
```

The persistent flags exist on iOS too now (UserDefaults suite `persistent_flags`), so both commands work on both platforms. The entity id `demo` is shared by every
app, so run one device at a time.

## Where the code is

| | Android (`android/app/src/main/java/ai/bitdrift/shop/`) | iOS (`ios/BitdriftShop/`) |
|---|---|---|
| Crash sites, precursors | `CartPricing.kt`, `PromoBannerParser.kt`, `Crashes.kt` | `CartPricing.swift`, `PromoBannerParser.swift`, `Crashes.swift` |
| Session mode, Lose orders | `DemoSettings.kt`, `ShoppingDemoApp.kt`, `Screens.kt` | `DemoSettings.swift`, `CaptureBridge.swift`, `Screens.swift` |
| `cart_json` | `CartJson.kt` | `CartJson.swift` |
| Commands, flags | `AppCommands.kt`, `PersistentFeatureFlags.kt` | `AppCommands.swift`, `PersistentFeatureFlags.swift` |
| Journey adapter | `SimulationManager.kt` | `SimulationManager.swift` |
