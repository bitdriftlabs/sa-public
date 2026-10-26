#!/usr/bin/env bash
# Host-run golden test for the shared journey engine: compiles JourneyEngine.swift (Foundation
# only) with the generated bundle and replays tools/journey/golden.json. No simulator, no Xcode.
set -euo pipefail

IOS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GOLDEN="$IOS/../tools/journey/golden.json"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

swiftc -O -swift-version 5 -o "$TMP/journey-engine-test" \
  "$IOS/BitdriftShop/JourneyEngine.swift" \
  "$IOS/BitdriftShop/Generated/SpecJourney.swift" \
  "$IOS/JourneyEngineTests/main.swift"
"$TMP/journey-engine-test" "$GOLDEN"
