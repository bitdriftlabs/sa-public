#!/usr/bin/env bash
# Boot the emulator (windowed by default) and wait until it reports fully booted.
# Defaults to the hardware GPU backend (-gpu host) on macOS — override with
# EMU_GPU=swiftshader_indirect if you want software rendering instead.
# EMULATOR_WINDOW=0 runs headless.
#
# Mirrors ../../../../bitdrift-shop/android/scripts/android-2-start-emulator.sh
# — identical logic, same "medium_phone" AVD default (the earlier
# "Medium_Phone_Control" / "bitdrift_shop" AVDs hit unresolved boot failures —
# HVF/mprotect issues on macOS 26 — and were replaced).
set -euo pipefail

SDK_DIR="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
AVD_NAME="${AVD_NAME:-medium_phone}"
# Newer emulator builds require ANDROID_SDK_ROOT specifically and log
# "ANDROID_SDK_ROOT is undefined" (then fail) if only ANDROID_HOME is set.
export ANDROID_HOME="$SDK_DIR"
export ANDROID_SDK_ROOT="$SDK_DIR"
export PATH="$SDK_DIR/emulator:$SDK_DIR/platform-tools:$PATH"

# Already booted?
if adb devices | awk 'NR>1 && $2=="device"' | grep -qE '^emulator-'; then
  echo "An emulator is already running."
else
  EMU_ARGS=(-avd "$AVD_NAME" -no-audio -no-boot-anim)
  [[ "${EMULATOR_WINDOW:-1}" == "0" ]] && EMU_ARGS+=(-no-window)
  # Default to the hardware GPU backend on macOS. Override with
  # EMU_GPU=swiftshader_indirect for software rendering.
  if [[ -z "${EMU_GPU:-}" && "$(uname -s)" == "Darwin" ]]; then
    EMU_GPU=host
  fi
  [[ -n "${EMU_GPU:-}" ]] && EMU_ARGS+=(-gpu "$EMU_GPU")

  echo "Starting emulator '$AVD_NAME' (gpu=${EMU_GPU:-auto}) ..."
  nohup emulator "${EMU_ARGS[@]}" >/tmp/bd-shop-otel-android-emulator.log 2>&1 &
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
    echo "Emulator did not finish booting in time. See /tmp/bd-shop-otel-android-emulator.log"
    exit 1
  fi
fi

echo "Emulator is up:"
adb devices
