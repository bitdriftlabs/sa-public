#!/usr/bin/env bash
# Stop the app without stopping the simulator itself.
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=demo-lib.sh
source "scripts/demo-lib.sh"

if ! resolve_target sim ""; then
  echo "No simulator booted." >&2
  exit 1
fi

terminate_app
echo "Stopped $BUNDLE_ID on $TARGET_ID"
