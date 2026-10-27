#!/usr/bin/env bash
# Start or stop the iOS Simulator, for every demo app (native, React Native, Flutter).
# The one place for this logic; the per-app copies were removed.
#
#   scripts/device/ios-simulator.sh start   # boot a simulator and open its window
#   scripts/device/ios-simulator.sh stop    # shut down every booted simulator
#
# Environment:
#   DEVICE_NAME      device to boot (default "iPhone 17 Pro"); falls back to any eligible iPhone, since
#                    the model set varies a lot with the Xcode version and downloaded platforms.
#                    List options with: xcrun simctl list devices available
#   MIN_IOS_VERSION  every candidate (already-booted, named, fallback) must run at least this iOS
#                    (default 26.0, the React Native app's deployment target). A simulator on an older
#                    runtime can boot here and then fail at build or install time, a much more confusing
#                    place to discover the mismatch.
#
# The start-app scripts target whichever simulator is booted by UDID, so a fallback here never creates a
# mismatch there.
set -euo pipefail

DEVICE_NAME="${DEVICE_NAME:-iPhone 17 Pro}"
MIN_IOS_VERSION="${MIN_IOS_VERSION:-26.0}"
UDID_RE='[0-9A-Fa-f]{8}-([0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}'

# Prints "UDID Name" for every simulator (from `simctl list devices <$1>`, e.g. "available" or "booted")
# whose runtime is >= MIN_IOS_VERSION. Runtime versions are only known from the "-- iOS X.Y --" section
# header each device is listed under, so this tracks which section it is in.
list_eligible() {
  xcrun simctl list devices "$1" 2>/dev/null | awk -v min="$MIN_IOS_VERSION" '
    /^-- iOS [0-9.]+ --/ {
      split($3, v, "."); split(min, m, ".")
      ok = (v[1]+0 > m[1]+0) || (v[1]+0 == m[1]+0 && v[2]+0 >= m[2]+0)
      next
    }
    ok && match($0, /[0-9A-Fa-f]{8}-([0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}/) {
      udid = substr($0, RSTART, RLENGTH)
      name = $0
      sub(/^[[:space:]]*/, "", name)
      sub(/ \(.*/, "", name)
      print udid, name
    }
  '
}

start() {
  local booted_line any_booted udid="" picked="$DEVICE_NAME" fallback
  booted_line="$(list_eligible booted | head -n1 || true)"
  if [[ -n "$booted_line" ]]; then
    echo "A simulator is already booted: ${booted_line%% *}"
  else
    # Every consumer (the start-app scripts, test.sh) takes the first booted simulator, so a second, eligible
    # one booted next to an ineligible one would still lose to it. Refuse instead of leaving two.
    any_booted="$(xcrun simctl list devices booted | grep -oE "$UDID_RE" | head -n1 || true)"
    if [[ -n "$any_booted" ]]; then
      echo "A simulator is booted ($any_booted) but its runtime is below iOS $MIN_IOS_VERSION." >&2
      echo "Stop it first (scripts/device/ios-simulator.sh stop), or lower MIN_IOS_VERSION." >&2
      exit 1
    fi

    udid="$(list_eligible available | awk -v name="$DEVICE_NAME" '{ln=$0; sub(/^[0-9A-Fa-f-]+ /, "", ln); if (ln == name) { print $1; exit } }')"
    if [[ -z "$udid" ]]; then
      fallback="$(list_eligible available | grep " iPhone " | head -n1 || true)"
      if [[ -n "$fallback" ]]; then
        udid="${fallback%% *}"
        picked="${fallback#* }"
        echo "No eligible simulator named '$DEVICE_NAME' (iOS >= $MIN_IOS_VERSION); falling back to '$picked'."
      fi
    fi
    if [[ -z "$udid" ]]; then
      echo "No iPhone simulator running iOS $MIN_IOS_VERSION or newer is available." >&2
      echo "List options with: xcrun simctl list devices available" >&2
      echo "Install a platform with: xcodebuild -downloadPlatform iOS" >&2
      exit 1
    fi
    echo "Booting '$picked' ($udid) ..."
    xcrun simctl boot "$udid"
  fi

  # Xcode 27 renamed/replaced Simulator.app with DeviceHub.app: try both, oldest name first. Opening Xcode
  # itself does NOT open the simulator window, so it is no fallback. A CLI-only Xcode has neither; the
  # booted device is still usable via simctl/xcodebuild.
  open -a Simulator 2>/dev/null || open -a DeviceHub 2>/dev/null \
    || echo "(No Simulator/DeviceHub GUI available on this machine; the device is still booted and usable via simctl/xcodebuild.)"

  echo "Simulator is up:"
  xcrun simctl list devices booted
}

stop() {
  local ids id
  ids="$(xcrun simctl list devices booted | grep -oE "$UDID_RE" || true)"
  if [[ -z "$ids" ]]; then
    echo "No simulator is running."
    return 0
  fi
  for id in $ids; do
    echo "Shutting down $id ..."
    xcrun simctl shutdown "$id"
  done
  echo "Stopped."
}

case "${1:-}" in
  start) start ;;
  stop) stop ;;
  *) echo "usage: ${0##*/} start|stop" >&2; exit 2 ;;
esac
