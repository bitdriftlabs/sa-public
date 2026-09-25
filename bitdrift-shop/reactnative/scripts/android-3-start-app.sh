#!/usr/bin/env bash
# Start Metro (if not already running) and build/install/launch the app on
# the connected emulator, via the React Native CLI — no Android Studio.
#
# Unlike ../../android/scripts/android-3-start-app.sh (native app, gradlew
# directly) and ../../flutter/scripts/android-3-start-app.sh (flutter build
# apk), there's no key-baking step here: this app reads BITDRIFT_SDK_KEY from
# .env via react-native-dotenv at Metro *bundle* time (src/config.ts), so
# restarting Metro with --reset-cache (metro-lib.sh does this) is all that's
# needed to pick up a changed .env.
#
# Requires a running emulator (scripts/android-2-start-emulator.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK_DIR="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export PATH="$SDK_DIR/platform-tools:$PATH"
export ANDROID_HOME="$SDK_DIR"

# shellcheck source=metro-lib.sh
source "$ROOT/scripts/metro-lib.sh"

# 1. A connected emulator.
EMU_ID="$(adb devices | awk 'NR>1 && $2=="device"{print $1}' | grep -E '^emulator-' | head -n1 || true)"
if [[ -z "$EMU_ID" ]]; then
  echo "No emulator attached. Start one first: bash scripts/android-2-start-emulator.sh"
  exit 1
fi
echo "Targeting emulator: $EMU_ID"

# 2. Warn (don't fail) if no key is configured.
if [[ ! -f "$ROOT/.env" ]] && [[ -z "${BITDRIFT_SDK_KEY:-}" ]]; then
  echo "WARNING: no .env and no BITDRIFT_SDK_KEY in the environment — the app" >&2
  echo "will build without a key. See README.md § Configuration." >&2
fi

# 3. Gradle 8.10.2 cannot run on Java 24+, and Android Studio's bundled JBR
#    can be newer — prefer an explicit JDK 17 (mirrors ../start.sh).
if [[ -z "${JAVA_HOME:-}" ]] || ! "$JAVA_HOME/bin/java" -version 2>&1 | grep -q '"17\.'; then
  JDK17="$(/usr/libexec/java_home -v 17 2>/dev/null || true)"
  if [[ -z "$JDK17" ]]; then
    JDK17="$(ls -d "$HOME"/Library/Java/JavaVirtualMachines/jdk-17*/Contents/Home 2>/dev/null | head -1)"
  fi
  if [[ -n "$JDK17" ]]; then
    echo "Using JDK 17 at $JDK17"
    export JAVA_HOME="$JDK17"
  else
    echo "ERROR: No JDK 17 found, and Gradle 8.10.2 cannot run on Java 24+." >&2
    echo "       Install it: brew install --cask temurin@17" >&2
    exit 1
  fi
fi
export PATH="$JAVA_HOME/bin:$PATH"

# 4. Metro must be up before `run-android` tries to fetch a bundle.
start_metro_background

# 5. Build + install + launch. Only one emulator is ever expected to be
#    attached here (same precondition as every other *-3-start-app.sh in
#    this repo), so no --device targeting is needed.
cd "$ROOT"
npx react-native run-android --no-packager

echo "Launched ai.bitdrift.rn.shop on $EMU_ID"
echo "Stop it with: bash scripts/android-4-stop-app.sh"
