#!/usr/bin/env bash
# Build and run the app on the connected emulator (no Android Studio).
#
# Requires a running emulator (scripts/start-emulator.sh). Pass credentials /
# config as environment variables; they are injected at compile time.
#
#   BITDRIFT_SDK_KEY   your key (empty => runs locally, no bitdrift upload)
#   BITDRIFT_API_HOST  optional, defaults to https://api.bitdrift.io
#   BACKEND_PORT       optional, defaults to 5173
#
# Tip: `export BITDRIFT_SDK_KEY=... ; bash scripts/run-app.sh`
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_DIR="${FLUTTER_DIR:-$HOME/development/flutter}"
SDK_DIR="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export PATH="$FLUTTER_DIR/bin:$SDK_DIR/platform-tools:$PATH"

# 1. A connected emulator.
EMU_ID="$(adb devices | awk 'NR>1 && $2=="device"{print $1}' | grep -E '^emulator-' | head -n1 || true)"
if [[ -z "$EMU_ID" ]]; then
  echo "No emulator attached. Start one first: bash scripts/start-emulator.sh"
  exit 1
fi
echo "Targeting emulator: $EMU_ID"

# 2. Compile-time defines (the app reads them via String.fromEnvironment).
DART_DEFINES=(--dart-define="BITDRIFT_SDK_KEY=${BITDRIFT_SDK_KEY:-}")
[[ -n "${BITDRIFT_API_HOST:-}" ]] && DART_DEFINES+=(--dart-define="BITDRIFT_API_HOST=$BITDRIFT_API_HOST")
[[ -n "${BACKEND_PORT:-}" ]] && DART_DEFINES+=(--dart-define="BACKEND_PORT=$BACKEND_PORT")

# 3. Run.
cd "$ROOT"
exec flutter run --release -d "$EMU_ID" "${DART_DEFINES[@]}"
