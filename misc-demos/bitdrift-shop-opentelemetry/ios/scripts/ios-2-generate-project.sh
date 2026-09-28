#!/usr/bin/env bash
# Regenerates BitdriftShopOtel.xcodeproj from project.yml via xcodegen (brew install xcodegen).
# Run this after editing project.yml, or after a fresh checkout, before opening the project.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$(dirname "$SCRIPT_DIR")"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not found -- install it with: brew install xcodegen" >&2
  exit 1
fi

xcodegen generate
echo "Generated BitdriftShopOtel.xcodeproj -- open it, or run ./scripts/ios-3-start-simulator.sh && ./scripts/ios-4-start-app.sh"
