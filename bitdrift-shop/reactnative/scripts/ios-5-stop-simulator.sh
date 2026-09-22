#!/usr/bin/env bash
# Shut down any booted iOS Simulator(s).
set -euo pipefail

BOOTED="$(xcrun simctl list devices booted | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' || true)"

if [[ -z "$BOOTED" ]]; then
  echo "No simulator is running."
  exit 0
fi

for id in $BOOTED; do
  echo "Shutting down $id ..."
  xcrun simctl shutdown "$id"
done

echo "Stopped."
