#!/usr/bin/env bash
# Boot the emulator (windowed by default) and wait until it reports fully booted.
# On macOS the windowed GPU backend is unstable, so software rendering
# (swiftshader_indirect) is the default there — override with EMU_GPU=host if
# you want to try the GPU backend. EMULATOR_WINDOW=0 runs headless.
set -euo pipefail

SDK_DIR="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
AVD_NAME="${AVD_NAME:-bitdrift_shop}"
export PATH="$SDK_DIR/emulator:$SDK_DIR/platform-tools:$PATH"

# Already booted?
if adb devices | awk 'NR>1 && $2=="device"' | grep -qE '^emulator-'; then
  echo "An emulator is already running."
else
  EMU_ARGS=(-avd "$AVD_NAME" -no-audio -no-boot-anim)
  [[ "${EMULATOR_WINDOW:-1}" == "0" ]] && EMU_ARGS+=(-no-window)
  # The windowed GPU backend crashes on macOS (CoreGraphics context errors),
  # so default to software rendering there. Override with EMU_GPU=host.
  if [[ -z "${EMU_GPU:-}" && "$(uname -s)" == "Darwin" ]]; then
    EMU_GPU=swiftshader_indirect
  fi
  [[ -n "${EMU_GPU:-}" ]] && EMU_ARGS+=(-gpu "$EMU_GPU")

  echo "Starting emulator '$AVD_NAME' ..."
  nohup emulator "${EMU_ARGS[@]}" >/tmp/bd-flutter-emulator.log 2>&1 &
  disown || true

  echo "Waiting for the device to come online and finish booting ..."
  adb wait-for-device
  booted=""
  for _ in $(seq 1 90); do
    booted="$(adb -e shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)"
    [[ "$booted" == "1" ]] && break
    sleep 2
  done
  if [[ "$booted" != "1" ]]; then
    echo "Emulator did not finish booting in time. See /tmp/bd-flutter-emulator.log"
    exit 1
  fi
fi

echo "Emulator is up:"
adb devices
