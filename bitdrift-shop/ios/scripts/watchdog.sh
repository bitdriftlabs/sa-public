#!/usr/bin/env bash
# Keeps the crash / hang / force-quit demos running, on a Simulator or a real device.
#
# Two jobs, both of which iOS gives the app no way to do for itself:
#   1. Relaunch the app after it dies. Android arms an AlarmManager before each
#      deliberate crash so the process comes back on its own; there is no
#      equivalent here.
#   2. Background the app when a background-half crash is armed, so the crash
#      lands with app_metrics.running_state = background (bd-shop-06/07).
#      Simulator only — see the warning it prints on a device.
#
#   ./scripts/watchdog.sh                    # auto: booted simulator, else connected device
#   ./scripts/watchdog.sh --simulator        # force the booted simulator
#   ./scripts/watchdog.sh --device           # force the connected device
#   ./scripts/watchdog.sh --device <UDID>    # a specific device
#   ./scripts/watchdog.sh --stop             # stop the app and any running watchdog
#
# Ctrl-C stops watching. `--stop` also terminates the app itself, which is the
# only practical way out of Fast Crash Mode.
set -uo pipefail

# shellcheck source=demo-lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/demo-lib.sh"

PIDFILE="${TMPDIR:-/tmp}/bitdrift-shop-ios-watchdog.pid"
STOP=0

parse_target_flags "$@"
for arg in ${PARSED_REST[@]+"${PARSED_REST[@]}"}; do
  case "$arg" in
    --stop) STOP=1 ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

if ! resolve_target "$PARSED_KIND" "$PARSED_ID"; then
  echo "No target found. Boot a simulator, or connect a device and pass --device." >&2
  exit 1
fi

if [[ "$STOP" -eq 1 ]]; then
  if [[ -f "$PIDFILE" ]]; then
    kill "$(cat "$PIDFILE")" 2>/dev/null || true
    rm -f "$PIDFILE"
    echo "Stopped running watchdog."
  fi
  terminate_app
  echo "Terminated $BUNDLE_ID on $(target_label)."
  exit 0
fi

if ! app_installed; then
  echo "$BUNDLE_ID is not installed on $(target_label). Build and install it first." >&2
  exit 1
fi

echo "$$" > "$PIDFILE"
trap 'rm -f "$PIDFILE" "$STATE_CACHE"' EXIT

echo "Watching $BUNDLE_ID on $(target_label). Ctrl-C to stop (or --stop)."
if [[ "$TARGET_KIND" == "device" ]]; then
  echo "NOTE: on a physical device the background half of the crash sweep cannot be"
  echo "      automated — iOS has no remote 'go to background'. When the log says a"
  echo "      background crash is armed, press Home on the phone. Foreground crashes"
  echo "      and hang/force-quit relaunches are fully automatic."
fi

# The app records how long to wait before relaunching. OOM crashes take tens of
# seconds to actually kill the process, and relaunching early leaves the previous
# attempt's leaked allocation thread accumulating alongside the new one.
restart_delay_seconds() {
  local ms; ms="$(state_value restart_delay_ms 2000)"
  if [[ "$ms" =~ ^[0-9]+$ ]] && [[ "$ms" -gt 0 ]]; then
    echo $(( (ms + 999) / 1000 ))
  else
    echo 2
  fi
}

relaunches=0
backgrounded=0
warned_background=0

while true; do
  pid="$(app_pid)"
  refresh_state || true

  if [[ -n "$pid" ]] && [[ "$(state_value awaiting_background false)" == "true" ]]; then
    if background_app; then
      echo "$(date '+%H:%M:%S')  background crash armed — sent app to the background"
      backgrounded=$((backgrounded + 1))
      sleep 5
      continue
    elif [[ "$warned_background" -eq 0 ]]; then
      echo "$(date '+%H:%M:%S')  background crash armed — PRESS HOME on the device to let it fire"
      warned_background=1
    fi
  else
    warned_background=0
  fi

  if [[ -z "$pid" ]]; then
    delay="$(restart_delay_seconds)"
    echo "$(date '+%H:%M:%S')  app not running — relaunching in ${delay}s (relaunch #$((relaunches + 1)), backgrounded ${backgrounded}x)"
    sleep "$delay"
    if launch_app; then
      relaunches=$((relaunches + 1))
    else
      echo "$(date '+%H:%M:%S')  launch failed — is the app still installed and trusted?"
      sleep 5
    fi
  fi

  sleep 2
done
