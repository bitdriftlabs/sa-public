#!/usr/bin/env bash
# Start or stop the Android emulator, for every demo app (native, React Native, Flutter).
# The one place for this logic; the per-app copies were removed.
#
#   scripts/device/android-emulator.sh start   # boot (windowed) and wait until fully booted
#   scripts/device/android-emulator.sh stop    # kill every running emulator
#
# Environment:
#   AVD_NAME          AVD to boot (default Medium_Phone, the AVD each app's android-1-setup.sh creates)
#   EMULATOR_WINDOW=0 run headless
#   EMU_GPU           -gpu mode. Defaults to swiftshader_indirect on macOS; EMU_GPU=host to try hardware.
#
# -gpu host is NOT safe to default to: on macOS 26.6.2 it either hangs at ~100% CPU with a black
# window or crashes in the emulator's own HangDetector startup code (qemu_android_emulation_setup ->
# async_run_on_cpu, called before any CPU exists) -- a bug in this emulator build's HVF fallback, not
# fixable via AVD config. Android Studio's Device Manager boots the same AVD because it never passes
# -gpu host and lands on software rendering (lavapipe/swiftshader) instead.
set -euo pipefail

SDK_DIR="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
AVD_NAME="${AVD_NAME:-Medium_Phone}"
LOG=/tmp/bd-shop-android-emulator.log
# Newer emulator builds require ANDROID_SDK_ROOT specifically and log "ANDROID_SDK_ROOT is undefined"
# (then fail) if only ANDROID_HOME is set.
export ANDROID_HOME="$SDK_DIR"
export ANDROID_SDK_ROOT="$SDK_DIR"
export PATH="$SDK_DIR/emulator:$SDK_DIR/platform-tools:$PATH"

emulator_ids() { adb devices | awk 'NR>1 && $2=="device"{print $1}' | grep -E '^emulator-' || true; }

start() {
  if [[ -n "$(emulator_ids)" ]]; then
    echo "An emulator is already running."
  else
    local args=(-avd "$AVD_NAME" -no-audio -no-boot-anim)
    [[ "${EMULATOR_WINDOW:-1}" == "0" ]] && args+=(-no-window)
    if [[ -z "${EMU_GPU:-}" && "$(uname -s)" == "Darwin" ]]; then EMU_GPU=swiftshader_indirect; fi
    [[ -n "${EMU_GPU:-}" ]] && args+=(-gpu "$EMU_GPU")

    echo "Starting emulator '$AVD_NAME' (gpu=${EMU_GPU:-auto}) ..."
    nohup emulator "${args[@]}" >"$LOG" 2>&1 &
    disown || true

    echo "Waiting for the device to come online and finish booting ..."
    adb wait-for-device
    local booted=""
    for _ in $(seq 1 90); do
      booted="$(adb -e shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)"
      [[ "$booted" == "1" ]] && break
      sleep 2
    done
    if [[ "$booted" != "1" ]]; then
      echo "Emulator did not finish booting in time. See $LOG"
      exit 1
    fi
  fi
  echo "Emulator is up:"
  adb devices
}

stop() {
  local ids; ids="$(emulator_ids)"
  if [[ -z "$ids" ]]; then
    echo "No emulator is running."
    return 0
  fi
  local id
  for id in $ids; do
    echo "Stopping $id ..."
    adb -s "$id" emu kill
  done
  echo "Stopped."
}

case "${1:-}" in
  start) start ;;
  stop) stop ;;
  *) echo "usage: ${0##*/} start|stop" >&2; exit 2 ;;
esac
