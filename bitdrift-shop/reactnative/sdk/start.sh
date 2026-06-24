#!/bin/bash
# start.sh — convenience launcher for the Shopping Demo (React Native SDK)
#
# Usage:
#   ./start.sh ios      — install deps, start Metro + launch iOS simulator
#   ./start.sh android  — install deps, start Metro + launch Android emulator

set -e

PLATFORM="${1:-}"

if [[ -z "$PLATFORM" ]]; then
  echo "Usage: ./start.sh ios | android"
  exit 1
fi

echo "==> Shopping Demo (React Native SDK)"

# Install npm dependencies if needed
if [ ! -d "node_modules" ]; then
  echo "==> Installing npm dependencies..."
  npm install
else
  echo "==> node_modules found, skipping npm install"
fi

# Install CocoaPods if targeting iOS
if [[ "$PLATFORM" == "ios" ]]; then
  if ! command -v pod &>/dev/null; then
    echo "ERROR: 'pod' not found. Install CocoaPods: sudo gem install cocoapods"
    exit 1
  fi
  if [ ! -d "ios/Pods" ]; then
    echo "==> Installing CocoaPods..."
    (cd ios && pod install)
  else
    echo "==> ios/Pods found, skipping pod install"
  fi
fi

# Kill any existing Metro on port 8081 (|| true so set -e doesn't trigger when nothing is running)
echo "==> Killing any existing Metro on port 8081..."
lsof -ti :8081 2>/dev/null | xargs kill 2>/dev/null || true
sleep 1

# Clear Metro transform cache so react-native-dotenv (@env) is re-evaluated
echo "==> Clearing Metro cache..."
rm -rf /tmp/metro-* "$TMPDIR/metro-*" 2>/dev/null || true

# Launch the selected target
case "$PLATFORM" in
  ios)
    echo "==> Starting app on iOS simulator..."
    npx react-native run-ios --scheme BitdriftShop --simulator "iPhone 16e"
    ;;
  android)
    echo "==> Starting app on Android emulator..."
    npx react-native run-android
    ;;
  *)
    echo "Unknown platform '$PLATFORM'. Use: ./start.sh ios | android"
    exit 1
    ;;
esac
