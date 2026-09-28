#!/usr/bin/env bash
# Stop the app without stopping the simulator itself.
set -euo pipefail

BUNDLE_ID="ai.bitdrift.oteldemo.ios"

TARGET_ID="$(xcrun simctl list devices booted | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' | head -n1 || true)"
if [[ -z "$TARGET_ID" ]]; then
  echo "No simulator booted."
  exit 1
fi

xcrun simctl terminate "$TARGET_ID" "$BUNDLE_ID"
echo "Stopped $BUNDLE_ID on $TARGET_ID"
