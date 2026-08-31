#!/usr/bin/env bash
# Build and run the app on the connected emulator (no Android Studio).
#
# Requires a running emulator (scripts/start-emulator.sh). Config can come from
# the project's .env file (BITDRIFT_SDK_KEY, BITDRIFT_API_HOST, BACKEND_PORT) or
# the shell environment (which wins — export it to override). All values are
# injected at compile time via --dart-define.
#
# Tip: put the key in flutter/.env, or `export BITDRIFT_SDK_KEY=... ; bash scripts/run-app.sh`
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

# 2. Load config: .env fills in anything not already set in the shell env.
#    (shell exports win, so `export BITDRIFT_SDK_KEY=...` still overrides .env)
if [[ -f "$ROOT/.env" ]]; then
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*([A-Z][A-Z0-9_]*)=(.*)$ ]] || continue
    key="${BASH_REMATCH[1]}"
    [[ -n "${!key:-}" ]] && continue
    export "$key=${BASH_REMATCH[2]}"
  done < "$ROOT/.env"
fi

# 3. Compile-time defines (the app reads them via String.fromEnvironment).
DART_DEFINES=(--dart-define="BITDRIFT_SDK_KEY=${BITDRIFT_SDK_KEY:-}")
[[ -n "${BITDRIFT_API_HOST:-}" ]] && DART_DEFINES+=(--dart-define="BITDRIFT_API_HOST=$BITDRIFT_API_HOST")
[[ -n "${BACKEND_PORT:-}" ]] && DART_DEFINES+=(--dart-define="BACKEND_PORT=$BACKEND_PORT")

# 4. Run.
cd "$ROOT"
exec flutter run --release -d "$EMU_ID" "${DART_DEFINES[@]}"
