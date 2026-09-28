#!/usr/bin/env bash
# Build and run BitdriftShopOtel on the booted iOS Simulator (no Xcode UI).
#
# Credentials come from .local.xcconfig (BITDRIFT_SDK_KEY, OTEL_DEMO_HOST, etc. --
# see README.md#local-config) -- xcodebuild picks these up automatically via
# local.xcconfig's baseConfigurationReference, no key-baking step needed here.
#
# Requires a booted simulator (scripts/ios-3-start-simulator.sh) and a generated
# project (scripts/ios-2-generate-project.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PROJECT="BitdriftShopOtel.xcodeproj"
SCHEME="BitdriftShopOtel"
BUNDLE_ID="ai.bitdrift.oteldemo.ios"
DERIVED="build/debug"

if [[ ! -d "$PROJECT" ]]; then
  echo "No $PROJECT found. Generate it first: bash scripts/ios-2-generate-project.sh" >&2
  exit 1
fi

TARGET_ID="$(xcrun simctl list devices booted | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' | head -n1 || true)"
if [[ -z "$TARGET_ID" ]]; then
  echo "No simulator booted. Start one first: bash scripts/ios-3-start-simulator.sh" >&2
  exit 1
fi
echo "Targeting simulator: $TARGET_ID"

if [[ ! -f .local.xcconfig ]] || ! grep -q "BITDRIFT_SDK_KEY" .local.xcconfig 2>/dev/null; then
  echo "WARNING: .local.xcconfig missing or has no BITDRIFT_SDK_KEY — the app" >&2
  echo "         will build but start without a key. See README.md#local-config." >&2
fi

echo "Building $SCHEME for the simulator ..."
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Debug \
  -destination "id=$TARGET_ID" -derivedDataPath "$DERIVED" build 2>&1 \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
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

# Terminate first: `simctl launch` on an already-running process is a no-op that
# just returns the existing PID rather than restarting it, so without this,
# reinstalling a freshly-built binary over a still-running process would leave
# the *old* in-memory build running indefinitely.
xcrun simctl terminate "$TARGET_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$TARGET_ID" "$APP"
xcrun simctl launch "$TARGET_ID" "$BUNDLE_ID"
echo "Launched $BUNDLE_ID on $TARGET_ID"
echo "Stop it with: bash scripts/ios-5-stop-app.sh"
