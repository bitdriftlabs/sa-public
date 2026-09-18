#!/usr/bin/env bash
# Build and run BitdriftShop on the booted iOS Simulator (no Xcode UI).
#
# Credentials come from ios/.local.xcconfig (BITDRIFT_API_KEY, BITDRIFT_API_HOST,
# etc. - see ios-1-setup.sh) - xcodebuild picks these up automatically via the
# project's baseConfigurationReference, so unlike the Flutter app's script there
# is no key-baking step here.
#
# Requires a booted simulator (scripts/ios-2-start-simulator.sh).
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=demo-lib.sh
source "scripts/demo-lib.sh"

PROJECT="BitdriftShop.xcodeproj"
SCHEME="BitdriftShop"
DERIVED="build/debug"

if ! resolve_target sim ""; then
  echo "No simulator booted. Start one first: bash scripts/ios-2-start-simulator.sh" >&2
  exit 1
fi
echo "Targeting simulator: $TARGET_ID"

if [[ ! -f .local.xcconfig ]] || ! grep -q "BITDRIFT_API_KEY" .local.xcconfig 2>/dev/null; then
  echo "WARNING: .local.xcconfig missing or has no BITDRIFT_API_KEY — the app" >&2
  echo "         will build but start without a key. See ios-1-setup.sh." >&2
fi

echo "Building $SCHEME for the simulator ..."
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Debug \
  -destination "id=$TARGET_ID" -derivedDataPath "$DERIVED" build 2>&1 \
  | grep -E "error:|\[bitdrift\]|BUILD (SUCCEEDED|FAILED)"
BUILD_STATUS=${PIPESTATUS[0]}

if [[ "$BUILD_STATUS" -ne 0 ]]; then
  echo "Build failed." >&2
  exit "$BUILD_STATUS"
fi

APP="$(find "$DERIVED/Build/Products" -maxdepth 2 -name "$SCHEME.app" | head -1)"
if [[ -z "$APP" ]]; then
  echo "Build succeeded but $SCHEME.app was not found under $DERIVED/Build/Products." >&2
  exit 1
fi

# Terminate first: `simctl launch` on an already-running process is a no-op
# that just returns the existing PID rather than restarting it (verified:
# calling it twice in a row on a running app returns the same PID both
# times). Without this, reinstalling a freshly-built binary over a process
# that's still alive from a previous run leaves the *old* in-memory build
# running indefinitely -- e.g. still reporting a pre-bump SDK version no
# matter how many times this script re-installs the new one.
terminate_app
xcrun simctl install "$TARGET_ID" "$APP"
launch_app
echo "Launched $BUNDLE_ID on $TARGET_ID"
echo "Stop it with: bash scripts/ios-4-stop-app.sh"
