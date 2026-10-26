#!/usr/bin/env bash
# Repeatedly foregrounds and backgrounds ai.bitdrift.shop via adb, to generate
# AppStart/AppStop lifecycle logs for the bd-shop-13/14/15 workflows (session
# count, session duration, crash rate per foreground) without a human
# switching apps by hand. See ../../workflows/docs/foreground-session-metrics.md for
# what those workflows chart and why.
#
# A genuinely in-app version of this (a toggle that backgrounds itself and
# then self-resumes on a timer) was tried and dropped: Android's
# background-activity-launch policy blocks a backgrounded app from bringing
# itself back to the foreground (confirmed via logcat: "Background activity
# launch blocked! goo.gle/android-bal"). adb's `am start` is not subject to
# that restriction, so this stays external.
#
# Usage:
#   ./foreground-cycle.sh        # cycle forever, until Ctrl-C
#   ./foreground-cycle.sh -10    # cycle exactly 10 times
#   ./foreground-cycle.sh --slow -5   # 30s foreground / 20s background per cycle,
#                                      # instead of the default 6s/5s -- use this to
#                                      # rule out cycling speed as a factor when a
#                                      # foreground->background workflow isn't
#                                      # matching (FOREGROUND_SECONDS/BACKGROUND_SECONDS
#                                      # env vars still override either default).
set -euo pipefail

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib" && pwd)"
# shellcheck source=../../scripts/lib/driver-adb.sh
source "$LIB/driver-adb.sh"
# shellcheck source=../../scripts/lib/foreground-cycle.sh
source "$LIB/foreground-cycle.sh"

PKG="ai.bitdrift.shop"
adb_setup

fc_prepare() {
  SERIAL="$(adb_serial)"
  [[ -n "$SERIAL" ]] || { echo "No device/emulator attached." >&2; return 1; }
  FC_LABEL="$PKG on $SERIAL"
}
fc_foreground() { adb_go_foreground; }
fc_background() { adb_go_background; }
FC_DONE_MESSAGE="Done. Charts: bd workflow charts <workflow id> -ojson --last 1h  (see workflows/docs/foreground-session-metrics.md)"

foreground_cycle_main "$@"
