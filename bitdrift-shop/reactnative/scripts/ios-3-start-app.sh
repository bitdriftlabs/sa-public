#!/usr/bin/env bash
# Start Metro (if not already running) and build/install/launch the app on
# the booted Simulator — no Xcode UI.
#
# Builds via plain `xcodebuild` + `xcrun simctl install/launch` rather than
# `react-native run-ios`: that CLI's runOnSimulator step unconditionally
# shells out to `open .../Applications/Simulator.app` *before* it builds, to
# bring the Simulator window forward. Xcode 27 folded Simulator.app into
# DeviceHub.app (see ios-2-start-simulator.sh), so that path no longer
# exists and the `open` call throws — aborting the whole command before any
# build/install/launch happens, even with a simulator already booted and
# visible. simctl has no such dependency.
#
# Unlike ../../ios/scripts/ios-3-start-app.sh (native app, plain xcodebuild)
# and ../../flutter/scripts/ios-3-start-app.sh (flutter build ios), there's
# no key-baking step here: this app reads BITDRIFT_SDK_KEY from .env via
# react-native-dotenv at Metro *bundle* time (src/config.ts), so restarting
# Metro with --reset-cache (metro-lib.sh does this) is all that's needed to
# pick up a changed .env.
#
# Targets the booted simulator by UDID rather than by name (what
# package.json's `npm run ios` hardcodes as "iPhone 16e"): that model isn't
# installed on every machine, and this way whatever ios-2-start-simulator.sh
# actually booted — including its own fallback — is exactly what gets
# targeted here, with no risk of the two disagreeing.
#
# Requires a booted simulator (scripts/ios-2-start-simulator.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=metro-lib.sh
source "$ROOT/scripts/metro-lib.sh"
# shellcheck source=demo-lib.sh
source "$ROOT/scripts/demo-lib.sh"

# 1. A booted simulator.
SIM_ID="$(xcrun simctl list devices booted | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' | head -n1 || true)"
if [[ -z "$SIM_ID" ]]; then
  echo "No simulator booted. Start one first: bash scripts/ios-2-start-simulator.sh"
  exit 1
fi
echo "Targeting simulator: $SIM_ID"

# 2. Warn (don't fail) if no key is configured.
if [[ ! -f "$ROOT/.env" ]] && [[ -z "${BITDRIFT_SDK_KEY:-}" ]]; then
  echo "WARNING: no .env and no BITDRIFT_SDK_KEY in the environment — the app" >&2
  echo "will build without a key. See README.md § Configuration." >&2
fi

if [[ ! -d "$ROOT/ios/Pods" ]]; then
  echo "ERROR: ios/Pods missing. Run: bash scripts/ios-1-setup.sh" >&2
  exit 1
fi

# 3. Metro must be up before the app tries to fetch a bundle.
start_metro_background

# 4. Build. -derivedDataPath keeps the product under ios/build (gitignored)
#    so its path is predictable rather than having to hunt for it under
#    ~/Library/Developer/Xcode/DerivedData. -quiet leaves only warnings/
#    errors and xcodebuild's own pass/fail line.
echo "Building (this can take a few minutes on a clean checkout) ..."
cd "$ROOT/ios"
xcodebuild -workspace ShopDemoRN.xcworkspace -scheme BitdriftShop \
  -configuration Debug -sdk iphonesimulator -destination "id=$SIM_ID" \
  -derivedDataPath build -quiet build
APP_PATH="build/Build/Products/Debug-iphonesimulator/BitdriftShop.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "ERROR: build succeeded but $APP_PATH is missing." >&2
  exit 1
fi

# 5. Install + launch, via demo-lib.sh's helpers (retries + verifies, same as
#    ios-foreground-cycle.sh/ios-4-stop-app.sh).
xcrun simctl install "$SIM_ID" "$APP_PATH"
resolve_target sim "$SIM_ID"
launch_app

echo "Launched $BUNDLE_ID on $SIM_ID"
echo "Stop it with: bash scripts/ios-4-stop-app.sh"
