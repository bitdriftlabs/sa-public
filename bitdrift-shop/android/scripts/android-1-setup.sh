#!/usr/bin/env bash
# Set up the Android SDK command-line tooling and an emulator AVD — no Android
# Studio. Installs cmdline-tools if missing, accepts licenses, ensures the
# packages this app needs (compileSdk/targetSdk 36, see app/build.gradle.kts),
# and creates an AVD. Idempotent.
#
# Mirrors ../../flutter/scripts/android-1-setup.sh, adjusted for this app's
# own SDK levels and device profile (Medium Phone, 1080x2400 — watchdog.sh's
# touch coordinates are calibrated for that resolution, see
# README-refs.md#emulator-requirements).
#
# AVD_NAME default was "bitdrift_shop" (shared with the Flutter script on
# purpose, so both apps' APKs could install on one shared AVD) until that AVD
# hit an unresolved boot failure (HVF/mprotect issues on macOS 26, reproduced
# in Android Studio too) and got deleted. Now defaults to
# "Medium_Phone_Control", one of Android Studio's own default AVDs, confirmed
# to boot on this machine -- if it doesn't already exist, this script creates
# it same as before; no longer shares a default with Flutter's scripts unless
# those get updated too.
set -euo pipefail

SDK_DIR="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
AVD_NAME="${AVD_NAME:-Medium_Phone_Control}"
DEVICE_PROFILE="${DEVICE_PROFILE:-medium_phone}"
CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-mac-11076708_latest.zip"

mkdir -p "$SDK_DIR/cmdline-tools"

# 1. cmdline-tools (sdkmanager / avdmanager) — only if missing. Google's
#    distributed archive only ships sdkmanager/avdmanager/etc.; it does not
#    include a unified `android` binary, so check for sdkmanager here.
if [[ ! -x "$SDK_DIR/cmdline-tools/latest/bin/sdkmanager" ]]; then
  echo "Installing Android cmdline-tools into $SDK_DIR/cmdline-tools ..."
  TMP="$(mktemp -d)"
  curl -fsSL -o "$TMP/clt.zip" "$CMDLINE_TOOLS_URL"
  unzip -q -o "$TMP/clt.zip" -d "$TMP"
  rm -rf "$SDK_DIR/cmdline-tools/latest"
  mv "$TMP/cmdline-tools" "$SDK_DIR/cmdline-tools/latest"
  rm -rf "$TMP"
fi

export PATH="$SDK_DIR/cmdline-tools/latest/bin:$SDK_DIR/platform-tools:$PATH"

# 2. JDK — sdkmanager and the Gradle build both need one (17+ for this
#    project's jvmTarget). Android Studio normally provides this; on a
#    CLI-only machine it must already be installed.
if ! command -v java >/dev/null 2>&1; then
  echo "ERROR: no JDK found on PATH. Install JDK 17+ first, e.g.:" >&2
  echo "  brew install openjdk@17" >&2
  echo "then re-run this script." >&2
  exit 1
fi
echo "JDK: $(java -version 2>&1 | head -1)"

# 3. Accept SDK licenses (needed before installing / building anything).
echo "Accepting SDK licenses ..."
yes 2>/dev/null | sdkmanager --licenses >/dev/null || true

# 4. Ensure the packages this app's Gradle build needs (compileSdk/targetSdk
#    36 — see app/build.gradle.kts).
echo "Ensuring SDK packages ..."
sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0" "emulator"

# 5. Pick an installed arm64 Google-Play image, or install the standard one.
find_image() {
  local d
  for d in "$SDK_DIR"/system-images/*/google_apis_playstore/arm64-v8a; do
    if [[ -f "$d/system.img" ]]; then
      local api
      api="$(basename "$(dirname "$(dirname "$d")")")"
      echo "system-images;$api;google_apis_playstore;arm64-v8a"
      return 0
    fi
  done
  return 1
}

if IMG="$(find_image)"; then
  echo "Using installed system image: $IMG"
else
  echo "No installed arm64 image found; installing android-36 ..."
  sdkmanager "system-images;android-36;google_apis_playstore;arm64-v8a"
  IMG="system-images;android-36;google_apis_playstore;arm64-v8a"
fi

# 6. Create the AVD if it does not exist. Falls back to pixel_7 if this SDK
#    tools version doesn't know the "medium_phone" device id yet.
if avdmanager list avd | grep -q "^Name: $AVD_NAME$"; then
  echo "AVD '$AVD_NAME' already exists."
else
  if ! avdmanager list device | grep -q "id: .*or \"$DEVICE_PROFILE\""; then
    echo "Device profile '$DEVICE_PROFILE' not found in this SDK tools version; falling back to pixel_7." >&2
    DEVICE_PROFILE="pixel_7"
  fi
  echo "Creating AVD '$AVD_NAME' ($DEVICE_PROFILE) from: $IMG"
  avdmanager create avd -n "$AVD_NAME" -k "$IMG" -d "$DEVICE_PROFILE" --force
fi

echo
echo "Done. To boot it: bash scripts/android-2-start-emulator.sh"
