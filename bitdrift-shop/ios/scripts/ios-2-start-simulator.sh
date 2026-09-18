#!/usr/bin/env bash
# Boot an iOS Simulator and open the Simulator.app window.
# Override the device with DEVICE_NAME=<name>; list options with:
#   xcrun simctl list devices available
#
# Mirrors ../../flutter/scripts/ios-2-start-simulator.sh. Prefers "iPhone 16"
# (this app's own README example) but falls back to whatever iPhone simulator
# is actually installed — the exact model set varies a lot by Xcode version
# and which platforms were downloaded, so a hardcoded name alone is fragile.
set -euo pipefail

DEVICE_NAME="${DEVICE_NAME:-iPhone 16}"

find_udid() {
  # $1: a literal device name to match, e.g. "iPhone 16"
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

open -a Simulator

echo "Simulator is up:"
xcrun simctl list devices booted
