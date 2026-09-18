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

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=demo-lib.sh
source "scripts/demo-lib.sh"

usage() {
  local exit_code="${1:-1}"
  echo "Usage: $(basename "$0") [--simulator|--device] [--slow] [-N]" >&2
  echo "  No -N: cycle forever (Ctrl-C to stop). -N: cycle exactly N times." >&2
  echo "  --slow: 30s foreground / 20s background per cycle, instead of 6s/5s." >&2
  echo "  --simulator|--device: pick the target explicitly (default: auto-detect)." >&2
  echo "  --help|-h: show this message." >&2
  exit "$exit_code"
}

for arg in "$@"; do
  [[ "$arg" == "--help" || "$arg" == "-h" ]] && usage 0
done

parse_target_flags "$@"
set -- ${PARSED_REST[@]+"${PARSED_REST[@]}"}

SLOW=0
REMAINING=()
for arg in "$@"; do
  if [[ "$arg" == "--slow" ]]; then
    SLOW=1
  else
    REMAINING+=("$arg")
  fi
done
set -- ${REMAINING[@]+"${REMAINING[@]}"}

CYCLES=""
if [[ $# -gt 0 ]]; then
  [[ "$1" =~ ^-([0-9]+)$ ]] || usage
  CYCLES="${BASH_REMATCH[1]}"
fi

if [[ "$SLOW" -eq 1 ]]; then
  FOREGROUND_SECONDS="${FOREGROUND_SECONDS:-30}"
  BACKGROUND_SECONDS="${BACKGROUND_SECONDS:-20}"
else
  FOREGROUND_SECONDS="${FOREGROUND_SECONDS:-6}"
  BACKGROUND_SECONDS="${BACKGROUND_SECONDS:-5}"
fi

if ! resolve_target "$PARSED_KIND" "$PARSED_ID"; then
  if [[ "${RESOLVE_ERROR:-none}" == "none" ]]; then
    echo "No target found. Boot a simulator, or connect a device and pass --device." >&2
  fi
  exit 1
fi

if ! app_installed; then
  echo "$BUNDLE_ID is not installed on $(target_label)." >&2
  exit 1
fi

if [[ -n "$CYCLES" ]]; then
  echo "Cycling $BUNDLE_ID on $(target_label): $CYCLES foreground/background cycles" \
    "(${FOREGROUND_SECONDS}s foreground, ${BACKGROUND_SECONDS}s background each)"
else
  echo "Cycling $BUNDLE_ID on $(target_label) indefinitely (Ctrl-C to stop)" \
    "(${FOREGROUND_SECONDS}s foreground, ${BACKGROUND_SECONDS}s background each)"
fi

launch_app

i=0
while [[ -z "$CYCLES" || "$i" -lt "$CYCLES" ]]; do
  i=$((i + 1))
  sleep "$FOREGROUND_SECONDS"
  background_app
  sleep "$BACKGROUND_SECONDS"
  launch_app
  if [[ -n "$CYCLES" ]]; then
    echo "cycle $i/$CYCLES done"
  else
    echo "cycle $i done"
  fi
done

echo "Done."
