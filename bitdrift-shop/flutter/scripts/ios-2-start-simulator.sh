#!/usr/bin/env bash
# Boot an iOS Simulator and open its window (Simulator.app, or Xcode's
# device UI on newer Xcode versions that no longer ship a standalone app).
# Override the device with DEVICE_NAME=<name>; list options with:
#   xcrun simctl list devices available
set -euo pipefail

DEVICE_NAME="${DEVICE_NAME:-iPhone 17 Pro}"

# Already booted?
BOOTED_ID="$(xcrun simctl list devices booted | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' | head -n1 || true)"
if [[ -n "$BOOTED_ID" ]]; then
  echo "A simulator is already booted: $BOOTED_ID"
else
  UDID="$(xcrun simctl list devices available \
    | grep -F "$DEVICE_NAME (" \
    | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' \
    | head -n1 || true)"
  if [[ -z "$UDID" ]]; then
    echo "No available simulator named '$DEVICE_NAME'." >&2
    echo "List options with: xcrun simctl list devices available" >&2
    exit 1
  fi
  echo "Booting '$DEVICE_NAME' ($UDID) ..."
  xcrun simctl boot "$UDID"
fi


# Xcode 27 renamed/replaced Simulator.app with DeviceHub.app (com.apple.dt.Devices) --
# try both, oldest-name-first. Opening Xcode itself (rather than either of these) does
# NOT open the simulator/device window, so it's not a usable fallback here -- only note
# the lack of a GUI if neither exists (e.g. a CLI-only Xcode install); the booted device
# is still usable via simctl either way.
open -a Simulator 2>/dev/null || open -a DeviceHub 2>/dev/null \
  || echo "(No Simulator/DeviceHub GUI available on this machine — the device is still booted and usable via simctl.)" >&2

echo "Simulator is up:"
xcrun simctl list devices booted
