#!/usr/bin/env bash
# Repeatedly foregrounds and backgrounds ai.bitdrift.shop via adb, to generate
# AppStart/AppStop lifecycle logs for the bd-shop-13/14/15 workflows (session
# count, session duration, crash rate per foreground) without a human
# switching apps by hand. See workflows/foreground-session-metrics.md for
# what those workflows chart and why.
#
# A genuinely in-app version of this (a toggle that backgrounds itself and
# then self-resumes on a timer) was tried and dropped: Android's
# background-activity-launch policy blocks a backgrounded app from bringing
# itself back to the foreground (confirmed via logcat: "Background activity
# launch blocked! goo.gle/android-bal"). adb's `am start` is not subject to
# that restriction, so this stays external.
#
# Usage:
#   ./foreground-cycle.sh        # cycle forever, until Ctrl-C
#   ./foreground-cycle.sh -10    # cycle exactly 10 times
set -euo pipefail

usage() {
  echo "Usage: $(basename "$0") [-N]" >&2
  echo "  No flag: cycle forever (Ctrl-C to stop). -N: cycle exactly N times." >&2
  exit 1
}

CYCLES="${CYCLES:-}"
if [[ $# -gt 0 ]]; then
  [[ "$1" =~ ^-([0-9]+)$ ]] || usage
  CYCLES="${BASH_REMATCH[1]}"
fi

SDK_DIR="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export PATH="$SDK_DIR/platform-tools:$PATH"

PKG="ai.bitdrift.shop"
FOREGROUND_SECONDS="${FOREGROUND_SECONDS:-6}"
BACKGROUND_SECONDS="${BACKGROUND_SECONDS:-5}"

EMU_ID="$(adb devices | awk 'NR>1 && $2=="device"{print $1}' | head -n1 || true)"
if [[ -z "$EMU_ID" ]]; then
  echo "No device/emulator attached." >&2
  exit 1
fi

if [[ -n "$CYCLES" ]]; then
  echo "Cycling $PKG on $EMU_ID: $CYCLES foreground/background cycles" \
    "(${FOREGROUND_SECONDS}s foreground, ${BACKGROUND_SECONDS}s background each)"
else
  echo "Cycling $PKG on $EMU_ID indefinitely (Ctrl-C to stop)" \
    "(${FOREGROUND_SECONDS}s foreground, ${BACKGROUND_SECONDS}s background each)"
fi

adb -s "$EMU_ID" shell am start -n "$PKG/.MainActivity" >/dev/null

i=0
while [[ -z "$CYCLES" || "$i" -lt "$CYCLES" ]]; do
  i=$((i + 1))
  sleep "$FOREGROUND_SECONDS"
  adb -s "$EMU_ID" shell input keyevent KEYCODE_HOME
  sleep "$BACKGROUND_SECONDS"
  adb -s "$EMU_ID" shell am start -n "$PKG/.MainActivity" >/dev/null
  if [[ -n "$CYCLES" ]]; then
    echo "cycle $i/$CYCLES done"
  else
    echo "cycle $i done"
  fi
done

echo "Done. Charts: bd workflow charts <bd-shop-13/14/15 workflow id> -ojson --last 1h"
