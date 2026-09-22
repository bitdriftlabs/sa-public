#!/usr/bin/env bash
# Boot an iOS Simulator and open its GUI window (Simulator.app, or DeviceHub.app
# on Xcode 27+, which renamed/replaced it).
# Override the device with DEVICE_NAME=<name>; list options with:
#   xcrun simctl list devices available
#
# Mirrors ../../ios/scripts/ios-2-start-simulator.sh. Defaults to "iPhone 16e"
# — the model package.json's own `npm run ios` hardcodes via
# `--simulator 'iPhone 16e'` — but falls back to whatever iPhone simulator is
# actually installed if that model isn't available on this machine (it
# wasn't, as of this writing: Xcode had aged it out in favor of newer
# models). ios-3-start-app.sh always targets whichever simulator actually
# ends up booted by UDID, so a fallback here doesn't create a mismatch there.
set -euo pipefail

DEVICE_NAME="${DEVICE_NAME:-iPhone 16e}"

find_udid() {
  # $1: a literal device name to match, e.g. "iPhone 16e"
  xcrun simctl list devices available \
    | grep -F "$1 (" \
    | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' \
    | head -n1 || true
}

# Already booted?
BOOTED_ID="$(xcrun simctl list devices booted | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' | head -n1 || true)"
if [[ -n "$BOOTED_ID" ]]; then
  echo "A simulator is already booted: $BOOTED_ID"
else
  UDID="$(find_udid "$DEVICE_NAME")"
  PICKED_NAME="$DEVICE_NAME"

  if [[ -z "$UDID" ]]; then
    # Fall back to any available iPhone simulator, since the requested model
    # may not exist on this machine's installed platforms/Xcode version.
    FALLBACK_LINE="$(xcrun simctl list devices available | grep -F "iPhone " | head -n1 || true)"
    if [[ -n "$FALLBACK_LINE" ]]; then
      PICKED_NAME="$(sed -E 's/^[[:space:]]*(.*) \([0-9A-F-]+\).*/\1/' <<<"$FALLBACK_LINE")"
      UDID="$(grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' <<<"$FALLBACK_LINE")"
      echo "No available simulator named '$DEVICE_NAME' — falling back to '$PICKED_NAME'."
    fi
  fi

  if [[ -z "$UDID" ]]; then
    echo "No iPhone simulator is available at all." >&2
    echo "List options with: xcrun simctl list devices available" >&2
    echo "Install a platform with: xcodebuild -downloadPlatform iOS" >&2
    exit 1
  fi

  echo "Booting '$PICKED_NAME' ($UDID) ..."
  xcrun simctl boot "$UDID"
fi

# Xcode 27 renamed/replaced Simulator.app with DeviceHub.app (com.apple.dt.Devices) --
# try both, oldest-name-first, and only note the lack of a GUI if neither exists
# (e.g. a CLI-only Xcode install) -- the booted device is still usable either way.
open -a Simulator 2>/dev/null || open -a DeviceHub 2>/dev/null \
  || echo "(No Simulator/DeviceHub GUI available on this machine — the device is still booted and usable via simctl/xcodebuild.)"

echo "Simulator is up:"
xcrun simctl list devices booted
