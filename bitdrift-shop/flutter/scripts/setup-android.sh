#!/usr/bin/env bash
# Set up the Android SDK command-line tooling and an emulator AVD — no Android
# Studio. Installs cmdline-tools if missing, accepts licenses, ensures the
# packages Flutter needs, and creates an AVD. Idempotent.
set -euo pipefail

SDK_DIR="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
AVD_NAME="${AVD_NAME:-bitdrift_shop}"
DEVICE_PROFILE="${DEVICE_PROFILE:-pixel_7}"
CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-mac-11076708_latest.zip"

mkdir -p "$SDK_DIR/cmdline-tools"

# 1. cmdline-tools (sdkmanager / avdmanager) — only if missing.
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

# 2. JDK — sdkmanager and the Gradle build both need one (21+ for this
#    project's jvmTarget). Android Studio normally provides this; on a
#    CLI-only machine it must already be installed.
if ! command -v java >/dev/null 2>&1; then
  echo "ERROR: no JDK found on PATH. Install JDK 21+ first, e.g.:" >&2
  echo "  brew install openjdk@21" >&2
  echo "then re-run this script." >&2
  exit 1
fi
echo "JDK: $(java -version 2>&1 | head -1)"

# 2. Accept SDK licenses (needed before installing / building anything).
echo "Accepting SDK licenses ..."
yes 2>/dev/null | sdkmanager --licenses >/dev/null || true

# 3. Ensure the packages Flutter's Android build needs.
echo "Ensuring SDK packages ..."
sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0" "emulator"

# 4. Pick an installed arm64 Google-Play image, or install the standard one.
find_image() {
  local d pkg
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

# 5. Create the AVD if it does not exist.
if avdmanager list avd | grep -q "^Name: $AVD_NAME$"; then
  echo "AVD '$AVD_NAME' already exists."
else
  echo "Creating AVD '$AVD_NAME' ($DEVICE_PROFILE) from: $IMG"
  avdmanager create avd -n "$AVD_NAME" -k "$IMG" -d "$DEVICE_PROFILE" --force
fi

echo
echo "Done. To boot it: bash scripts/start-emulator.sh"
