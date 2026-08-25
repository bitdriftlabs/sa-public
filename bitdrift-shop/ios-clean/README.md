# Bitdrift Shop iOS Clean Demo

A native SwiftUI shopping demo used to validate removal of observability instrumentation. It retains the shopping flow, backend requests, simulations, and fault scenarios, but has no Bitdrift Capture SDK or generated observability configuration.

## Run

1. Start the shared backend from `../backend`.
2. Open `BitdriftShop.xcodeproj` in Xcode and run the app on an iOS Simulator.

The iOS Simulator reaches the backend through the Mac host. The default fallback is `127.0.0.1:5173`. If the backend is on another host or you are using a physical device, set `SHOP_BACKEND_URL` in `.local.xcconfig` using xcconfig URL escaping:

```text
SHOP_BACKEND_URL = http:/$()/192.168.1.20:5173
```

The app package name and Bitdrift Shop branding are sample product identity. The clean target does not send telemetry to Bitdrift.

## Simulation

Use the Welcome or Advanced screen to run a finite or continuous journey. The simulator overlay includes an X button to cancel the active run. Crash, hang, and force-quit scenarios may require the companion watchdog scripts in `scripts/`.

Start `scripts/watchdog.sh` before running persistent fault scenarios. If Fast Crash Mode
relaunches before the UI is usable, run `scripts/check-demo-state.sh --reset` to clear its flags.
