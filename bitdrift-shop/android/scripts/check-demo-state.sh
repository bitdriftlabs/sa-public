#!/usr/bin/env bash
# Crash Loop, ANR-A, and Force-Quit persist their "active" flag in SharedPreferences by
# design, so each mode survives the deliberate crash/freeze/kill + relaunch cycle it drives.
# That also means switching to a different demo without explicitly turning a mode off leaves
# it silently armed — Fast Crash Mode in particular skips all UI, so there's no in-app signal
# it's still running. Run this before starting any demo session to check for (and optionally
# clear) leftover state from a previous one.
set -uo pipefail

PKG="ai.bitdrift.shop"
SERIAL=""
RESET=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [-s emulator-5554] [--reset]

Checks whether Crash Loop, ANR-A, or Force-Quit fault-injection modes were left
active from a previous demo session.

Options:
  -s SERIAL   ADB device serial (required if multiple emulators are connected)
  --reset     Force-stop the app and clear any active fault-mode flags
  -h          Show help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s)
      SERIAL="$2"
      shift 2
      ;;
    --reset)
      RESET=1
      shift
      ;;
    -h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 2
      ;;
  esac
done

ADB=(adb)
if ! command -v adb >/dev/null 2>&1; then
  if [[ -x "$HOME/Library/Android/sdk/platform-tools/adb" ]]; then
    ADB=("$HOME/Library/Android/sdk/platform-tools/adb")
  else
    echo "Error: adb not found. Add it to PATH or install Android SDK." >&2
    exit 1
  fi
fi

if [[ -z "$SERIAL" ]]; then
  emulators=$("${ADB[0]}" devices | awk '/^emulator-[0-9]+[[:space:]]+device$/ {print $1}')
  count=$(echo "$emulators" | sed '/^$/d' | wc -l | tr -d ' ')
  if [[ "$count" == "1" ]]; then
    SERIAL=$(echo "$emulators" | head -1)
  elif [[ "$count" == "0" ]]; then
    echo "Error: no running emulator detected." >&2
    exit 1
  else
    echo "Error: multiple emulators detected. Pass -s SERIAL to pick one:" >&2
    echo "$emulators" >&2
    exit 1
  fi
fi
ADB+=(-s "$SERIAL")

read_prefs() {
  "${ADB[@]}" shell run-as "$PKG" cat "/data/data/$PKG/shared_prefs/$1" 2>/dev/null | tr -d '\r'
}

is_active() { echo "$1" | grep -q 'name="active" value="true"'; }
is_fast_mode() { echo "$1" | grep -q 'name="fast_mode" value="true"'; }
is_oom_only() { echo "$1" | grep -q 'name="oom_only" value="true"'; }

CRASH_XML=$(read_prefs crash_loop.xml)
ANR_XML=$(read_prefs anr_a.xml)
FQ_XML=$(read_prefs force_quit.xml)

CRASH_ACTIVE=0
FAST_MODE=0
OOM_ONLY=0
ANR_ACTIVE=0
FQ_ACTIVE=0
is_active "$CRASH_XML" && CRASH_ACTIVE=1
is_fast_mode "$CRASH_XML" && FAST_MODE=1
is_oom_only "$CRASH_XML" && OOM_ONLY=1
is_active "$ANR_XML" && ANR_ACTIVE=1
is_active "$FQ_XML" && FQ_ACTIVE=1

if [[ "$CRASH_ACTIVE" -eq 0 && "$ANR_ACTIVE" -eq 0 && "$FQ_ACTIVE" -eq 0 ]]; then
  echo "OK: no fault-injection mode left active on $SERIAL. Safe to start a new demo."
  exit 0
fi

echo "WARNING: fault-injection state left active on $SERIAL from a previous session:"
if [[ "$CRASH_ACTIVE" -eq 1 ]]; then
  mode_desc="Crash Loop: ON"
  [[ "$FAST_MODE" -eq 1 ]] && mode_desc+=", Fast Crash Mode: ON — crashes immediately on every relaunch, skips all UI"
  [[ "$OOM_ONLY" -eq 1 ]] && mode_desc+=", OOM-only: ON — cycling Crashes.oomOnly instead of the full catalog"
  echo "  - $mode_desc"
fi
[[ "$ANR_ACTIVE" -eq 1 ]] && echo "  - ANR-A: ON"
[[ "$FQ_ACTIVE" -eq 1 ]] && echo "  - Force-Quit: ON"

if [[ "$RESET" -eq 0 ]]; then
  echo
  echo "Re-run with --reset to force-stop the app and clear these flags, or use the"
  echo "in-app toggles (Advanced screen, or the Welcome screen's 'Stop crash loop' button)."
  exit 1
fi

echo
echo "Resetting..."
"${ADB[@]}" shell am force-stop "$PKG"

if [[ "$CRASH_ACTIVE" -eq 1 || "$FAST_MODE" -eq 1 || "$OOM_ONLY" -eq 1 ]]; then
  "${ADB[@]}" shell "run-as $PKG sed -i -e 's/name=\"active\" value=\"true\"/name=\"active\" value=\"false\"/' -e 's/name=\"fast_mode\" value=\"true\"/name=\"fast_mode\" value=\"false\"/' -e 's/name=\"oom_only\" value=\"true\"/name=\"oom_only\" value=\"false\"/' /data/data/$PKG/shared_prefs/crash_loop.xml"
fi
if [[ "$ANR_ACTIVE" -eq 1 ]]; then
  "${ADB[@]}" shell "run-as $PKG sed -i -e 's/name=\"active\" value=\"true\"/name=\"active\" value=\"false\"/' /data/data/$PKG/shared_prefs/anr_a.xml"
fi
if [[ "$FQ_ACTIVE" -eq 1 ]]; then
  "${ADB[@]}" shell "run-as $PKG sed -i -e 's/name=\"active\" value=\"true\"/name=\"active\" value=\"false\"/' /data/data/$PKG/shared_prefs/force_quit.xml"
fi

echo "Done. Verify:"
echo "  adb -s $SERIAL shell run-as $PKG cat /data/data/$PKG/shared_prefs/crash_loop.xml /data/data/$PKG/shared_prefs/anr_a.xml /data/data/$PKG/shared_prefs/force_quit.xml"
