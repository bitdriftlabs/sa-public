#!/usr/bin/env bash
# Repeatedly foregrounds and backgrounds ai.bitdrift.shop via adb, without a
# human switching apps by hand. Mirrors ../../android/scripts/foreground-cycle.sh.
#
# Backgrounding goes through ActivityManager (`am start` with a HOME intent)
# rather than `input keyevent KEYCODE_HOME`: the keyevent passes through the
# input dispatcher and can get silently dropped if focus/IME state is mid-
# transition, which is exactly the flakiness this was written to avoid.
#
# Usage:
#   ./android-foreground-cycle.sh        # cycle forever, until Ctrl-C
#   ./android-foreground-cycle.sh -10    # cycle exactly 10 times
#   ./android-foreground-cycle.sh --slow -5   # 30s foreground / 20s background per cycle,
#                                              # instead of the default 6s/5s.
set -euo pipefail

usage() {
  local exit_code="${1:-1}"
  echo "Usage: $(basename "$0") [--slow] [-N]" >&2
  echo "  No flag: cycle forever (Ctrl-C to stop). -N: cycle exactly N times." >&2
  echo "  --slow: 30s foreground / 20s background per cycle, instead of 6s/5s." >&2
  echo "  --help|-h: show this message." >&2
  exit "$exit_code"
}

SLOW=0
REMAINING=()
for arg in "$@"; do
  case "$arg" in
    --help|-h) usage 0 ;;
    --slow) SLOW=1 ;;
    *) REMAINING+=("$arg") ;;
  esac
done
set -- ${REMAINING[@]+"${REMAINING[@]}"}

CYCLES="${CYCLES:-}"
if [[ $# -gt 0 ]]; then
  [[ "$1" =~ ^-([0-9]+)$ ]] || usage
  CYCLES="${BASH_REMATCH[1]}"
fi

SDK_DIR="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export PATH="$SDK_DIR/platform-tools:$PATH"

PKG="ai.bitdrift.shop"
if [[ "$SLOW" -eq 1 ]]; then
  FOREGROUND_SECONDS="${FOREGROUND_SECONDS:-30}"
  BACKGROUND_SECONDS="${BACKGROUND_SECONDS:-20}"
else
  FOREGROUND_SECONDS="${FOREGROUND_SECONDS:-6}"
  BACKGROUND_SECONDS="${BACKGROUND_SECONDS:-5}"
fi

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

# True when $PKG's activity is the resumed (foreground) one.
is_foreground() {
  adb -s "$EMU_ID" shell dumpsys activity activities 2>/dev/null \
    | grep -q "mResumedActivity:.*$PKG"
}

# am start's own exit code is not reliable — it exits 0 even when it prints an
# on-device "Error: ..." (e.g. activity not found, ActivityManager busy). Check
# the output instead, and confirm the transition actually happened rather than
# assuming the adb call landed.
go_foreground() {
  local out attempt
  for attempt in 1 2 3; do
    out="$(adb -s "$EMU_ID" shell am start -n "$PKG/.MainActivity" 2>&1)"
    [[ "$out" == *Error* ]] && echo "warning: am start reported: $out" >&2
    sleep 1
    is_foreground && return 0
  done
  echo "warning: $PKG did not reach the foreground after $attempt attempts" >&2
  return 1
}

# Goes through ActivityManager directly instead of KEYCODE_HOME — see header.
go_background() {
  local out attempt
  for attempt in 1 2 3; do
    out="$(adb -s "$EMU_ID" shell am start -a android.intent.action.MAIN -c android.intent.category.HOME 2>&1)"
    [[ "$out" == *Error* ]] && echo "warning: am start (HOME) reported: $out" >&2
    sleep 1
    is_foreground || return 0
  done
  echo "warning: $PKG still foreground after $attempt attempts to background it" >&2
  return 1
}

go_foreground || true

i=0
while [[ -z "$CYCLES" || "$i" -lt "$CYCLES" ]]; do
  i=$((i + 1))
  sleep "$FOREGROUND_SECONDS"
  go_background || true
  sleep "$BACKGROUND_SECONDS"
  go_foreground || true
  if [[ -n "$CYCLES" ]]; then
    echo "cycle $i/$CYCLES done"
  else
    echo "cycle $i done"
  fi
done

echo "Done."
