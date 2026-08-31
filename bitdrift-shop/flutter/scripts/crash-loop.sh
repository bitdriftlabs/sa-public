#!/usr/bin/env bash
# Crash loop (like the Android demo's crash loop), driven from the CLI the
# way android/scripts/watchdog.sh drives its modes: the script owns the loop
# state. It sets the debug.bd_shop_crash loop flag and keeps relaunching the
# app. On launch the app runs one shopping journey and, when it reaches
# payment, crashes with a random crash shape (like the Android demo's
# "crash on payment"). Each pass is a fresh journey ending in a fresh random
# crash in a live session.
#
# The app itself cannot write the property (SELinux denies untrusted_app the
# property-service socket on this device), so the loop is script-driven.
#
# Stop with Ctrl-C — the property is cleared on exit.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK_DIR="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export PATH="$SDK_DIR/platform-tools:$PATH"

PKG="ai.bitdrift.shop.flutter"
PROP="debug.bd_shop_crash"
EMU_ID="$(adb devices | awk 'NR>1 && $2=="device"{print $1}' | grep -E '^emulator-' | head -n1 || true)"
if [[ -z "$EMU_ID" ]]; then
  EMU_ID="$(adb devices | awk 'NR>1 && $2=="device"{print $1}' | head -n1 || true)"
fi
if [[ -z "$EMU_ID" ]]; then
  echo "No device/emulator attached."
  exit 1
fi

adb -s "$EMU_ID" shell setprop "$PROP" 1
cleanup() { adb -s "$EMU_ID" shell setprop "$PROP" 0; }
trap cleanup EXIT INT TERM

echo "Crash loop started on $EMU_ID (one journey per pass, random crash at payment). Ctrl-C to stop."
while true; do
  adb -s "$EMU_ID" shell am force-stop "$PKG"
  sleep 2
  adb -s "$EMU_ID" shell am start -n "$PKG/.MainActivity" >/dev/null
  # Give the journey time to run and crash at payment.
  sleep 20
done
