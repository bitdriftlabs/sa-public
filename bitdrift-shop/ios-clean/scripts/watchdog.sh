#!/usr/bin/env bash
# Keeps the crash / hang / force-quit demos running, on a Simulator or a real device.
#
# Two jobs, both of which iOS gives the app no way to do for itself:
#   1. Relaunch the app after it dies. Android arms an AlarmManager before each
#      deliberate crash so the process comes back on its own; there is no
#      equivalent here.
#   2. Background the app when a background-half crash is armed, so the crash
#      lands while the app is backgrounded.
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
#
# While watching, macOS's "app quit unexpectedly" dialogs are suppressed — a
# crash loop otherwise buries the screen in them. The previous setting is
# restored on exit, including on Ctrl-C.
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

# --stop is handled before target resolution, and unconditionally. A watchdog
# whose device has since disconnected is exactly when you most need to stop it —
# and it holds a *global* macOS CrashReporter preference that only its EXIT trap
# restores, so failing to reach it would leave crash dialogs disabled machine-wide.
if [[ "$STOP" -eq 1 ]]; then
  if [[ -f "$PIDFILE" ]]; then
    kill "$(cat "$PIDFILE")" 2>/dev/null || true
    rm -f "$PIDFILE"
    echo "Stopped running watchdog."
  else
    echo "No watchdog was running."
  fi
  # Terminating the app is best-effort: it needs a live target, which stopping
  # the watchdog does not.
  if resolve_target "$PARSED_KIND" "$PARSED_ID" 2>/dev/null; then
    terminate_app
    echo "Terminated $BUNDLE_ID on $(target_label)."
  else
    echo "No reachable target — skipped terminating the app."
  fi
  exit 0
fi

if ! resolve_target "$PARSED_KIND" "$PARSED_ID"; then
  # resolve_target already explained itself when the choice was ambiguous.
  if [[ "${RESOLVE_ERROR:-none}" == "none" ]]; then
    echo "No target found. Boot a simulator, or connect a device and pass --device." >&2
  fi
  exit 1
fi

if ! app_installed; then
  echo "$BUNDLE_ID is not installed on $(target_label). Build and install it first." >&2
  exit 1
fi

# ── macOS crash dialogs ──────────────────────────────────────────────────
# A crash loop triggers one "app quit unexpectedly" dialog per crash, which
# quickly buries the screen. Suppress them for the duration and put the previous
# setting back on exit — this is a global macOS preference, so leaving it flipped
# would silently disable crash dialogs for everything else on the machine.
#
# Deliberately done here, after --help and --stop have already returned: neither
# needs it, and neither should mutate a system setting on the way past.
CRASH_DIALOG_PREV=""
CRASH_DIALOG_CHANGED=0

suppress_crash_dialogs() {
  CRASH_DIALOG_PREV="$(defaults read com.apple.CrashReporter DialogType 2>/dev/null || true)"
  defaults write com.apple.CrashReporter DialogType none 2>/dev/null || return 0
  CRASH_DIALOG_CHANGED=1
}

restore_crash_dialogs() {
  [[ "$CRASH_DIALOG_CHANGED" -eq 1 ]] || return 0
  if [[ -n "$CRASH_DIALOG_PREV" ]]; then
    defaults write com.apple.CrashReporter DialogType "$CRASH_DIALOG_PREV" 2>/dev/null || true
  else
    # Was unset before, so delete rather than write a value macOS never had.
    defaults delete com.apple.CrashReporter DialogType 2>/dev/null || true
  fi
}

suppress_crash_dialogs

echo "$$" > "$PIDFILE"
trap 'rm -f "$PIDFILE" "$STATE_CACHE"; restore_crash_dialogs' EXIT

echo "Watching $BUNDLE_ID on $(target_label). Ctrl-C to stop (or --stop)."
if [[ "$TARGET_KIND" == "device" ]]; then
  echo "NOTE: background-half crashes are fired by launching Settings to take the"
  echo "      foreground, so expect the phone to flip to Settings periodically."
fi

# The app records how long to wait before relaunching. OOM crashes take tens of
# seconds to actually kill the process, and relaunching early leaves the previous
# attempt's leaked allocation thread accumulating alongside the new one.
# Capped: only the OOM variants legitimately need tens of seconds, and a value
# left over from an OOM run would otherwise stall a fast-crash loop for 45s a
# time. MAX_RESTART_DELAY raises the ceiling when actually demoing OOMs.
MAX_RESTART_DELAY="${MAX_RESTART_DELAY:-5}"

restart_delay_seconds() {
  local ms secs; ms="$(state_value restart_delay_ms 2000)"
  if [[ "$ms" =~ ^[0-9]+$ ]] && [[ "$ms" -gt 0 ]]; then
    secs=$(( (ms + 999) / 1000 ))
  else
    secs=2
  fi
  [[ "$secs" -gt "$MAX_RESTART_DELAY" ]] && secs="$MAX_RESTART_DELAY"
  echo "$secs"
}

relaunches=0
backgrounded=0
hangs=0

while true; do
  pid="$(app_pid)"
  refresh_state || true

  if [[ -n "$pid" ]] && [[ "$(state_value awaiting_background false)" == "true" ]]; then
    background_app
    echo "$(date '+%H:%M:%S')  background crash armed — sent app to the background"
    backgrounded=$((backgrounded + 1))
    sleep 5
    continue
  fi

  # A watchdog hang cannot fire on its own: the app can't launch, resume or
  # terminate itself, so drive whichever transition it is waiting on.
  if [[ -n "$pid" ]]; then
    if driven="$(drive_pending_watchdog)"; then
      echo "$(date '+%H:%M:%S')  watchdog hang armed ($driven) — drove the transition"
      hangs=$((hangs + 1))
      # Blocks the main thread for its whole budget before the OS steps in.
      sleep 15
      continue
    fi
  fi

  if [[ -z "$pid" ]]; then
    delay="$(restart_delay_seconds)"
    echo "$(date '+%H:%M:%S')  app not running — relaunching in ${delay}s (relaunch #$((relaunches + 1)), bg ${backgrounded}x, hangs ${hangs}x)"
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
