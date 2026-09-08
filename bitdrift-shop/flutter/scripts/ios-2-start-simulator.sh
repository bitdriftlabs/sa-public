#!/usr/bin/env bash
# Boot an iOS Simulator and open the Simulator.app window.
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

open -a Simulator

echo "Simulator is up:"
xcrun simctl list devices booted
