#!/usr/bin/env bash
# Shut down the booted simulator(s) started by scripts/ios-3-start-simulator.sh.
set -euo pipefail

BOOTED_IDS="$(xcrun simctl list devices booted | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' || true)"

if [[ -z "$BOOTED_IDS" ]]; then
  echo "No simulator is running."
  exit 0
fi

for id in $BOOTED_IDS; do
  echo "Shutting down $id ..."
  xcrun simctl shutdown "$id"
done

echo "Stopped."
