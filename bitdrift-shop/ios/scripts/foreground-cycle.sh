#!/usr/bin/env bash
# Repeatedly foregrounds and backgrounds BitdriftShop, to generate
# foreground_session spans (see BitdriftShopApp.swift) without a human
# switching apps by hand. Mirrors ../../android/scripts/foreground-cycle.sh.
#
# Backgrounding uses demo-lib.sh's background_app (launches SpringBoard on
# a simulator, Settings on a device — neither platform lets an app background
# itself), the same mechanism watchdog.sh already relies on for the
# background half of the crash sweep.
#
# Usage:
#   ./foreground-cycle.sh          # cycle forever, until Ctrl-C
#   ./foreground-cycle.sh -10      # cycle exactly 10 times
#   ./foreground-cycle.sh --device -10
#   ./foreground-cycle.sh --slow -5   # 30s foreground / 20s background per cycle,
#                                      # instead of the default 6s/5s -- use this to
#                                      # rule out cycling speed as a factor when a
#                                      # foreground->background workflow isn't
#                                      # matching (FOREGROUND_SECONDS/BACKGROUND_SECONDS
#                                      # env vars still override either default).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$HERE/../../scripts/lib"
cd "$HERE/.."

# shellcheck source=demo-lib.sh
source "scripts/demo-lib.sh"
# shellcheck source=../../scripts/lib/foreground-cycle.sh
source "$LIB/foreground-cycle.sh"

FC_USAGE_FLAGS="[--simulator|--device] "
FC_USAGE_EXTRA="  --simulator|--device: pick the target explicitly (default: auto-detect)."

fc_parse_args() { parse_target_flags "$@"; FC_REST=(${PARSED_REST[@]+"${PARSED_REST[@]}"}); }
fc_prepare() {
  if ! resolve_target "$PARSED_KIND" "$PARSED_ID"; then
    [[ "${RESOLVE_ERROR:-none}" == "none" ]] && echo "No target found. Boot a simulator, or connect a device and pass --device." >&2
    return 1
  fi
  if ! app_installed; then echo "$BUNDLE_ID is not installed on $(target_label)." >&2; return 1; fi
  FC_LABEL="$BUNDLE_ID on $(target_label)"
}
fc_foreground() { launch_app; }
fc_background() { background_app; }

foreground_cycle_main "$@"
