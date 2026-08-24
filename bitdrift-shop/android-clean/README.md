# Bitdrift Shop Android Demo

A small Android shopping demo with simulated browsing, checkout, crash, ANR, and force-quit scenarios.

## Run

Start the shared backend from `../backend`, then open this directory in Android Studio and run the `app` module on an emulator or device. The Android emulator reaches the host backend at `10.0.2.2:5173`; a physical device needs the backend host configured for your LAN.

Use the Welcome or Advanced screen to run finite or continuous simulations. The clean target retains the shopping flow and fault scenarios but has no Bitdrift Capture SDK, telemetry configuration, or generated observability artifacts.

The app's package name and branding are part of the sample product identity. This copy has no observability SDK configuration or generated observability artifacts.
