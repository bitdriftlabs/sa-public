#!/usr/bin/env bash
# Shared helpers for watchdog.sh and check-demo-state.sh.
#
# Targets either a booted Simulator (via simctl) or a connected physical device
# (via devicectl) behind one set of functions, so the callers don't branch.
#
# The app publishes its fault-injection state to a JSON file in its container
# (see BitdriftShop/DemoStateFile.swift). We read that rather than the app's
# UserDefaults plist: on the Simulator that plist is owned by cfprefsd, which
# caches the domain in memory, so a host-side read can return values the app
# abandoned minutes ago. On a device the plist isn't reachable at all.

BUNDLE_ID="ai.bitdrift.shop.ios"

# Set by resolve_target: "sim" or "device", plus the identifier.
TARGET_KIND=""
TARGET_ID=""

# Cache for the pulled state file — copying off a device takes seconds, so a
# poll cycle refreshes once and then reads as many keys as it likes.
STATE_CACHE="${TMPDIR:-/tmp}/bitdrift-shop-state-$$.json"
trap 'rm -f "$STATE_CACHE"' EXIT

booted_simulator() {
  xcrun simctl list devices booted 2>/dev/null | grep -oE '[0-9A-F-]{36}' | head -1
}

connected_device() {
  # The State column wording varies — "connected" when actively attached,
  # "available (paired)" when known but idle — so match either rather than the
  # literal "connected", and skip the header and separator rows.
  xcrun devicectl list devices 2>/dev/null \
    | awk '$0 !~ /^(Name|-+[[:space:]])/ && /connected|available/ {
             for (i=1;i<=NF;i++)
               if ($i ~ /^[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}$/) { print $i; exit }
           }'
}

# resolve_target <kind|auto> <id|"">
# kind: sim | device | auto
resolve_target() {
  local kind="${1:-auto}" id="${2:-}"
  # "ambiguous" when both targets are live, "none" when neither is. Callers use
  # this to avoid printing a "boot a simulator" hint at someone who has two.
  RESOLVE_ERROR="none"

  case "$kind" in
    sim)
      TARGET_KIND="sim"
      TARGET_ID="${id:-$(booted_simulator)}"
      ;;
    device)
      TARGET_KIND="device"
      TARGET_ID="${id:-$(connected_device)}"
      ;;
    auto)
      # Refuse to guess when both are live. Silently preferring one meant a bare
      # `watchdog.sh` could sit watching an idle Simulator while the phone you were
      # actually testing waited, armed, forever.
      local sim dev; sim="$(booted_simulator)"; dev="$(connected_device)"
      if [[ -n "$sim" && -n "$dev" ]]; then
        RESOLVE_ERROR="ambiguous"
        echo "Both a booted simulator and a connected device are available:" >&2
        echo "  --simulator $sim" >&2
        echo "  --device    $dev" >&2
        echo "Pass one explicitly." >&2
        return 1
      elif [[ -n "$sim" ]]; then
        TARGET_KIND="sim"; TARGET_ID="$sim"
      else
        TARGET_KIND="device"; TARGET_ID="$dev"
      fi
      ;;
  esac

  [[ -n "$TARGET_ID" ]]
}

target_label() {
  echo "$TARGET_KIND $TARGET_ID"
}

app_installed() {
  case "$TARGET_KIND" in
    sim) [[ -n "$(xcrun simctl get_app_container "$TARGET_ID" "$BUNDLE_ID" data 2>/dev/null)" ]] ;;
    device)
      xcrun devicectl device info apps --device "$TARGET_ID" 2>/dev/null | grep -q "$BUNDLE_ID"
      ;;
  esac
}

app_pid() {
  case "$TARGET_KIND" in
    sim)
      xcrun simctl spawn "$TARGET_ID" launchctl list 2>/dev/null \
        | awk -v id="$BUNDLE_ID" '$3 ~ id && $1 ~ /^[0-9]+$/ { print $1; exit }'
      ;;
    device)
      # devicectl pads its table columns, so the executable path is followed by
      # trailing spaces — anchoring with a bare `$` never matches.
      xcrun devicectl device info processes --device "$TARGET_ID" 2>/dev/null \
        | awk '/BitdriftShop\.app\/BitdriftShop[[:space:]]*$/ && $1 ~ /^[0-9]+$/ { print $1; exit }'
      ;;
  esac
}

launch_app() {
  case "$TARGET_KIND" in
    sim) xcrun simctl launch "$TARGET_ID" "$BUNDLE_ID" >/dev/null 2>&1 ;;
    device) xcrun devicectl device process launch --device "$TARGET_ID" "$BUNDLE_ID" >/dev/null 2>&1 ;;
  esac
}

terminate_app() {
  case "$TARGET_KIND" in
    sim) xcrun simctl terminate "$TARGET_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true ;;
    device)
      local pid; pid="$(app_pid)"
      [[ -n "$pid" ]] && xcrun devicectl device process terminate \
        --device "$TARGET_ID" --pid "$pid" >/dev/null 2>&1 || true
      ;;
  esac
}

# Pulls the app's published state into STATE_CACHE. Returns non-zero if there is
# nothing to read yet (app has never launched).
refresh_state() {
  case "$TARGET_KIND" in
    sim)
      local container
      container="$(xcrun simctl get_app_container "$TARGET_ID" "$BUNDLE_ID" data 2>/dev/null)"
      local src="$container/Library/Application Support/bitdrift-demo-state.json"
      [[ -f "$src" ]] || return 1
      cp -f "$src" "$STATE_CACHE" 2>/dev/null || return 1
      ;;
    device)
      rm -f "$STATE_CACHE"
      xcrun devicectl device copy from --device "$TARGET_ID" \
        --domain-type appDataContainer --domain-identifier "$BUNDLE_ID" --user mobile \
        --source "Library/Application Support/bitdrift-demo-state.json" \
        --destination "$STATE_CACHE" >/dev/null 2>&1 || return 1
      [[ -s "$STATE_CACHE" ]] || return 1
      ;;
  esac
}

# state_value <key> [default] — reads from the last refresh_state.
state_value() {
  local v
  [[ -s "$STATE_CACHE" ]] || { echo "${2:-}"; return 0; }
  v="$(plutil -extract "$1" raw -o - "$STATE_CACHE" 2>/dev/null || true)"
  [[ -z "$v" ]] && v="${2:-}"
  echo "$v"
}

# Sends the app to the background so a background-half crash can fire.
#
# Neither platform lets the app background itself, so this is done from outside
# by giving something else the foreground:
#   - Simulator: launching SpringBoard returns to the home screen.
#   - Device: there is no SpringBoard equivalent over devicectl, but launching
#     any other app has the same effect. Settings is used because it is present
#     on every device, harmless to open, and cheap to launch.
background_app() {
  case "$TARGET_KIND" in
    sim) xcrun simctl launch "$TARGET_ID" com.apple.springboard >/dev/null 2>&1 || true ;;
    device) xcrun devicectl device process launch --device "$TARGET_ID" com.apple.Preferences >/dev/null 2>&1 || true ;;
  esac
  return 0
}

# Turns every fault flag off by relaunching the app with them all set to 0.
#
# Works on a device, where the plist cannot be deleted: launch arguments land in
# NSArgumentDomain, and the app promotes whatever it resolves at startup into its
# persistent store — so one disarmed launch sticks. Note the `--` before the app's
# own arguments, without which devicectl claims them as its own flags.
DISARM_ARGS=(
  -crash_loop.pending_watchdog ""
  -crash_loop.active 0
  -crash_loop.fast_mode 0
  -crash_loop.oom_only 0
  -crash_loop.resume_infinite_with_crash 0
  -crash_loop.awaiting_background 0
  -app_hang.active 0
  -app_hang.restart_pending 0
  -force_quit.active 0
  -force_quit.restart_pending 0
  -auto_infinite.active 0
)

disarm_flags() {
  terminate_app
  sleep 2
  case "$TARGET_KIND" in
    sim) xcrun simctl launch "$TARGET_ID" "$BUNDLE_ID" "${DISARM_ARGS[@]}" >/dev/null 2>&1 ;;
    device) xcrun devicectl device process launch --device "$TARGET_ID" "$BUNDLE_ID" \
              -- "${DISARM_ARGS[@]}" >/dev/null 2>&1 ;;
  esac
  # Give the app time to start, resolve, persist and republish its state.
  sleep 8
}

# Sends SIGTERM — a *graceful* termination request, which is what makes the
# 0x8BADF00D "Failed to terminate gracefully after 5.0s" watchdog fire when the
# app blocks its main thread instead of exiting. SIGKILL would just kill it with
# no report at all, so the default (SIGTERM) is exactly what is wanted here.
request_graceful_terminate() {
  local pid; pid="$(app_pid)"
  [[ -z "$pid" ]] && return 1
  case "$TARGET_KIND" in
    sim) xcrun simctl spawn "$TARGET_ID" kill -TERM "$pid" >/dev/null 2>&1 ;;
    device) xcrun devicectl device process terminate --device "$TARGET_ID" --pid "$pid" >/dev/null 2>&1 ;;
  esac
}

# Drives the lifecycle transition an armed watchdog hang is waiting on. Returns
# non-zero when there is nothing armed.
#
#   scene_create  relaunch, so the hang lands in the launch window
#   scene_update  background then foreground, so it lands on resume
#   process_exit  graceful SIGTERM, so it lands in the 5s exit budget
drive_pending_watchdog() {
  local kind; kind="$(state_value pending_watchdog "")"
  [[ -z "$kind" || "$kind" == "null" ]] && return 1
  case "$kind" in
    scene_create)
      terminate_app; sleep 1; launch_app ;;
    scene_update)
      background_app; sleep 3; launch_app ;;
    process_exit)
      request_graceful_terminate ;;
    *) return 1 ;;
  esac
  echo "$kind"
}

# Bounces the Simulator's preferences daemon so it drops its cached copy of the
# app's domain and re-reads from disk. Needed after deleting the plist from the
# host, otherwise the daemon just writes its stale values back.
restart_prefs_daemon() {
  [[ "$TARGET_KIND" == "sim" ]] || return 0
  xcrun simctl spawn "$TARGET_ID" launchctl kill SIGTERM system/com.apple.cfprefsd.xpc.daemon >/dev/null 2>&1 \
    || xcrun simctl spawn "$TARGET_ID" launchctl stop com.apple.cfprefsd.xpc.daemon >/dev/null 2>&1 \
    || true
}

# Parses the shared --simulator/--device flags out of "$@".
# Sets PARSED_KIND, PARSED_ID, and PARSED_REST (remaining args).
#
# Must be called directly, never via $(...) — command substitution would run it
# in a subshell and none of these assignments would reach the caller.
parse_target_flags() {
  PARSED_KIND="auto"; PARSED_ID=""; PARSED_REST=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --simulator)
        PARSED_KIND="sim"
        if [[ -n "${2:-}" && "${2:-}" != -* ]]; then PARSED_ID="$2"; shift; fi
        shift ;;
      --device)
        PARSED_KIND="device"
        if [[ -n "${2:-}" && "${2:-}" != -* ]]; then PARSED_ID="$2"; shift; fi
        shift ;;
      *) PARSED_REST+=("$1"); shift ;;
    esac
  done
}
