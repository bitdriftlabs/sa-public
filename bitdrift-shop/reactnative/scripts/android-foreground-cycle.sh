#!/usr/bin/env bash
# Repeatedly foregrounds and backgrounds ai.bitdrift.rn.shop via adb, without a
# human switching apps by hand. Mirrors ../../android/scripts/foreground-cycle.sh.
#
# Backgrounding goes through ActivityManager (`am start` with a HOME intent)
# rather than `input keyevent KEYCODE_HOME`: the keyevent passes through the
# input dispatcher and can get silently dropped if focus/IME state is mid-
# transition, which is exactly the flakiness this was written to avoid.
#
# Usage:
#   ./android-foreground-cycle.sh        # cycle forever, until Ctrl-C
#   ./android-foreground-cycle.sh -10    # cycle exactly 10 times
#   ./android-foreground-cycle.sh --slow -5   # 30s foreground / 20s background per cycle,
#                                              # instead of the default 6s/5s.
set -euo pipefail

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib" && pwd)"
# shellcheck source=../../scripts/lib/driver-adb.sh
source "$LIB/driver-adb.sh"
# shellcheck source=../../scripts/lib/foreground-cycle.sh
source "$LIB/foreground-cycle.sh"

PKG="ai.bitdrift.rn.shop"
adb_setup

fc_prepare() {
  SERIAL="$(adb_serial)"
  [[ -n "$SERIAL" ]] || { echo "No device/emulator attached." >&2; return 1; }
  FC_LABEL="$PKG on $SERIAL"
}
fc_foreground() { adb_go_foreground; }
fc_background() { adb_go_background; }
FC_DONE_MESSAGE="Done."

foreground_cycle_main "$@"
