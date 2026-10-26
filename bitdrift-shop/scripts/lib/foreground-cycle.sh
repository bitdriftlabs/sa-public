# Shared foreground/background cycling loop for the four per-app foreground-cycle scripts.
#
# The caller defines these hooks, then calls `foreground_cycle_main "$@"`:
#   fc_parse_args "$@"   optional: consume platform flags; set FC_REST to the remaining args
#   fc_prepare           resolve/validate the target; set FC_LABEL ("<app> on <target>"); non-zero to abort
#   fc_foreground        bring the app to the foreground
#   fc_background        send the app to the background
#   FC_DONE_MESSAGE      optional: final line
# Arguments: [--slow] [-N] (cycle forever without -N), plus whatever fc_parse_args handles.
# FOREGROUND_SECONDS / BACKGROUND_SECONDS (default 6/5; --slow: 30/20) override the timings.

fc_usage() {
  local exit_code="${1:-1}"
  echo "Usage: $(basename "$0") ${FC_USAGE_FLAGS:-}[--slow] [-N]" >&2
  echo "  No -N: cycle forever (Ctrl-C to stop). -N: cycle exactly N times." >&2
  echo "  --slow: 30s foreground / 20s background per cycle, instead of 6s/5s." >&2
  [[ -n "${FC_USAGE_EXTRA:-}" ]] && echo "$FC_USAGE_EXTRA" >&2
  echo "  --help|-h: show this message." >&2
  exit "$exit_code"
}

foreground_cycle_main() {
  local arg
  for arg in "$@"; do [[ "$arg" == "--help" || "$arg" == "-h" ]] && fc_usage 0; done

  FC_REST=("$@")
  if declare -F fc_parse_args >/dev/null; then fc_parse_args "$@"; fi
  set -- ${FC_REST[@]+"${FC_REST[@]}"}

  local slow=0 rest=()
  for arg in "$@"; do
    if [[ "$arg" == "--slow" ]]; then slow=1; else rest+=("$arg"); fi
  done
  set -- ${rest[@]+"${rest[@]}"}

  local cycles="${CYCLES:-}"
  if [[ $# -gt 0 ]]; then
    [[ "$1" =~ ^-([0-9]+)$ ]] || fc_usage
    cycles="${BASH_REMATCH[1]}"
  fi

  if (( slow )); then
    FOREGROUND_SECONDS="${FOREGROUND_SECONDS:-30}"
    BACKGROUND_SECONDS="${BACKGROUND_SECONDS:-20}"
  else
    FOREGROUND_SECONDS="${FOREGROUND_SECONDS:-6}"
    BACKGROUND_SECONDS="${BACKGROUND_SECONDS:-5}"
  fi

  fc_prepare || exit 1

  if [[ -n "$cycles" ]]; then
    echo "Cycling $FC_LABEL: $cycles foreground/background cycles (${FOREGROUND_SECONDS}s foreground, ${BACKGROUND_SECONDS}s background each)"
  else
    echo "Cycling $FC_LABEL indefinitely (Ctrl-C to stop) (${FOREGROUND_SECONDS}s foreground, ${BACKGROUND_SECONDS}s background each)"
  fi

  fc_foreground || true
  local i=0
  while [[ -z "$cycles" || "$i" -lt "$cycles" ]]; do
    i=$((i + 1))
    sleep "$FOREGROUND_SECONDS"
    fc_background || true
    sleep "$BACKGROUND_SECONDS"
    fc_foreground || true
    if [[ -n "$cycles" ]]; then echo "cycle $i/$cycles done"; else echo "cycle $i done"; fi
  done
  echo "${FC_DONE_MESSAGE:-Done.}"
}
