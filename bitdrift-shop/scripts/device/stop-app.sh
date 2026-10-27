#!/usr/bin/env bash
# Stop one demo app without stopping the emulator/simulator it runs on.
#
#   scripts/device/stop-app.sh <native|rn|flutter> <android|ios>
set -euo pipefail

app="${1:-}" platform="${2:-}"
case "$app/$platform" in
  native/android)  id=ai.bitdrift.shop ;;
  native/ios)      id="${BUNDLE_ID:-ai.bitdrift.shop.ios}" ;;
  rn/android)      id=ai.bitdrift.rn.shop ;;
  rn/ios)          id="${BUNDLE_ID:-ai.bitdrift.rn.shop}" ;;
  flutter/android) id=ai.bitdrift.shop.flutter ;;
  flutter/ios)     id=io.bitdrift.bitdriftShopFlutter ;;
  *) echo "usage: ${0##*/} <native|rn|flutter> <android|ios>" >&2; exit 2 ;;
esac

if [[ "$platform" == android ]]; then
  export PATH="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools:$PATH"
  dev="$(adb devices | awk 'NR>1 && $2=="device"{print $1}' | grep -E '^emulator-' | head -n1 || true)"
  if [[ -z "$dev" ]]; then echo "No emulator attached." >&2; exit 1; fi
  adb -s "$dev" shell am force-stop "$id"
else
  dev="$(xcrun simctl list devices booted | grep -oE '[0-9A-Fa-f]{8}-([0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}' | head -n1 || true)"
  if [[ -z "$dev" ]]; then echo "No simulator booted." >&2; exit 1; fi
  xcrun simctl terminate "$dev" "$id"
fi
echo "Stopped $id on $dev"
