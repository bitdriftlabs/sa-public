#!/usr/bin/env bash
# Stop the app without stopping the emulator itself.
set -euo pipefail

SDK_DIR="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export PATH="$SDK_DIR/platform-tools:$PATH"

PKG="ai.bitdrift.shop.flutter"

EMU_ID="$(adb devices | awk 'NR>1 && $2=="device"{print $1}' | grep -E '^emulator-' | head -n1 || true)"
if [[ -z "$EMU_ID" ]]; then
  echo "No emulator attached."
  exit 1
fi

adb -s "$EMU_ID" shell am force-stop "$PKG"
echo "Stopped $PKG on $EMU_ID"
