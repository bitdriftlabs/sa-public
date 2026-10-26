#!/usr/bin/env bash
# bitdrift-shop test entry point (command line only, no IDE).
#
#   ./test.sh <app|all> <unit|smoke>
#   app:  android | ios | rn-android | rn-ios | flutter-android | flutter-ios   (kmp: best effort, not wired)
#   unit:  no emulator/simulator: codegen drift check, spec validation, conformance self-test,
#          and the app's own unit tests where it has them.
#   smoke: build, install, launch with `sim_runs/sim_seed/persona/record_file` launch arguments,
#          wait for the `sim_autorun_complete` marker, pull the recorded JSONL off the device and
#          run tools/conformance on it.
#
# Tunables (env): SIM_RUNS (5) SIM_SEED (42) PERSONA (control|variant_a|variant_b) SMOKE_TIMEOUT (360s)
# Prints one summary line per app; exits non-zero if any failed.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="$ROOT/tools/codegen/.venv/bin/python"
OUT="${TEST_OUT:-/tmp/bdshop-test}"
SIM_RUNS="${SIM_RUNS:-5}"
SIM_SEED="${SIM_SEED:-42}"
PERSONA="${PERSONA:-control}"
SMOKE_TIMEOUT="${SMOKE_TIMEOUT:-360}"
SDK_DIR="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export PATH="$SDK_DIR/platform-tools:$PATH"

mkdir -p "$OUT"

die() { echo "$*" >&2; exit 2; }

ensure_python() {
  [[ -x "$PY" ]] || "$ROOT/tools/codegen/run.sh" >/dev/null 2>&1 || true
  [[ -x "$PY" ]] || die "tools/codegen/.venv missing; run tools/codegen/run.sh once"
}

# ── shared unit steps ────────────────────────────────────────────────────────
unit_common() {
  ensure_python
  "$ROOT/tools/codegen/check.sh" >"$OUT/codegen-check.log" 2>&1 || { echo "codegen drift: see $OUT/codegen-check.log"; return 1; }
  "$PY" "$ROOT/spec/validate.py" --strict >"$OUT/spec-validate.log" 2>&1 || { echo "spec validation failed: see $OUT/spec-validate.log"; return 1; }
  "$PY" "$ROOT/tools/conformance/conformance.py" --self-test >"$OUT/conformance-selftest.log" 2>&1 || { echo "conformance self-test failed"; return 1; }
}

# ── android ──────────────────────────────────────────────────────────────────
android_serial() { adb devices | awk 'NR>1 && $2=="device"{print $1}' | grep -E '^emulator-' | head -n1; }

unit_android() {
  unit_common || return 1
  (cd "$ROOT/android" && ./gradlew -q :app:testDebugUnitTest >"$OUT/android-unit.log" 2>&1) || { echo "gradle unit tests failed: see $OUT/android-unit.log"; return 1; }
}

smoke_android() {
  local serial; serial="$(android_serial)"
  if [[ -z "$serial" ]]; then
    echo "starting headless emulator ..."
    (cd "$ROOT/android" && EMULATOR_WINDOW=0 bash scripts/android-2-start-emulator.sh >"$OUT/android-emulator.log" 2>&1) || { echo "emulator failed: see $OUT/android-emulator.log"; return 1; }
    serial="$(android_serial)"
  fi
  [[ -n "$serial" ]] || { echo "no emulator"; return 1; }
  (cd "$ROOT/android" && ./gradlew -q :app:installDebug >"$OUT/android-build.log" 2>&1) || { echo "build/install failed: see $OUT/android-build.log"; return 1; }
  local pkg=ai.bitdrift.shop file=smoke.jsonl
  adb -s "$serial" shell am force-stop "$pkg"
  adb -s "$serial" shell run-as "$pkg" rm -f "files/record/$file" >/dev/null 2>&1
  adb -s "$serial" logcat -c
  adb -s "$serial" shell am start -n "$pkg/.MainActivity" \
    --ei sim_runs "$SIM_RUNS" --el sim_seed "$SIM_SEED" --es persona "$PERSONA" --es record_file "$file" >/dev/null
  local waited=0 seen=0
  while (( waited < SMOKE_TIMEOUT )); do
    if adb -s "$serial" shell run-as "$pkg" cat "files/record/$file" 2>/dev/null | grep -q '"sim_autorun_complete"'; then break; fi
    if [[ -n "$(adb -s "$serial" shell pidof "$pkg" | tr -d '\r')" ]]; then seen=1
    elif (( seen )) || (( waited > 30 )); then
      adb -s "$serial" logcat -d -b crash >"$OUT/android-logcat.txt"
      echo "app died before the autorun finished (crash log: $OUT/android-logcat.txt)"; return 1
    fi
    sleep 3; waited=$((waited + 3))
  done
  (( waited < SMOKE_TIMEOUT )) || { echo "timed out after ${SMOKE_TIMEOUT}s waiting for sim_autorun_complete"; return 1; }
  adb -s "$serial" exec-out run-as "$pkg" cat "files/record/$file" >"$OUT/android-$file"
  "$PY" "$ROOT/tools/conformance/conformance.py" --platform android --runs "$SIM_RUNS" "$OUT/android-$file"
}

# ── dispatch ─────────────────────────────────────────────────────────────────
run_app() {
  local app="$1" tier="$2" fn="${2}_${1//-/_}"
  if ! declare -F "$fn" >/dev/null; then echo "SKIP  $app $tier (not wired yet)"; return 0; fi
  local t0=$SECONDS
  if "$fn"; then echo "PASS  $app $tier ($((SECONDS - t0))s)"; return 0; fi
  echo "FAIL  $app $tier ($((SECONDS - t0))s)"; return 1
}

[[ $# -eq 2 ]] || die "usage: $0 <app|all> <unit|smoke>"
app="$1"; tier="$2"
[[ "$tier" == unit || "$tier" == smoke ]] || die "tier must be unit or smoke"
apps=(android ios rn-android rn-ios flutter-android flutter-ios)
[[ "$app" == all ]] || apps=("$app")
rc=0
for a in "${apps[@]}"; do run_app "$a" "$tier" || rc=1; done
exit $rc
