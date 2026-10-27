# Testing (command line, no IDE)

Part of the [bitdrift Shop README](../README.md). Everything here runs from `bitdrift-shop/` in a terminal.

```bash
./test.sh all unit      # seconds: codegen drift, spec validation, conformance self-test, each app's compile/unit tests
./test.sh all smoke     # ~5 min: build, install and launch every app, auto-run 5 journeys, validate what it emitted
./test.sh android smoke # one app: android | ios | rn-android | rn-ios | flutter-android | flutter-ios
```

`smoke` needs a running (or bootable) Android emulator and iOS simulator, and runs the sim with no taps.
Tune it with `SIM_RUNS`, `SIM_SEED` and `PERSONA` (`control`, `variant_a`, `variant_b`). Each app records the
logs, spans and screen views it emits, and [`tools/conformance`](../tools/conformance/conformance.py) checks them
against [`spec/`](../spec/): known names, required fields, levels, closed spans, one `sim_autorun_complete` marker.

- Android and iOS take launch arguments (`sim_runs`, `sim_seed`, `persona`, `record_file`) and write the record on the device.
- React Native and Flutter can't without native code, so in debug builds they ask a local collector
  (`tools/conformance/collector.py`, started by `test.sh`) for the autorun config and POST their records to it.
- `tools/codegen/generate.sh` regenerates every app's constants from `spec/`; `tools/codegen/check.sh` fails if they drift.

## Crash on demand

Android and iOS accept one more launch argument for the realistic crashes (`spec/crashes.yaml`, `realistic: true`):
`--es crash <name>` (Android intent extra) or `-crash <name>` (iOS), for example `app_coupon_empty_cart` or
`app_promo_banner_payload`. With a journey running (`sim_runs`), the app fires exactly that crash at the journey's crash
point instead of walking the crash sweep. Relaunch the app afterwards so the SDK uploads the report.

## Host-run unit checks

Besides the app builds, the unit tier runs checks that need no device: spec validation (`spec/validate.py --strict`,
which also verifies each `source:` file:line citation; `validate.py --fix-refs` re-points stale ones after edits),
the conformance self-test, the shared journey engine's golden traces on every language, and
`ios/scripts/test-realism.sh` plus Android's `RealismTest` for the realistic-crash app code.

## Devices

`smoke` boots what it needs through [`scripts/device/`](../README.md#emulators-and-simulators-shared-by-every-app),
the same scripts you use by hand.
