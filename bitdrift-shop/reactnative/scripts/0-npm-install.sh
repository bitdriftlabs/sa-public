#!/usr/bin/env bash
# Install npm dependencies and check for a configured .env. Platform-specific
# setup (SDK/simulator/emulator) is scripts/android-1-setup.sh /
# scripts/ios-1-setup.sh. Idempotent.
#
# Mirrors what ../start.sh already does inline — pulled out here so it can run
# standalone, matching the numbered-script convention in ../../android/scripts,
# ../../ios/scripts and ../../flutter/scripts.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -d node_modules ]]; then
  echo "node_modules found, skipping npm install."
else
  echo "Installing npm dependencies ..."
  npm install
fi

if [[ -f .env ]] && grep -q "^BITDRIFT_API_KEY=" .env && ! grep -q "^BITDRIFT_API_KEY=your_api_key_here$" .env; then
  echo ".env exists and sets BITDRIFT_API_KEY."
else
  echo "WARNING: no .env with a real BITDRIFT_API_KEY — the app will start without a key." >&2
  echo "  cp .env.example .env  # then add your API key" >&2
fi

echo
echo "Done. Next: bash scripts/android-1-setup.sh or bash scripts/ios-1-setup.sh"
