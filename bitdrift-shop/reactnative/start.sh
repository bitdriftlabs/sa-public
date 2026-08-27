#!/bin/bash
# start.sh — convenience launcher for the Shopping Demo (React Native SDK)
#
# Usage:
#   ./start.sh          — install deps, start Metro in the foreground
#   ./start.sh ios      — install deps, start Metro + launch iOS simulator
#   ./start.sh android  — install deps, start Metro + launch Android emulator

set -e

PLATFORM="${1:-}"

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
    # --repo-update so a newly bumped BitdriftCapture version resolves; without it
    # pod install fails with "None of your spec sources contain a spec satisfying
    # the dependency: BitdriftCapture (= x.y.z)".
    (cd ios && pod install --repo-update)
  else
    echo "==> ios/Pods found, skipping pod install"
  fi
fi

# Gradle 8.10.2 cannot run on Java 24+, and Android Studio's bundled JBR is Java 25.
# Prefer an explicit JDK 17 so ./gradlew doesn't crash on daemon startup.
if [[ "$PLATFORM" == "android" ]]; then
  if [[ -z "$JAVA_HOME" ]] || ! "$JAVA_HOME/bin/java" -version 2>&1 | grep -q '"17\.'; then
    JDK17="$(/usr/libexec/java_home -v 17 2>/dev/null || true)"
    if [[ -z "$JDK17" ]]; then
      # Fall back to a home-directory Temurin unpack (see README § JDK 17).
      JDK17="$(ls -d "$HOME"/Library/Java/JavaVirtualMachines/jdk-17*/Contents/Home 2>/dev/null | head -1)"
    fi
    if [[ -n "$JDK17" ]]; then
      echo "==> Using JDK 17 at $JDK17"
      export JAVA_HOME="$JDK17"
    else
      echo "ERROR: No JDK 17 found, and Gradle 8.10.2 cannot run on Java 24+."
      echo "       Install it:  brew install --cask temurin@17"
      echo "       See README.md § 'JDK 17 is required for Android'."
      exit 1
    fi
  fi
  export PATH="$JAVA_HOME/bin:$PATH"
fi

metro_running() {
  curl -s -m 2 http://localhost:8081/status 2>/dev/null | grep -q "packager-status:running"
}

# Clear Metro transform cache so react-native-dotenv (@env) is re-evaluated. Without
# this a stale bundle keeps serving the previous .env values (e.g. an old API key).
start_metro_background() {
  if metro_running; then
    echo "==> Metro already running on port 8081"
    return
  fi
  echo "==> Starting Metro in the background (log: /tmp/metro-shop.log)..."
  npx react-native start --reset-cache >/tmp/metro-shop.log 2>&1 &
  for _ in $(seq 1 60); do
    metro_running && break
    sleep 1
  done
  if metro_running; then
    echo "==> Metro ready on port 8081"
  else
    echo "ERROR: Metro failed to start. Last lines of /tmp/metro-shop.log:"
    tail -20 /tmp/metro-shop.log
    echo
    echo "If this says \"Cannot read properties of undefined (reading 'handle')\","
    echo "@react-native-community/cli must be pinned to 15.1.3 — see README.md."
    exit 1
  fi
}

# Launch the selected target
case "$PLATFORM" in
  "")
    echo "==> Killing any existing Metro on port 8081..."
    lsof -ti :8081 2>/dev/null | xargs kill 2>/dev/null || true
    sleep 1
    echo "==> Starting Metro (Ctrl+C to stop)..."
    exec npx react-native start --reset-cache
    ;;
  ios)
    start_metro_background
    echo "==> Starting app on iOS simulator..."
    npx react-native run-ios --scheme BitdriftShop --simulator "iPhone 16e"
    ;;
  android)
    start_metro_background
    echo "==> Starting app on Android emulator..."
    npx react-native run-android --no-packager
    ;;
  *)
    echo "Unknown platform '$PLATFORM'. Use: ./start.sh | ./start.sh ios | ./start.sh android"
    exit 1
    ;;
esac
