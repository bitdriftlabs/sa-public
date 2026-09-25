#!/usr/bin/env bash
# Boot the emulator (windowed by default) and wait until it reports fully booted.
# Defaults to software rendering (-gpu swiftshader_indirect) on macOS — override
# with EMU_GPU=host if you want to try the hardware GPU backend.
# EMULATOR_WINDOW=0 runs headless.
#
# -gpu host is NOT safe to default to here: on this machine (macOS 26.6.2) it
# reliably either hangs at ~100% CPU with a black window, or crashes outright
# with a NULL-pointer dereference in the emulator's own HangDetector startup
# code (qemu_android_emulation_setup -> async_run_on_cpu, called before any
# CPU exists) -- a real bug in this emulator build's HVF fallback handling,
# not something fixable via AVD config. Confirmed by comparison: Android
# Studio's Device Manager boots the same AVD successfully because it never
# passes -gpu host in the first place and lands on software rendering
# (lavapipe/swiftshader) instead.
#
# Mirrors ../../flutter/scripts/android-2-start-emulator.sh — identical logic.
# AVD_NAME default was "bitdrift_shop" (matching Flutter's own scripts, so
# either app's start-app script could reuse whichever emulator was already
# running) until that AVD hit an unresolved boot failure (HVF/mprotect issues
# on macOS 26, reproduced in Android Studio too, not just this script) and got
# deleted. Then defaulted to "Medium_Phone_Control", one of Android Studio's
# own default AVDs, until that was replaced too. Now defaults to
# "medium_phone" (confirmed present via `emulator -list-avds` on this
# machine) -- no longer shares a default with Flutter's scripts unless those
# get updated too.
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
  # Default to software rendering on macOS — see header comment for why
  # -gpu host isn't safe to default to. Override with EMU_GPU=host.
  if [[ -z "${EMU_GPU:-}" && "$(uname -s)" == "Darwin" ]]; then
    EMU_GPU=swiftshader_indirect
  fi
  [[ -n "${EMU_GPU:-}" ]] && EMU_ARGS+=(-gpu "$EMU_GPU")

  echo "Starting emulator '$AVD_NAME' (gpu=${EMU_GPU:-auto}) ..."
  nohup emulator "${EMU_ARGS[@]}" >/tmp/bd-shop-android-emulator.log 2>&1 &
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
    echo "Emulator did not finish booting in time. See /tmp/bd-shop-android-emulator.log"
    exit 1
  fi
fi

echo "Emulator is up:"
adb devices
