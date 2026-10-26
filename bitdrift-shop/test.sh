#!/usr/bin/env bash
# bitdrift-shop test entry point (command line only, no IDE).
#
#   ./test.sh <app|all> <unit|smoke>
#   app:  android | ios | rn-android | rn-ios | flutter-android | flutter-ios   (kmp: best effort, not wired)
#   unit:  no emulator/simulator: codegen drift check, spec validation, conformance self-test,
#          and the app's own unit tests where it has them.
#   smoke: build, install, launch with `sim_runs/sim_seed/persona/record_file` launch arguments,
#          wait for the `sim_autorun_complete` marker, pull the recorded JSONL off the device and
#          run tools/conformance on it, including the journey check against the reference
#          engine for that persona/seed. With several apps, their journey records are also
#          diffed against each other (conformance.py --diff).
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
  "$PY" "$ROOT/tools/conformance/conformance.py" --platform android --runs "$SIM_RUNS" --persona "$PERSONA" --seed "$SIM_SEED" "$OUT/android-$file"
}

# ── ios ──────────────────────────────────────────────────────────────────────
ios_udid() { xcrun simctl list devices booted -j | "$PY" -c 'import json,sys;d=json.load(sys.stdin)["devices"];print(next((x["udid"] for l in d.values() for x in l if x["state"]=="Booted"),""))'; }

unit_ios() {
  unit_common || return 1
  # No iOS unit-test target yet: compile for the simulator so type errors surface without a device.
  (cd "$ROOT/ios" && xcodebuild -project BitdriftShop.xcodeproj -scheme BitdriftShop -configuration Debug \
     -destination 'generic/platform=iOS Simulator' -derivedDataPath build/debug build >"$OUT/ios-unit-build.log" 2>&1) \
    || { echo "xcodebuild failed: see $OUT/ios-unit-build.log"; return 1; }
}

smoke_ios() {
  local udid; udid="$(ios_udid)"
  if [[ -z "$udid" ]]; then
    (cd "$ROOT/ios" && bash scripts/ios-2-start-simulator.sh >"$OUT/ios-sim.log" 2>&1) || { echo "simulator failed: see $OUT/ios-sim.log"; return 1; }
    udid="$(ios_udid)"
  fi
  [[ -n "$udid" ]] || { echo "no booted simulator"; return 1; }
  local bundle=ai.bitdrift.shop.ios file=smoke.jsonl
  (cd "$ROOT/ios" && xcodebuild -project BitdriftShop.xcodeproj -scheme BitdriftShop -configuration Debug \
     -destination "id=$udid" -derivedDataPath build/debug build >"$OUT/ios-build.log" 2>&1) \
    || { echo "build failed: see $OUT/ios-build.log"; return 1; }
  local app; app="$(find "$ROOT/ios/build/debug/Build/Products" -maxdepth 2 -name 'BitdriftShop.app' | head -1)"
  [[ -n "$app" ]] || { echo "BitdriftShop.app not found"; return 1; }
  xcrun simctl terminate "$udid" "$bundle" >/dev/null 2>&1
  xcrun simctl install "$udid" "$app" || return 1
  local data; data="$(xcrun simctl get_app_container "$udid" "$bundle" data)"
  local rec="$data/Documents/record/$file"
  rm -f "$rec"
  xcrun simctl launch "$udid" "$bundle" -sim_runs "$SIM_RUNS" -sim_seed "$SIM_SEED" -persona "$PERSONA" -record_file "$file" >/dev/null || return 1
  local waited=0
  while (( waited < SMOKE_TIMEOUT )); do
    grep -q '"sim_autorun_complete"' "$rec" 2>/dev/null && break
    sleep 3; waited=$((waited + 3))
  done
  (( waited < SMOKE_TIMEOUT )) || { echo "timed out after ${SMOKE_TIMEOUT}s waiting for sim_autorun_complete"; return 1; }
  cp "$rec" "$OUT/ios-$file"
  "$PY" "$ROOT/tools/conformance/conformance.py" --platform ios --runs "$SIM_RUNS" --persona "$PERSONA" --seed "$SIM_SEED" "$OUT/ios-$file"
}

# ── collector-driven apps (RN, Flutter) ──────────────────────────────────────
# These apps can't take launch arguments without native code, so in debug builds they ask a local
# collector (tools/conformance/collector.py) for an autorun config and POST their records back.
ensure_android() {
  local serial; serial="$(android_serial)"
  if [[ -z "$serial" ]]; then
    echo "starting headless emulator ..." >&2
    (cd "$ROOT/android" && EMULATOR_WINDOW=0 bash scripts/android-2-start-emulator.sh >"$OUT/android-emulator.log" 2>&1) || return 1
    serial="$(android_serial)"
  fi
  [[ -n "$serial" ]] && echo "$serial"
}

ensure_ios() {
  local udid; udid="$(ios_udid)"
  if [[ -z "$udid" ]]; then
    (cd "$ROOT/ios" && bash scripts/ios-2-start-simulator.sh >"$OUT/ios-sim.log" 2>&1) || return 1
    udid="$(ios_udid)"
  fi
  [[ -n "$udid" ]] && echo "$udid"
}

COLLECTOR_PID=""
start_collector() {
  "$PY" "$ROOT/tools/conformance/collector.py" --out "$1" --runs "$SIM_RUNS" --seed "$SIM_SEED" \
    --persona "$PERSONA" --timeout "$SMOKE_TIMEOUT" >"$OUT/collector.log" 2>&1 &
  COLLECTOR_PID=$!
  sleep 1
}

# Waits for the collector to finish; if the app never asked for its config (it was already running),
# `relaunch` is called once to restart it.
await_collector() {
  local relaunch="$1" waited=0 relaunched=0 served
  while kill -0 "$COLLECTOR_PID" 2>/dev/null; do
    sleep 3; waited=$((waited + 3))
    if (( ! relaunched && waited >= 45 )); then
      served="$(curl -s -m 2 localhost:5599/status | "$PY" -c 'import json,sys;print(json.load(sys.stdin).get("served",0))' 2>/dev/null)"
      if [[ "${served:-0}" == "0" ]]; then echo "app never asked for its config; relaunching" >&2; $relaunch; fi
      relaunched=1
    fi
  done
  wait "$COLLECTOR_PID"
}

unit_rn() {
  unit_common || return 1
  (cd "$ROOT/reactnative" && npx tsc --noEmit >"$OUT/rn-tsc.log" 2>&1) || { echo "tsc failed: see $OUT/rn-tsc.log"; return 1; }
}
unit_rn_android() { unit_rn; }
unit_rn_ios() { unit_rn; }

smoke_rn_android() {
  local serial; serial="$(ensure_android)" || { echo "no emulator"; return 1; }
  local pkg=ai.bitdrift.rn.shop out="$OUT/rn-android-smoke.jsonl" act
  start_collector "$out"
  (cd "$ROOT/reactnative" && bash scripts/android-3-start-app.sh >"$OUT/rn-android-start.log" 2>&1) \
    || { kill "$COLLECTOR_PID" 2>/dev/null; echo "build/launch failed: see $OUT/rn-android-start.log"; return 1; }
  act="$(adb -s "$serial" shell cmd package resolve-activity --brief "$pkg" | tail -1 | tr -d '\r')"
  await_collector "adb -s $serial shell am start -S -n $act" || { echo "collector: $(cat "$OUT/collector.log")"; return 1; }
  "$PY" "$ROOT/tools/conformance/conformance.py" --platform reactnative --runs "$SIM_RUNS" --persona "$PERSONA" --seed "$SIM_SEED" "$out"
}

smoke_rn_ios() {
  local udid; udid="$(ensure_ios)" || { echo "no simulator"; return 1; }
  local bundle=ai.bitdrift.rn.shop out="$OUT/rn-ios-smoke.jsonl"
  start_collector "$out"
  (cd "$ROOT/reactnative" && bash scripts/ios-3-start-app.sh >"$OUT/rn-ios-start.log" 2>&1) \
    || { kill "$COLLECTOR_PID" 2>/dev/null; echo "build/launch failed: see $OUT/rn-ios-start.log"; return 1; }
  await_collector "xcrun simctl launch --terminate-running-process $udid $bundle" || { echo "collector: $(cat "$OUT/collector.log")"; return 1; }
  "$PY" "$ROOT/tools/conformance/conformance.py" --platform reactnative --runs "$SIM_RUNS" --persona "$PERSONA" --seed "$SIM_SEED" "$out"
}

unit_flutter() {
  unit_common || return 1
  (cd "$ROOT/flutter" && flutter analyze --no-fatal-infos --no-fatal-warnings >"$OUT/flutter-analyze.log" 2>&1) \
    || { echo "flutter analyze found errors: see $OUT/flutter-analyze.log"; return 1; }
  (cd "$ROOT/flutter" && flutter test >"$OUT/flutter-test.log" 2>&1) || { echo "flutter test failed: see $OUT/flutter-test.log"; return 1; }
}
unit_flutter_android() { unit_flutter; }
unit_flutter_ios() { unit_flutter; }

smoke_flutter_android() {
  local serial; serial="$(ensure_android)" || { echo "no emulator"; return 1; }
  local out="$OUT/flutter-android-smoke.jsonl"
  start_collector "$out"
  (cd "$ROOT/flutter" && BDSHOP_HARNESS=1 LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 bash scripts/android-3-start-app.sh >"$OUT/flutter-android-start.log" 2>&1) \
    || { kill "$COLLECTOR_PID" 2>/dev/null; echo "build/launch failed: see $OUT/flutter-android-start.log"; return 1; }
  await_collector "adb -s $serial shell am start -S -n ai.bitdrift.shop.flutter/.MainActivity" || { echo "collector: $(cat "$OUT/collector.log")"; return 1; }
  "$PY" "$ROOT/tools/conformance/conformance.py" --platform flutter --runs "$SIM_RUNS" --persona "$PERSONA" --seed "$SIM_SEED" "$out"
}

smoke_flutter_ios() {
  local udid; udid="$(ensure_ios)" || { echo "no simulator"; return 1; }
  local out="$OUT/flutter-ios-smoke.jsonl"
  start_collector "$out"
  (cd "$ROOT/flutter" && BDSHOP_HARNESS=1 LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 bash scripts/ios-3-start-app.sh >"$OUT/flutter-ios-start.log" 2>&1) \
    || { kill "$COLLECTOR_PID" 2>/dev/null; echo "build/launch failed: see $OUT/flutter-ios-start.log"; return 1; }
  await_collector "xcrun simctl launch --terminate-running-process $udid io.bitdrift.bitdriftShopFlutter" || { echo "collector: $(cat "$OUT/collector.log")"; return 1; }
  "$PY" "$ROOT/tools/conformance/conformance.py" --platform flutter --runs "$SIM_RUNS" --persona "$PERSONA" --seed "$SIM_SEED" "$out"
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
passed=()
for a in "${apps[@]}"; do
  if run_app "$a" "$tier"; then passed+=("$a"); else rc=1; fi
done
# Same persona + seed => the journey records must be identical across apps (Phase 4).
if [[ "$tier" == smoke && ${#passed[@]} -gt 1 ]]; then
  files=()
  for a in "${passed[@]}"; do [[ -f "$OUT/$a-smoke.jsonl" ]] && files+=("$OUT/$a-smoke.jsonl"); done
  if (( ${#files[@]} > 1 )); then
    if "$PY" "$ROOT/tools/conformance/conformance.py" --diff "${files[@]}"; then echo "PASS  cross-app journey diff (${#files[@]} apps)"
    else echo "FAIL  cross-app journey diff"; rc=1; fi
  fi
fi
exit $rc
