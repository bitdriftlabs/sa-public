#!/usr/bin/env bash
# Boot an iOS Simulator and open its GUI window (Simulator.app, or DeviceHub.app
# on Xcode 27+, which renamed/replaced it).
# Override the device with DEVICE_NAME=<name>; list options with:
#   xcrun simctl list devices available
#
# Mirrors ../../ios/scripts/ios-2-start-simulator.sh. Defaults to "iPhone 16e"
# — the model package.json's own `npm run ios` hardcodes via
# `--simulator 'iPhone 16e'` — but falls back to whatever iPhone simulator is
# actually installed if that model isn't available on this machine (it
# wasn't, as of this writing: Xcode had aged it out in favor of newer
# models). ios-3-start-app.sh always targets whichever simulator actually
# ends up booted by UDID, so a fallback here doesn't create a mismatch there.
#
# Every candidate (already-booted, named, and fallback) is filtered to
# MIN_IOS_VERSION (default 26.0, matching IPHONEOS_DEPLOYMENT_TARGET in
# ios/ShopDemoRN.xcodeproj) — a simulator running an older runtime can boot
# successfully here and then fail later at build or install time, which is
# a much more confusing place to discover the mismatch.
set -euo pipefail

DEVICE_NAME="${DEVICE_NAME:-iPhone 16e}"
MIN_IOS_VERSION="${MIN_IOS_VERSION:-26.0}"

# Prints "UDID Name" for every simulator (from `simctl list devices <$1>`,
# e.g. "available" or "booted") whose runtime is >= MIN_IOS_VERSION. Runtime
# versions are only known from the "-- iOS X.Y --" section header each device
# is listed under, so this has to track which section it's currently in.
list_eligible() {
  xcrun simctl list devices "$1" 2>/dev/null | awk -v min="$MIN_IOS_VERSION" '
    /^-- iOS [0-9.]+ --/ {
      split($3, v, "."); split(min, m, ".")
      ok = (v[1]+0 > m[1]+0) || (v[1]+0 == m[1]+0 && v[2]+0 >= m[2]+0)
      next
    }
    ok && match($0, /[0-9A-Fa-f]{8}-([0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}/) {
      udid = substr($0, RSTART, RLENGTH)
      name = $0
      sub(/^[[:space:]]*/, "", name)
      sub(/ \(.*/, "", name)
      print udid, name
    }
  '
}

# Already booted (and eligible)?
BOOTED_LINE="$(list_eligible booted | head -n1 || true)"
if [[ -n "$BOOTED_LINE" ]]; then
  echo "A simulator is already booted: ${BOOTED_LINE%% *}"
else
  # A simulator may be booted but on a runtime below MIN_IOS_VERSION — don't
  # reuse it (it would just fail later at build/install instead of here).
  ANY_BOOTED="$(xcrun simctl list devices booted | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' | head -n1 || true)"
  if [[ -n "$ANY_BOOTED" ]]; then
    echo "A simulator is booted ($ANY_BOOTED) but its runtime is below iOS $MIN_IOS_VERSION — booting a separate eligible one instead."
  fi

  UDID="$(list_eligible available | awk -v name="$DEVICE_NAME" '{ln=$0; sub(/^[0-9A-Fa-f-]+ /, "", ln); if (ln == name) { print $1; exit } }')"
  PICKED_NAME="$DEVICE_NAME"

  if [[ -z "$UDID" ]]; then
    # Fall back to any available, eligible iPhone simulator, since the
    # requested model may not exist on this machine's installed
    # platforms/Xcode version.
    FALLBACK_LINE="$(list_eligible available | grep " iPhone " | head -n1 || true)"
    if [[ -n "$FALLBACK_LINE" ]]; then
      UDID="${FALLBACK_LINE%% *}"
      PICKED_NAME="${FALLBACK_LINE#* }"
      echo "No eligible simulator named '$DEVICE_NAME' (iOS >= $MIN_IOS_VERSION) — falling back to '$PICKED_NAME'."
    fi
  fi

  if [[ -z "$UDID" ]]; then
    echo "No iPhone simulator running iOS $MIN_IOS_VERSION or newer is available." >&2
    echo "List options with: xcrun simctl list devices available" >&2
    echo "Install a platform with: xcodebuild -downloadPlatform iOS" >&2
    exit 1
  fi

  echo "Booting '$PICKED_NAME' ($UDID) ..."
  xcrun simctl boot "$UDID"
fi

# Xcode 27 renamed/replaced Simulator.app with DeviceHub.app (com.apple.dt.Devices) --
# try both, oldest-name-first, and only note the lack of a GUI if neither exists
# (e.g. a CLI-only Xcode install) -- the booted device is still usable either way.
open -a Simulator 2>/dev/null || open -a DeviceHub 2>/dev/null \
  || echo "(No Simulator/DeviceHub GUI available on this machine — the device is still booted and usable via simctl/xcodebuild.)"

echo "Simulator is up:"
xcrun simctl list devices booted
