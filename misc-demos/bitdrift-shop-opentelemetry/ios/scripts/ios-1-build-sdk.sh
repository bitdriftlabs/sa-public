#!/usr/bin/env bash
# Builds Capture.xcframework from a local capture-sdk checkout (default:
# /Users/slerner/Code/repos/capture-sdk, override with CAPTURE_SDK_DIR) and copies it into
# ../Frameworks/, ready for project.yml's local framework dependency.
#
# There is no "published SDK" toggle here (unlike the android/ app's Maven Central fallback) --
# this demo only ever links the local xcframework. See README.md "OTel span export" for why.
set -euo pipefail

CAPTURE_SDK_DIR="${CAPTURE_SDK_DIR:-/Users/slerner/Code/repos/capture-sdk}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(dirname "$SCRIPT_DIR")"

if [[ ! -d "$CAPTURE_SDK_DIR" ]]; then
  echo "capture-sdk checkout not found at $CAPTURE_SDK_DIR (set CAPTURE_SDK_DIR to override)" >&2
  exit 1
fi

echo "Building //:ios_dist in $CAPTURE_SDK_DIR ..."
(cd "$CAPTURE_SDK_DIR" && ./bazelw build //:ios_dist)

ZIP_PATH="$CAPTURE_SDK_DIR/bazel-bin/Capture.ios.zip"
if [[ ! -f "$ZIP_PATH" ]]; then
  echo "Expected build output not found: $ZIP_PATH" >&2
  exit 1
fi

rm -rf "$IOS_DIR/Frameworks/Capture.xcframework"
mkdir -p "$IOS_DIR/Frameworks"
unzip -q -o "$ZIP_PATH" -d "$IOS_DIR/Frameworks"

echo "Capture.xcframework updated at $IOS_DIR/Frameworks/Capture.xcframework"
echo "Re-run 'xcodegen generate' (or ./scripts/ios-2-generate-project.sh) if this is the first build."
