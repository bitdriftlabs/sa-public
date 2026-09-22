#!/usr/bin/env bash
# Build and run the app on the connected emulator (no Android Studio).
#
# Pipeline: gradlew install<Variant> -> adb launch.
#
# No key-baking step here, unlike some other apps in this repo — this app's
# build.gradle.kts already reads BITDRIFT_SDK_KEY / BITDRIFT_API_HOST /
# OTEL_DEMO_HOST / OTEL_DEMO_PORT straight from local.properties/
# .local.properties (or the shell env as a fallback, which loses to
# local.properties if both are set) into BuildConfig, so gradlew just needs
# to run with those already in place. See README.md#local-config.
#
# The launch component below is fully qualified because this app's
# applicationId (ai.bitdrift.oteldemo) differs from its source namespace
# (com.example.shoppingdemo, see app/build.gradle.kts) — the ".MainActivity"
# shorthand `adb` normally accepts only works when those two match.
#
# Requires a running emulator (scripts/android-2-start-emulator.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK_DIR="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
BUILD_VARIANT="${BUILD_VARIANT:-Debug}"
PKG="ai.bitdrift.oteldemo"
ACTIVITY="$PKG/com.example.shoppingdemo.MainActivity"
export PATH="$SDK_DIR/platform-tools:$PATH"
export ANDROID_HOME="$SDK_DIR"

# 1. A connected emulator.
EMU_ID="$(adb devices | awk 'NR>1 && $2=="device"{print $1}' | grep -E '^emulator-' | head -n1 || true)"
if [[ -z "$EMU_ID" ]]; then
  echo "No emulator attached. Start one first: bash scripts/android-2-start-emulator.sh"
  exit 1
fi
echo "Targeting emulator: $EMU_ID"

# 2. Warn (don't fail) if no credentials are configured anywhere gradle looks.
if [[ ! -f "$ROOT/local.properties" && ! -f "$ROOT/.local.properties" && -z "${BITDRIFT_SDK_KEY:-}" ]]; then
  echo "WARNING: no local.properties/.local.properties and no BITDRIFT_SDK_KEY in the" >&2
  echo "environment — the app will build without a key. See README.md#local-config." >&2
fi

# 3. Build + install. installDebug/installRelease already builds first.
cd "$ROOT"
./gradlew ":app:install${BUILD_VARIANT}" --console=plain

# 4. Launch.
adb -s "$EMU_ID" shell am start -n "$ACTIVITY"
echo "Launched $PKG on $EMU_ID"
echo "Stop it with: bash scripts/android-4-stop-app.sh"
