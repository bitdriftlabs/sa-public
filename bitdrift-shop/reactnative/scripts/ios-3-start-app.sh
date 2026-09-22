#!/usr/bin/env bash
# Start Metro (if not already running) and build/install/launch the app on
# the booted Simulator, via the React Native CLI — no Xcode UI.
#
# Unlike ../../ios/scripts/ios-3-start-app.sh (native app, plain xcodebuild)
# and ../../flutter/scripts/ios-3-start-app.sh (flutter build ios), there's
# no key-baking step here: this app reads BITDRIFT_API_KEY from .env via
# react-native-dotenv at Metro *bundle* time (src/config.ts), so restarting
# Metro with --reset-cache (metro-lib.sh does this) is all that's needed to
# pick up a changed .env.
#
# Targets the booted simulator by UDID (`--udid`) rather than by name
# (`--simulator "iPhone 16e"`, what package.json's `npm run ios` hardcodes):
# that model isn't installed on every machine, and this way whatever
# ios-2-start-simulator.sh actually booted — including its own fallback — is
# exactly what gets targeted here, with no risk of the two disagreeing.
#
# Requires a booted simulator (scripts/ios-2-start-simulator.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=metro-lib.sh
source "$ROOT/scripts/metro-lib.sh"

# 1. A booted simulator.
SIM_ID="$(xcrun simctl list devices booted | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' | head -n1 || true)"
if [[ -z "$SIM_ID" ]]; then
  echo "No simulator booted. Start one first: bash scripts/ios-2-start-simulator.sh"
  exit 1
fi
echo "Targeting simulator: $SIM_ID"

# 2. Warn (don't fail) if no key is configured.
if [[ ! -f "$ROOT/.env" ]] && [[ -z "${BITDRIFT_API_KEY:-}" ]]; then
  echo "WARNING: no .env and no BITDRIFT_API_KEY in the environment — the app" >&2
  echo "will build without a key. See README.md § Configuration." >&2
fi

if [[ ! -d "$ROOT/ios/Pods" ]]; then
  echo "ERROR: ios/Pods missing. Run: bash scripts/ios-1-setup.sh" >&2
  exit 1
fi

# 3. Metro must be up before `run-ios` tries to fetch a bundle.
start_metro_background

# 4. Build + install + launch.
cd "$ROOT"
npx react-native run-ios --scheme BitdriftShop --udid "$SIM_ID" --no-packager

echo "Launched ai.bitdrift.shop on $SIM_ID"
echo "Stop it with: bash scripts/ios-4-stop-app.sh"
