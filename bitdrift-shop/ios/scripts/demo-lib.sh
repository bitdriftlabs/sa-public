#!/usr/bin/env bash
# Shared helpers for watchdog.sh and check-demo-state.sh.
#
# The app publishes its fault-injection state to a JSON file in its container
# (see BitdriftShop/DemoStateFile.swift). We read that rather than the app's
# UserDefaults plist: on the Simulator that plist is owned by cfprefsd, which
# caches the domain in memory, so a host-side read can return values the app
# abandoned minutes ago and a host-side write is silently overwritten on the
# daemon's next flush.

BUNDLE_ID="ai.bitdrift.shop.ios"

resolve_device() {
  local requested="${1:-}"
  if [[ -n "$requested" ]]; then
    echo "$requested"
    return 0
  fi
  xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1
}

app_container() {
  xcrun simctl get_app_container "$1" "$BUNDLE_ID" data 2>/dev/null || true
}

state_file() {
  local container
  container="$(app_container "$1")"
  [[ -n "$container" ]] && echo "$container/Library/Application Support/bitdrift-demo-state.json"
}

# state_value <device> <key> [default]
state_value() {
  local file value
  file="$(state_file "$1")"
  if [[ -z "$file" || ! -f "$file" ]]; then
    echo "${3:-}"
    return 0
  fi
  # plutil reads JSON directly; no jq dependency.
  value="$(plutil -extract "$2" raw -o - "$file" 2>/dev/null || true)"
  [[ -z "$value" ]] && value="${3:-}"
  echo "$value"
}

app_pid() {
  xcrun simctl spawn "$1" launchctl list 2>/dev/null \
    | awk -v id="$BUNDLE_ID" '$3 ~ id && $1 ~ /^[0-9]+$/ { print $1; exit }'
}

# Bounces the Simulator's preferences daemon so it drops its cached copy of the
# app's domain and re-reads from disk. Needed after deleting the plist from the
# host, otherwise the daemon just writes its stale values back.
restart_prefs_daemon() {
  xcrun simctl spawn "$1" launchctl kill SIGTERM system/com.apple.cfprefsd.xpc.daemon >/dev/null 2>&1 \
    || xcrun simctl spawn "$1" launchctl stop com.apple.cfprefsd.xpc.daemon >/dev/null 2>&1 \
    || true
}
