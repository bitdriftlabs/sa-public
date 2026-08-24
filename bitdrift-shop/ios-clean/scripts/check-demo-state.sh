#!/usr/bin/env bash
# Reports which fault-injection flags are currently armed, and optionally clears
# them. Works against a booted Simulator or a connected device.
#
# These flags persist across launches by design — each mode has to survive its
# own crash/relaunch cycle — which means leaving one on and later starting an
# unrelated demo leaves it silently armed. Run this before any demo session.
#
#   ./scripts/check-demo-state.sh
#   ./scripts/check-demo-state.sh --reset          # simulator only
#   ./scripts/check-demo-state.sh --device [UDID]
#   ./scripts/check-demo-state.sh --simulator [UDID]
set -uo pipefail

# shellcheck source=demo-lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/demo-lib.sh"

RESET=0
parse_target_flags "$@"
for arg in ${PARSED_REST[@]+"${PARSED_REST[@]}"}; do
  case "$arg" in
    --reset) RESET=1 ;;
    -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

if ! resolve_target "$PARSED_KIND" "$PARSED_ID"; then
  # resolve_target already explained itself when the choice was ambiguous.
  if [[ "${RESOLVE_ERROR:-none}" == "none" ]]; then
    echo "No target found. Boot a simulator, or connect a device and pass --device." >&2
  fi
  exit 1
fi

if ! app_installed; then
  echo "$BUNDLE_ID is not installed on $(target_label)." >&2
  exit 1
fi

if [[ "$RESET" -eq 1 ]]; then
  echo "Disarming all fault flags on $(target_label)…"
  if [[ "$TARGET_KIND" == "sim" ]]; then
    container="$(xcrun simctl get_app_container "$TARGET_ID" "$BUNDLE_ID" data 2>/dev/null)"
    # Order matters. The app has to be dead first, or cfprefsd writes its cached
    # copy straight back over the deleted plist; bouncing the daemon afterwards
    # makes it re-read (now-absent) state from disk.
    terminate_app
    sleep 1
    rm -f "$container/Library/Preferences/$BUNDLE_ID.plist"
    rm -f "$container/Library/Application Support/bitdrift-demo-state.json"
    restart_prefs_daemon
    sleep 1
  else
    # A device's plist can't be deleted, so disarm by relaunching with every flag
    # explicitly off — the app persists whatever it resolves at startup.
    disarm_flags
  fi
  echo "Done."
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
  "recommendations_v2|Rec v2 (heavier scoring pass)"
)

if ! refresh_state; then
  echo "No demo state published yet on $(target_label)."
  echo "Launch the app once — it writes its state on startup — then re-run this."
  exit 0
fi

echo "Demo state for $BUNDLE_ID on $(target_label):"
armed=0
for entry in "${FLAGS[@]}"; do
  key="${entry%%|*}"; label="${entry##*|}"
  if [[ "$(state_value "$key" false)" == "true" ]]; then
    state="ON"; armed=$((armed + 1))
  else
    state="off"
  fi
  printf '  %-34s %s\n' "$label" "$state"
done
printf '  %-34s %s\n' "Next crash combo index" "$(state_value next_combo_index 0)"

echo
if [[ "$armed" -gt 0 ]]; then
  echo "$armed flag(s) armed."
  [[ "$TARGET_KIND" == "sim" ]] && echo "Run with --reset to clear them before an unrelated demo."
else
  echo "Clean — no fault injection armed."
fi
