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

# Must match BITDRIFT_SHOP_BUNDLE_ID in .local.xcconfig. These scripts cannot read
# xcconfig, so if you override the bundle identifier there, export it here too or
# every script will look for an app that is not installed:
#
#   export BUNDLE_ID=com.example.bitdriftshop
BUNDLE_ID="${BUNDLE_ID:-ai.bitdrift.shop.ios}"

# shellcheck source=../../scripts/lib/driver-simctl.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/lib/driver-simctl.sh"
# Persisted fault store names come from spec/faults.yaml (generated).
# shellcheck source=../../scripts/lib/generated/faults.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/lib/generated/faults.sh"

# Cache for the pulled state file — copying off a device takes seconds, so a
# poll cycle refreshes once and then reads as many keys as it likes.
STATE_CACHE="${TMPDIR:-/tmp}/bitdrift-shop-state-$$.json"
trap 'rm -f "$STATE_CACHE"' EXIT

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

# Turns every fault flag (and Rec v2, so a device reset actually matches what
# check-demo-state.sh reports afterward) off by relaunching the app with them
# all set to 0.
#
# Works on a device, where the plist cannot be deleted: launch arguments land in
# NSArgumentDomain, and the app promotes whatever it resolves at startup into its
# persistent store — so one disarmed launch sticks. Note the `--` before the app's
# own arguments, without which devicectl claims them as its own flags.
DISARM_ARGS=(
  -${FAULT_STORE_CRASH_LOOP_IOS}.pending_watchdog ""
  -${FAULT_STORE_CRASH_LOOP_IOS}.active 0
  -${FAULT_STORE_CRASH_LOOP_IOS}.fast_mode 0
  -${FAULT_STORE_CRASH_LOOP_IOS}.oom_only 0
  -${FAULT_STORE_CRASH_LOOP_IOS}.resume_infinite_with_crash 0
  -${FAULT_STORE_CRASH_LOOP_IOS}.awaiting_background 0
  -${FAULT_STORE_ANR_IOS}.active 0
  -${FAULT_STORE_ANR_IOS}.restart_pending 0
  -${FAULT_STORE_ANR_IOS}.resume_infinite 0
  -${FAULT_STORE_FORCE_QUIT_IOS}.active 0
  -${FAULT_STORE_FORCE_QUIT_IOS}.restart_pending 0
  -${FAULT_STORE_FORCE_QUIT_IOS}.resume_infinite 0
  -${FAULT_STORE_AUTO_INFINITE_IOS}.active 0
  -${FAULT_STORE_SLOW_MODE_IOS}.active 0
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

