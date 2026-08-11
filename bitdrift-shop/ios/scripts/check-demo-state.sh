#!/usr/bin/env bash
# Reports which fault-injection flags are currently armed, and optionally clears
# them.
#
# These flags persist across launches by design — each mode has to survive its
# own crash/relaunch cycle — which means leaving one on and later starting an
# unrelated demo leaves it silently armed. Run this before any demo session.
#
#   ./scripts/check-demo-state.sh
#   ./scripts/check-demo-state.sh --reset
#   ./scripts/check-demo-state.sh --device UDID
set -euo pipefail

# shellcheck source=demo-lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/demo-lib.sh"

DEVICE=""
RESET=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) DEVICE="${2:-}"; shift 2 ;;
    --reset) RESET=1; shift ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

DEVICE="$(resolve_device "$DEVICE")"
if [[ -z "$DEVICE" ]]; then
  echo "No booted simulator found. Boot one first, or pass --device UDID." >&2
  exit 1
fi

CONTAINER="$(app_container "$DEVICE")"
if [[ -z "$CONTAINER" ]]; then
  echo "$BUNDLE_ID is not installed on $DEVICE." >&2
  exit 1
fi

if [[ "$RESET" -eq 1 ]]; then
  # Order matters. The app has to be dead first, or cfprefsd writes its cached
  # copy straight back over the deleted plist; bouncing the daemon afterwards
  # makes it re-read (now-absent) state from disk.
  xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
  sleep 1
  rm -f "$CONTAINER/Library/Preferences/$BUNDLE_ID.plist"
  rm -f "$CONTAINER/Library/Application Support/bitdrift-demo-state.json"
  restart_prefs_daemon "$DEVICE"
  sleep 1
  echo "All demo flags cleared on $DEVICE (app terminated)."
  echo
fi

FLAGS=(
  "crash_loop|Crash loop"
  "fast_crash|Fast crash mode"
  "oom_only|OOM crashes only"
  "resume_infinite_with_crash|Resume infinite after crash"
  "app_hang|Hang-A (main-thread hang)"
  "app_hang_restart_pending|Hang restart pending"
  "force_quit|Force quit"
  "force_quit_restart_pending|Force-quit restart pending"
  "auto_infinite|Auto infinite sim on launch"
  "awaiting_background|Background crash armed"
)

STATE_FILE="$(state_file "$DEVICE")"
if [[ ! -f "$STATE_FILE" ]]; then
  echo "No demo state published yet on $DEVICE."
  echo "Launch the app once — it writes its state on startup — then re-run this."
  exit 0
fi

echo "Demo state for $BUNDLE_ID on $DEVICE:"
armed=0
for entry in "${FLAGS[@]}"; do
  key="${entry%%|*}"
  label="${entry##*|}"
  if [[ "$(state_value "$DEVICE" "$key" false)" == "true" ]]; then
    state="ON"
    armed=$((armed + 1))
  else
    state="off"
  fi
  printf '  %-34s %s\n' "$label" "$state"
done

printf '  %-34s %s\n' "Next crash combo index" "$(state_value "$DEVICE" next_combo_index 0)"

echo
if [[ "$armed" -gt 0 ]]; then
  echo "$armed flag(s) armed. Run with --reset to clear them before an unrelated demo."
else
  echo "Clean — no fault injection armed."
fi
