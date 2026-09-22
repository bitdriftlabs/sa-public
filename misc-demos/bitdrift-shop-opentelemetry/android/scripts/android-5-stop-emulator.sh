#!/usr/bin/env bash
# Stop the running emulator(s) started by scripts/android-2-start-emulator.sh.
set -euo pipefail

SDK_DIR="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export PATH="$SDK_DIR/platform-tools:$PATH"

EMU_IDS="$(adb devices | awk 'NR>1 && $2=="device"{print $1}' | grep -E '^emulator-' || true)"

if [[ -z "$EMU_IDS" ]]; then
  echo "No emulator is running."
  exit 0
fi

for id in $EMU_IDS; do
  echo "Stopping $id ..."
  adb -s "$id" emu kill
done

echo "Stopped."
