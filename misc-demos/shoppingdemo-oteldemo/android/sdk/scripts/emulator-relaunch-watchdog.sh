#!/usr/bin/env bash
# NOTE: intentionally no `set -e` — the main loop must survive transient adb failures
set -uo pipefail

PKG="com.example.shoppingdemo"
ACTIVITY="com.example.shoppingdemo/.MainActivity"
SERIAL=""
INTERVAL_SECS=2
TAP_X=""
TAP_Y=""
EMULATOR_NAME=""

ts() {
  date '+%Y-%m-%d %H:%M:%S'
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [-s emulator-5554] [-p package] [-a package/.Activity] [-i seconds]

Monitors the emulator for ANR dialogs and auto-dismisses them.
The app's own crash-loop handler restarts after crashes; this script
only handles ANR dialogs which the app cannot dismiss itself.

Options:
  -s SERIAL   ADB device serial (recommended). If omitted, script auto-selects
              only when exactly one emulator is connected.
  -p PACKAGE  Android package name (default: com.example.shoppingdemo)
  -a ACTIVITY Fully qualified launch activity (default: com.example.shoppingdemo/.MainActivity)
  -i SECONDS  Poll interval in seconds (default: 2)
  -h          Show help
EOF
}

while getopts ":s:p:a:i:h" opt; do
  case "$opt" in
    s) SERIAL="$OPTARG" ;;
    p) PKG="$OPTARG" ;;
    a) ACTIVITY="$OPTARG" ;;
    i) INTERVAL_SECS="$OPTARG" ;;
    h)
      usage
      exit 0
      ;;
    :)
      echo "Missing value for -$OPTARG" >&2
      usage
      exit 2
      ;;
    \?)
      echo "Unknown option: -$OPTARG" >&2
      usage
      exit 2
      ;;
  esac
done

ADB=(adb)
# Auto-detect adb if not on PATH
if ! command -v adb >/dev/null 2>&1; then
  if [[ -x "$HOME/Library/Android/sdk/platform-tools/adb" ]]; then
    ADB=("$HOME/Library/Android/sdk/platform-tools/adb")
  else
    echo "Error: adb not found. Add it to PATH or install Android SDK." >&2
    exit 1
  fi
fi

ensure_target_serial() {
  if [[ -n "$SERIAL" ]]; then
    local state
    state=$("${ADB[0]}" devices | awk -v s="$SERIAL" '$1==s {print $2}' | head -1)
    if [[ "$state" != "device" ]]; then
      echo "Error: target serial '$SERIAL' is not connected as a device." >&2
      echo "Tip: run 'adb devices' and pass -s emulator-XXXX." >&2
      exit 1
    fi
    return 0
  fi

  local emulators count
  emulators=$("${ADB[0]}" devices | awk '/^emulator-[0-9]+[[:space:]]+device$/ {print $1}')
  count=$(echo "$emulators" | sed '/^$/d' | wc -l | tr -d ' ')

  if [[ "$count" == "1" ]]; then
    SERIAL=$(echo "$emulators" | head -1)
    return 0
  fi

  if [[ "$count" == "0" ]]; then
    echo "Error: no running emulator detected." >&2
  else
    echo "Error: multiple emulators detected. To avoid affecting other emulators, pass -s SERIAL." >&2
    echo "Connected emulators:" >&2
    while IFS= read -r serial; do
      [[ -z "$serial" ]] && continue
      echo "  $serial ($(get_emulator_name "$serial"))" >&2
    done <<< "$emulators"
  fi
  exit 1
}

get_emulator_name() {
  local serial="$1"
  local avd_name model
  avd_name=$("${ADB[0]}" -s "$serial" emu avd name 2>/dev/null | tr -d '\r' | head -1) || true
  if [[ -n "$avd_name" ]] && [[ "$avd_name" != "OK" ]]; then
    echo "$avd_name"
    return 0
  fi

  model=$("${ADB[0]}" -s "$serial" shell getprop ro.product.model 2>/dev/null | tr -d '\r' | head -1) || true
  if [[ -n "$model" ]]; then
    echo "$model"
    return 0
  fi

  echo "unknown"
}

ensure_target_serial
if [[ -n "$SERIAL" ]]; then
  ADB+=( -s "$SERIAL" )
fi
EMULATOR_NAME=$(get_emulator_name "$SERIAL")

start_app() {
  "${ADB[@]}" shell am start -n "$ACTIVITY" >/dev/null 2>&1 || true
}

force_stop() {
  "${ADB[@]}" shell am force-stop "$PKG" >/dev/null 2>&1 || true
}

resolve_tap_coords() {
  local size_line size width height
  size_line=$("${ADB[@]}" shell wm size 2>/dev/null | tr -d '\r' | grep -E "Override size|Physical size" | head -1) || true
  size=$(echo "$size_line" | grep -Eo '[0-9]+x[0-9]+' | head -1) || true

  if [[ -n "$size" ]]; then
    width=${size%x*}
    height=${size#*x}
    if [[ "$width" =~ ^[0-9]+$ ]] && [[ "$height" =~ ^[0-9]+$ ]] && [[ "$width" -gt 0 ]] && [[ "$height" -gt 0 ]]; then
      TAP_X=$((width / 2))
      TAP_Y=$((height / 2))
      return 0
    fi
  fi

  # Fallback for the workshop default emulator resolution (1080x2400).
  TAP_X=540
  TAP_Y=1200
  return 0
}

# Detect ANR dialog using dumpsys window (fast, works even when app is frozen).
# uiautomator dump gets killed (exit 137) when the main thread is blocked.
check_anr_dialog() {
  local windows
  windows=$("${ADB[@]}" shell dumpsys window windows 2>/dev/null) || { echo "[$(ts)] [poll] dumpsys window failed"; return 1; }

  # Android ANR surfaces with different strings across OS versions.
  if echo "$windows" | grep -qiE "Application Not Responding|AppNotRespondingDialog|isn.?t responding|ApplicationErrorDialog|ANR"; then
    echo "[$(ts)] [ANR] *** ANR dialog detected via dumpsys window ***"
    return 0
  fi

  # Also check via activity manager for package-specific ANR markers.
  local anr_info
  anr_info=$("${ADB[@]}" shell dumpsys activity 2>/dev/null | grep -iE "ANR in|not responding|AppNotResponding" | head -20) || true
  if echo "$anr_info" | grep -q "$PKG"; then
    echo "[$(ts)] [ANR] *** Active ANR detected for $PKG via dumpsys activity ***"
    return 0
  fi

  # Log current focus for debugging
  local focus
  focus=$(echo "$windows" | grep "mCurrentFocus" | head -1 | sed 's/.*mCurrentFocus=//') || true
  echo "[$(ts)] [poll] no ANR dialog — focus: ${focus:-unknown}"
  return 1
}

# Dismiss ANR: force-stop is the most reliable method.
# We don't need to tap the dialog button — killing the process dismisses it.
dismiss_anr() {
  echo "[$(ts)] [ANR] force-stopping $PKG to dismiss ANR"
  force_stop
  sleep 1
  echo "[$(ts)] [ANR] relaunching app"
  start_app
  echo "[$(ts)] [ANR] app relaunched"
}

is_variant_a_restart_pending() {
  local prefs_xml
  prefs_xml=$("${ADB[@]}" shell run-as "$PKG" cat shared_prefs/anr_a.xml 2>/dev/null | tr -d '\r') || true

  if [[ -z "$prefs_xml" ]]; then
    echo "[$(ts)] [gate] unable to read anr_a prefs via run-as; skipping relaunch for safety"
    return 1
  fi

  if ! echo "$prefs_xml" | grep -q 'name="active" value="true"'; then
    return 1
  fi

  if ! echo "$prefs_xml" | grep -q 'name="restart_pending" value="true"'; then
    return 1
  fi

  if echo "$prefs_xml" | grep -Eq 'name="restart_variant"( value="VARIANT_A")?>VARIANT_A<|name="restart_variant" value="VARIANT_A"'; then
    return 0
  fi

  return 1
}

echo "[$(ts)] ANR auto-dismiss watchdog active"
echo "[$(ts)] package=$PKG activity=$ACTIVITY interval=${INTERVAL_SECS}s serial=${SERIAL:-default} emulator=${EMULATOR_NAME}"
echo "[$(ts)] gate=Variant-A-only"
echo "[$(ts)] NOTE: Crash restarts are handled by the app itself; this script only dismisses ANR dialogs."
echo "[$(ts)] Press Ctrl+C to stop"

"${ADB[@]}" wait-for-device >/dev/null
resolve_tap_coords
echo "[$(ts)] tap target resolved to (${TAP_X},${TAP_Y})"

POLL_COUNT=0

while true; do
  POLL_COUNT=$((POLL_COUNT + 1))

  # Send a touch event to the CENTER of the screen so it hits the app window.
  # (1,1) goes to the status bar / SystemUI and never triggers app ANR detection.
  # The input dispatcher queues this for the focused app; if the main thread is
  # frozen, the pending touch triggers the ANR dialog after ~5s.
  echo "[$(ts)] [poll #$POLL_COUNT] sending touch to app window (${TAP_X},${TAP_Y})"
  "${ADB[@]}" shell input tap "$TAP_X" "$TAP_Y" >/dev/null 2>&1 || echo "[$(ts)] [poll #$POLL_COUNT] touch failed"

  # Check for ANR dialog and dismiss + relaunch
  if check_anr_dialog; then
    if is_variant_a_restart_pending; then
      dismiss_anr
    else
      echo "[$(ts)] [gate] ANR seen but Variant A restart is not pending; not relaunching"
    fi
  fi

  sleep "$INTERVAL_SECS"
done
