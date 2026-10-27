#!/usr/bin/env bash
# Host-run checks for the Phase 6 app types (CartPricing, PromoBannerParser, CartJson): compiles
# them with JSON.swift and RealismTests/main.swift. No simulator, no Xcode.
set -euo pipefail

IOS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

swiftc -O -swift-version 5 -o "$TMP/realism-test" \
  "$IOS/BitdriftShop/CartPricing.swift" \
  "$IOS/BitdriftShop/PromoBannerParser.swift" \
  "$IOS/BitdriftShop/CartJson.swift" \
  "$IOS/BitdriftShop/JSON.swift" \
  "$IOS/RealismTests/main.swift"
"$TMP/realism-test"
