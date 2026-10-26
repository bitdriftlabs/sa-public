#!/usr/bin/env bash
# Build the minified (R8) release variant, upload its ProGuard mapping to bitdrift so crash stacks
# deobfuscate, and optionally install it. Without the upload, release crashes show obfuscated frames
# like `a.b.c()` instead of `CartPricing.applyCoupon`.
#
#   ./scripts/release-build.sh              # build + upload mapping
#   ./scripts/release-build.sh --install    # ...and install on the attached emulator/device
#
# The upload needs your SDK key (BITDRIFT_SDK_KEY in .local.properties or the environment). The
# mapping is keyed by app id + versionName + versionCode, so the build you crash must match what was uploaded.
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

INSTALL=0
[[ "${1:-}" == "--install" ]] && INSTALL=1

# Same key resolution as app/build.gradle.kts: local.properties files first, then the environment.
prop() { { grep -hE "^$1=" local.properties .local.properties 2>/dev/null || true; } | head -1 | cut -d= -f2-; }
KEY="${BITDRIFT_SDK_KEY:-$(prop BITDRIFT_SDK_KEY)}"
HOST="${BITDRIFT_API_HOST:-$(prop BITDRIFT_API_HOST)}"
APP_ID="ai.bitdrift.shop"

./gradlew :app:assembleRelease --console=plain -q

MAPPING="app/build/outputs/mapping/release/mapping.txt"
[[ -f "$MAPPING" ]] || { echo "no mapping file at $MAPPING (is minification on?)" >&2; exit 1; }
# The build writes the real version into the output metadata.
META="app/build/outputs/apk/release/output-metadata.json"
VERSION_NAME="$(python3 -I -c "import json;print(json.load(open('$META'))['elements'][0]['versionName'])")"
VERSION_CODE="$(python3 -I -c "import json;print(json.load(open('$META'))['elements'][0]['versionCode'])")"

if [[ -z "$KEY" ]]; then
  echo "WARNING: BITDRIFT_SDK_KEY is not set: skipping the mapping upload, so release crashes will not deobfuscate." >&2
elif ! command -v bd >/dev/null; then
  echo "WARNING: bd CLI not found: skipping the mapping upload." >&2
else
  # bd wants the base domain (bitdrift.io); the SDK host is api.bitdrift.io.
  BASE=()
  [[ -n "$HOST" && "$HOST" != "api.bitdrift.io" ]] && BASE=(--base-domain "${HOST#api.}")
  echo "Uploading $MAPPING ($APP_ID $VERSION_NAME / $VERSION_CODE) ..."
  bd debug-files upload-proguard --app-id "$APP_ID" --app-version "$VERSION_NAME" --version-code "$VERSION_CODE" \
    --api-key "$KEY" ${BASE[@]+"${BASE[@]}"} "$MAPPING"
fi

if [[ "$INSTALL" -eq 1 ]]; then
  ./gradlew :app:installRelease --console=plain -q
  echo "Installed the release variant."
fi
