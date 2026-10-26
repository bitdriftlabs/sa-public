# Shared adb driver for the Android and React Native (Android) host scripts.
# Caller sets PKG (and optionally ACTIVITY, default .MainActivity) before using the functions.

adb_setup() {
  local sdk="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
  export PATH="$sdk/platform-tools:$PATH"
}

# First attached device or emulator, or empty.
adb_serial() {
  adb devices | awk 'NR>1 && $2=="device"{print $1}' | head -n1 || true
}

# True when $PKG's activity is the resumed (foreground) one.
adb_is_foreground() {
  adb -s "$SERIAL" shell dumpsys activity activities 2>/dev/null | grep -q "mResumedActivity:.*$PKG"
}

# am start's own exit code is not reliable: it exits 0 even when it prints an on-device
# "Error: ..." (e.g. activity not found, ActivityManager busy). Check the output instead, and
# confirm the transition actually happened rather than assuming the adb call landed.
adb_go_foreground() {
  local out attempt
  for attempt in 1 2 3; do
    out="$(adb -s "$SERIAL" shell am start -n "$PKG/${ACTIVITY:-.MainActivity}" 2>&1)" || true
    [[ "$out" == *Error* ]] && echo "warning: am start reported: $out" >&2
    sleep 1
    adb_is_foreground && return 0
  done
  echo "warning: $PKG did not reach the foreground after $attempt attempts" >&2
  return 1
}

# Goes through ActivityManager directly instead of KEYCODE_HOME, which passes through the input
# dispatcher and can get dropped if focus/IME state is mid-transition.
adb_go_background() {
  local out attempt
  for attempt in 1 2 3; do
    out="$(adb -s "$SERIAL" shell am start -a android.intent.action.MAIN -c android.intent.category.HOME 2>&1)" || true
    [[ "$out" == *Error* ]] && echo "warning: am start (HOME) reported: $out" >&2
    sleep 1
    adb_is_foreground || return 0
  done
  echo "warning: $PKG still foreground after $attempt attempts to background it" >&2
  return 1
}
