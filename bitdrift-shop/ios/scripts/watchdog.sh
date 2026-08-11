#!/usr/bin/env bash
# Keeps the crash / hang / force-quit demos running on a booted Simulator.
#
# Two jobs, both of which iOS gives the app no way to do for itself:
#   1. Relaunch the app after it dies. Android arms an AlarmManager before each
#      deliberate crash so the process comes back on its own; there is no
#      equivalent here.
#   2. Background the app when a background-half crash is armed, so the crash
#      lands with app_metrics.running_state = background (bd-shop-06/07).
#
#   ./scripts/watchdog.sh              # watch the booted simulator
#   ./scripts/watchdog.sh --device UDID
#   ./scripts/watchdog.sh --stop       # stop the app and any running watchdog
#
# Ctrl-C stops watching. `--stop` also terminates the app itself, which is the
# only practical way out of Fast Crash Mode.
set -euo pipefail

# shellcheck source=demo-lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/demo-lib.sh"

PIDFILE="${TMPDIR:-/tmp}/bitdrift-shop-ios-watchdog.pid"
DEVICE=""
STOP=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) DEVICE="${2:-}"; shift 2 ;;
    --stop) STOP=1; shift ;;
    -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

DEVICE="$(resolve_device "$DEVICE")"
if [[ -z "$DEVICE" ]]; then
  echo "No booted simulator found. Boot one first (open -a Simulator) or pass --device UDID." >&2
  exit 1
fi

if [[ "$STOP" -eq 1 ]]; then
  if [[ -f "$PIDFILE" ]]; then
    kill "$(cat "$PIDFILE")" 2>/dev/null || true
    rm -f "$PIDFILE"
    echo "Stopped running watchdog."
  fi
  xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" 2>/dev/null || true
  echo "Terminated $BUNDLE_ID on $DEVICE."
  exit 0
fi

if [[ -z "$(app_container "$DEVICE")" ]]; then
  echo "$BUNDLE_ID is not installed on $DEVICE. Build and run it once first." >&2
  exit 1
fi

echo "$$" > "$PIDFILE"
trap 'rm -f "$PIDFILE"' EXIT

echo "Watching $BUNDLE_ID on $DEVICE. Ctrl-C to stop (or ./scripts/watchdog.sh --stop)."

# The app records how long to wait before relaunching. OOM crashes take tens of
# seconds to actually kill the process, and relaunching early leaves the previous
# attempt's leaked allocation thread accumulating alongside the new one.
restart_delay_seconds() {
  local ms
  ms="$(state_value "$DEVICE" restart_delay_ms 2000)"
  if [[ "$ms" =~ ^[0-9]+$ ]] && [[ "$ms" -gt 0 ]]; then
    echo $(( (ms + 999) / 1000 ))
  else
    echo 2
  fi
}

relaunches=0
backgrounded=0

while true; do
  pid="$(app_pid "$DEVICE")"

  if [[ -n "$pid" ]] && [[ "$(state_value "$DEVICE" awaiting_background false)" == "true" ]]; then
    echo "$(date '+%H:%M:%S')  background crash armed — sending app to the background"
    xcrun simctl launch "$DEVICE" com.apple.springboard >/dev/null 2>&1 || true
    backgrounded=$((backgrounded + 1))
    sleep 5
    continue
  fi

  if [[ -z "$pid" ]]; then
    delay="$(restart_delay_seconds)"
    echo "$(date '+%H:%M:%S')  app not running — relaunching in ${delay}s (relaunch #$((relaunches + 1)), backgrounded ${backgrounded}x)"
    sleep "$delay"
    if xcrun simctl launch "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1; then
      relaunches=$((relaunches + 1))
    else
      echo "$(date '+%H:%M:%S')  launch failed — is the app installed on $DEVICE?"
      sleep 5
    fi
  fi

  sleep 2
done
