#!/usr/bin/env bash
# NOTE: intentionally no `set -e` — the main loop must survive transient adb failures
set -uo pipefail

PKG="ai.bitdrift.shop"
ACTIVITY="ai.bitdrift.shop/.MainActivity"
SERIAL=""
INTERVAL_SECS=2
TAP_X=""
TAP_Y=""
RECENTS_CARD_X=""
RECENTS_CARD_START_Y=""
RECENTS_CARD_END_Y=""
EMULATOR_NAME=""

ts() {
  date '+%Y-%m-%d %H:%M:%S'
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [-s emulator-5554] [-p package] [-a package/.Activity] [-i seconds]

Monitors the emulator for ANR dialogs and force-quit process deaths,
then auto-dismisses / relaunches the app.
  - ANR: detects the system ANR dialog, force-stops, and relaunches.
  - Force-quit: detects restart_pending=true and performs a recents
    swipe-dismiss (user-style), then relaunches.

Options:
  -s SERIAL   ADB device serial (recommended). If omitted, script auto-selects
              only when exactly one emulator is connected.
  -p PACKAGE  Android package name (default: ai.bitdrift.shop)
  -a ACTIVITY Fully qualified launch activity (default: ai.bitdrift.shop/.MainActivity)
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
  local out rc
  out=$("${ADB[@]}" shell am start -n "$ACTIVITY" 2>&1) || rc=$?
  rc=${rc:-0}
  if [[ "$rc" -eq 0 ]]; then
    echo "[$(ts)] [launch] am start ok: ${out//$'\r'/ }"
    return 0
  fi

  echo "[$(ts)] [launch] am start failed (rc=$rc): ${out//$'\r'/ }"
  echo "[$(ts)] [launch] trying monkey launcher fallback"
  "${ADB[@]}" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
  return 0
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
      RECENTS_CARD_X=$((width / 2))
      RECENTS_CARD_START_Y=$((height * 75 / 100))
      RECENTS_CARD_END_Y=$((height * 20 / 100))
      return 0
    fi
  fi

  # Fallback for the default emulator resolution (1080x2400).
  TAP_X=540
  TAP_Y=1200
  RECENTS_CARD_X=540
  RECENTS_CARD_START_Y=1800
  RECENTS_CARD_END_Y=480
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

# Check if force_quit prefs have restart_pending=true.
is_force_quit_restart_pending() {
  local prefs_xml
  prefs_xml=$("${ADB[@]}" shell run-as "$PKG" cat shared_prefs/force_quit.xml 2>/dev/null | tr -d '\r') || true

  if [[ -z "$prefs_xml" ]]; then
    return 1
  fi

  if ! echo "$prefs_xml" | grep -q 'name="restart_pending" value="true"'; then
    return 1
  fi

  return 0
}

is_force_quit_active() {
  local prefs_xml
  prefs_xml=$("${ADB[@]}" shell run-as "$PKG" cat shared_prefs/force_quit.xml 2>/dev/null | tr -d '\r') || true

  if [[ -z "$prefs_xml" ]]; then
    return 1
  fi

  if ! echo "$prefs_xml" | grep -q 'name="active" value="true"'; then
    return 1
  fi

  return 0
}

# Check if the app process is currently running.
is_app_running() {
  local pid
  pid=$("${ADB[@]}" shell pidof "$PKG" 2>/dev/null | tr -d '\r') || true
  [[ -n "$pid" ]]
}

relaunch_app_with_wait() {
  echo "[$(ts)] [force-quit] relaunching app"
  start_app

  local i
  for i in 1 2 3 4 5; do
    if is_app_running; then
      echo "[$(ts)] [force-quit] app relaunched (process detected)"
      return 0
    fi
    sleep 1
  done

  echo "[$(ts)] [force-quit] relaunch requested but process not detected yet"
  return 1
}

request_user_force_quit() {
  echo "[$(ts)] [force-quit] requesting user-style dismiss via recents swipe"

  "${ADB[@]}" shell input keyevent KEYCODE_APP_SWITCH >/dev/null 2>&1 || true
  sleep 1
  "${ADB[@]}" shell input swipe "$RECENTS_CARD_X" "$RECENTS_CARD_START_Y" "$RECENTS_CARD_X" "$RECENTS_CARD_END_Y" 180 >/dev/null 2>&1 || true
  sleep 1
  "${ADB[@]}" shell input keyevent KEYCODE_HOME >/dev/null 2>&1 || true

  local i
  for i in 1 2 3; do
    if ! is_app_running; then
      echo "[$(ts)] [force-quit] app dismissed from recents"
      return 0
    fi
    sleep 1
  done

  echo "[$(ts)] [force-quit] recents dismiss not confirmed; falling back to force-stop"
  force_stop
  sleep 1
  if ! is_app_running; then
    return 0
  fi

  echo "[$(ts)] [force-quit] app still running after dismiss attempt"
  return 1
}

# Check whether crash loop mode is currently active.
# The app pre-schedules its own AlarmManager restart before each crash, so the
# watchdog is purely a safety net for cases where the alarm gets dropped (e.g.
# a native signal crash on a device that clears pending alarms on process death).
is_crash_loop_active() {
  local xml
  xml=$("${ADB[@]}" shell run-as "$PKG" cat shared_prefs/crash_loop.xml 2>/dev/null | tr -d '\r') || true
  [[ -n "$xml" ]] && echo "$xml" | grep -q 'name="active" value="true"'
}

# Check if ANR-A mode is currently active (not restart_pending, just the toggle).
is_anr_a_active() {
  local prefs_xml
  prefs_xml=$("${ADB[@]}" shell run-as "$PKG" cat shared_prefs/anr_a.xml 2>/dev/null | tr -d '\r') || true
  [[ -n "$prefs_xml" ]] && echo "$prefs_xml" | grep -q 'name="active" value="true"'
}

# Check whether the app currently has an activity task in ActivityManager.
# This catches cases where the process survives but no app task exists.
is_app_task_present() {
  local out
  out=$("${ADB[@]}" shell dumpsys activity activities 2>/dev/null | tr -d '\r') || true
  [[ -n "$out" ]] && echo "$out" | grep -q "$PKG/"
}

echo "[$(ts)] ANR + force-quit + crash-loop watchdog active"
echo "[$(ts)] package=$PKG activity=$ACTIVITY interval=${INTERVAL_SECS}s serial=${SERIAL:-default} emulator=${EMULATOR_NAME}"
echo "[$(ts)] Handles: ANR dialogs (Variant-A gate), force-quit restarts, crash-loop safety net"
echo "[$(ts)] NOTE: Crash restarts are primarily handled by the app's own AlarmManager. This script"
echo "[$(ts)]       is a safety net for cases where the alarm is dropped after a native signal crash."
echo "[$(ts)] Press Ctrl+C to stop"

"${ADB[@]}" wait-for-device >/dev/null
resolve_tap_coords
echo "[$(ts)] tap target resolved to (${TAP_X},${TAP_Y})"
echo "[$(ts)] recents dismiss swipe: (${RECENTS_CARD_X},${RECENTS_CARD_START_Y}) -> (${RECENTS_CARD_X},${RECENTS_CARD_END_Y})"

POLL_COUNT=0
FORCE_QUIT_RELAUNCH_ARMED=0
FORCE_QUIT_RELAUNCH_ARM_MAX=5
FORCE_QUIT_MODE_SEEN=0
ANR_MODE_SEEN=0
CRASH_LOOP_MODE_SEEN=0
DEAD_POLL_COUNT=0
DEAD_POLL_FALLBACK_RELAUNCH_AFTER=2
MISSING_TASK_POLLS=0
MISSING_TASK_RELAUNCH_AFTER=2

while true; do
  POLL_COUNT=$((POLL_COUNT + 1))

  if is_force_quit_active; then
    FORCE_QUIT_MODE_SEEN=1
  fi
  if is_anr_a_active; then
    ANR_MODE_SEEN=1
  fi
  if is_crash_loop_active; then
    CRASH_LOOP_MODE_SEEN=1
  fi

  if is_app_running && is_force_quit_restart_pending; then
    if request_user_force_quit; then
      FORCE_QUIT_RELAUNCH_ARMED=$FORCE_QUIT_RELAUNCH_ARM_MAX
      sleep "$INTERVAL_SECS"
      continue
    fi
  fi

  # First priority: force-quit restart (independent of ANR mode).
  # If process is dead and force_quit restart is pending, relaunch immediately.
  if ! is_app_running; then
    DEAD_POLL_COUNT=$((DEAD_POLL_COUNT + 1))

    if is_force_quit_restart_pending; then
      FORCE_QUIT_RELAUNCH_ARMED=$FORCE_QUIT_RELAUNCH_ARM_MAX
      echo "[$(ts)] [force-quit] *** App not running with force_quit restart pending ***"
    elif is_force_quit_active; then
      # restart_pending can clear quickly after a brief launch/resume cycle;
      # keep relaunching while force-quit mode is still enabled.
      FORCE_QUIT_RELAUNCH_ARMED=$FORCE_QUIT_RELAUNCH_ARM_MAX
      echo "[$(ts)] [force-quit] app not running while force_quit mode is active"
    elif [[ "$FORCE_QUIT_MODE_SEEN" -eq 1 ]]; then
      # If prefs become temporarily unreadable, continue recovery based on
      # previously observed force-quit mode.
      FORCE_QUIT_RELAUNCH_ARMED=$FORCE_QUIT_RELAUNCH_ARM_MAX
      echo "[$(ts)] [force-quit] app down; force-quit mode was previously active, relaunching"
    fi

    if [[ "$FORCE_QUIT_RELAUNCH_ARMED" -gt 0 ]]; then
      if [[ "$FORCE_QUIT_RELAUNCH_ARMED" -lt "$FORCE_QUIT_RELAUNCH_ARM_MAX" ]]; then
        echo "[$(ts)] [force-quit] app still down; retrying relaunch (armed=$FORCE_QUIT_RELAUNCH_ARMED)"
      fi

      if relaunch_app_with_wait; then
        FORCE_QUIT_RELAUNCH_ARMED=0
      else
        FORCE_QUIT_RELAUNCH_ARMED=$((FORCE_QUIT_RELAUNCH_ARMED - 1))
      fi

      sleep "$INTERVAL_SECS"
      continue
    fi

    # Crash loop safety net: the app pre-arms an AlarmManager restart before each crash,
    # but native signal crashes (SIGSEGV/SIGBUS/etc.) can sometimes drop the alarm.
    # If the process is dead and crash loop is active, relaunch as a fallback.
    if is_crash_loop_active; then
      echo "[$(ts)] [crash-loop] app not running while crash loop is active — relaunching"
      relaunch_app_with_wait || true
      sleep "$INTERVAL_SECS"
      continue
    elif [[ "$CRASH_LOOP_MODE_SEEN" -eq 1 ]]; then
      echo "[$(ts)] [crash-loop] app down; crash loop was previously active, relaunching"
      relaunch_app_with_wait || true
      sleep "$INTERVAL_SECS"
      continue
    fi

    if [[ "$DEAD_POLL_COUNT" -ge "$DEAD_POLL_FALLBACK_RELAUNCH_AFTER" ]]; then
      echo "[$(ts)] [fallback] app has been down for $DEAD_POLL_COUNT polls; forcing relaunch"
      relaunch_app_with_wait || true
      sleep "$INTERVAL_SECS"
      continue
    fi

    echo "[$(ts)] [poll #$POLL_COUNT] app not running, no force_quit/crash_loop restart pending"
    sleep "$INTERVAL_SECS"
    continue
  fi

  DEAD_POLL_COUNT=0
  FORCE_QUIT_RELAUNCH_ARMED=0

  # In demo modes, treat missing activity task as down and relaunch.
  if [[ "$FORCE_QUIT_MODE_SEEN" -eq 1 || "$ANR_MODE_SEEN" -eq 1 ]]; then
    if ! is_app_task_present; then
      MISSING_TASK_POLLS=$((MISSING_TASK_POLLS + 1))
      echo "[$(ts)] [poll #$POLL_COUNT] app process alive but no activity task (count=$MISSING_TASK_POLLS)"
      if [[ "$MISSING_TASK_POLLS" -ge "$MISSING_TASK_RELAUNCH_AFTER" ]]; then
        echo "[$(ts)] [recovery] relaunching because task/activity is missing"
        relaunch_app_with_wait || true
        sleep "$INTERVAL_SECS"
        continue
      fi
    else
      MISSING_TASK_POLLS=0
    fi
  else
    MISSING_TASK_POLLS=0
  fi

  fq_status=""
  anr_status=""
  crash_status=""
  if is_force_quit_active; then fq_status="ON"; else fq_status="off"; fi
  if is_anr_a_active; then anr_status="ON"; else anr_status="off"; fi
  if is_crash_loop_active; then crash_status="ON"; else crash_status="off"; fi

  # ANR handling is separate and only active when ANR-A is enabled.
  if [[ "$anr_status" == "ON" ]]; then
    # Send touch to trigger input-dispatch timeout on a frozen UI thread.
    echo "[$(ts)] [poll #$POLL_COUNT] mode: ANR=$anr_status FQ=$fq_status CRASH=$crash_status — sending touch (${TAP_X},${TAP_Y})"
    "${ADB[@]}" shell input tap "$TAP_X" "$TAP_Y" >/dev/null 2>&1 || echo "[$(ts)] [poll #$POLL_COUNT] touch failed"

    if check_anr_dialog; then
      if is_variant_a_restart_pending; then
        dismiss_anr
      else
        echo "[$(ts)] [gate] ANR seen but Variant A restart is not pending; not relaunching"
      fi
    fi
  else
    echo "[$(ts)] [poll #$POLL_COUNT] mode: ANR=$anr_status FQ=$fq_status CRASH=$crash_status — waiting"
  fi

  sleep "$INTERVAL_SECS"
done
