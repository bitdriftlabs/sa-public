#!/usr/bin/env bash
# Stop the app without stopping the simulator itself.
set -euo pipefail

BUNDLE_ID="io.bitdrift.bitdriftShopFlutter"

SIM_ID="$(xcrun simctl list devices booted | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' | head -n1 || true)"
if [[ -z "$SIM_ID" ]]; then
  echo "No simulator booted."
  exit 1
fi

xcrun simctl terminate "$SIM_ID" "$BUNDLE_ID"
echo "Stopped $BUNDLE_ID on $SIM_ID"
