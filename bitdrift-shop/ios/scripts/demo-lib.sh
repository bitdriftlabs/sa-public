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
  xcrun devicectl list devices 2>/dev/null \
    | awk '/connected/ { for (i=1;i<=NF;i++) if ($i ~ /^[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}$/) { print $i; exit } }'
}

# resolve_target <kind|auto> <id|"">
# kind: sim | device | auto
resolve_target() {
  local kind="${1:-auto}" id="${2:-}"

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
      # Prefer a booted simulator (the common case), fall back to a device.
      local sim; sim="$(booted_simulator)"
      if [[ -n "$sim" ]]; then
        TARGET_KIND="sim"; TARGET_ID="$sim"
      else
        TARGET_KIND="device"; TARGET_ID="$(connected_device)"
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
# Simulator only: launching SpringBoard backgrounds the foreground app. There is
# no devicectl equivalent, so on a device the background half needs a human
# pressing Home (see watchdog.sh's warning).
background_app() {
  case "$TARGET_KIND" in
    sim) xcrun simctl launch "$TARGET_ID" com.apple.springboard >/dev/null 2>&1 || true; return 0 ;;
    device) return 1 ;;
  esac
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
