#!/usr/bin/env bash
# Verify/prepare the iOS toolchain. Most of this cannot be automated:
# installing Xcode.app, accepting its license, and downloading simulator
# platforms all require interactive `sudo` prompts (or an App Store /
# developer.apple.com sign-in) and are surfaced here as instructions rather
# than run for you. What *can* be automated (CocoaPods, npm deps) is
# installed automatically. Idempotent — re-run any time to check status.
#
# Mirrors ../../ios/scripts/ios-1-setup.sh (native app), plus this project's
# own npm/CocoaPods/.env requirements (see ../start.sh, which this borrows
# the CocoaPods step from).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ok=1

echo "== Xcode =="
if ! xcode-select -p >/dev/null 2>&1; then
  echo "✗ Xcode command line tools not found. Install with: xcode-select --install"
  ok=0
else
  DEV_DIR="$(xcode-select -p)"
  if [[ "$DEV_DIR" == *CommandLineTools* ]]; then
    echo "✗ Active developer directory is Command Line Tools, not full Xcode:"
    echo "    $DEV_DIR"
    echo "  Install Xcode.app (App Store or developer.apple.com), then run:"
    echo "    sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer"
    echo "    sudo xcodebuild -runFirstLaunch"
    ok=0
  else
    echo "✓ Xcode developer directory: $DEV_DIR"
    if ! xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
      echo "✗ First-launch tasks (incl. license acceptance) not complete. Run:"
      echo "    sudo xcodebuild -runFirstLaunch"
      ok=0
    else
      echo "✓ License accepted / first-launch tasks complete."
    fi
  fi
fi

echo
echo "== npm dependencies =="
if [[ -d "$ROOT/node_modules" ]]; then
  echo "✓ node_modules present."
else
  echo "Installing npm dependencies ..."
  (cd "$ROOT" && npm install)
fi

echo
echo "== CocoaPods =="
if command -v pod >/dev/null 2>&1; then
  echo "✓ CocoaPods $(pod --version)"
  if [[ -d "$ROOT/ios/Pods" ]]; then
    echo "✓ ios/Pods present."
  else
    echo "Installing CocoaPods dependencies (--repo-update, so a newly bumped" \
      "BitdriftCapture version resolves) ..."
    (cd "$ROOT/ios" && pod install --repo-update)
  fi
else
  echo "✗ CocoaPods not found. Install with: sudo gem install cocoapods"
  ok=0
fi

if [[ ! -f "$ROOT/ios/.xcode.env.local" ]]; then
  echo "Writing ios/.xcode.env.local (NODE_BINARY) ..."
  echo "export NODE_BINARY=$(command -v node)" > "$ROOT/ios/.xcode.env.local"
fi

echo
echo "== iOS Simulator runtime =="
# `simctl list runtimes` marks unavailable entries with "(unavailable, ...)"
# but leaves normally-installed ones unmarked — so match "^iOS " lines and
# exclude the unavailable ones, rather than requiring a literal "(available".
if xcrun simctl list runtimes 2>/dev/null | grep "^iOS " | grep -qv "unavailable"; then
  xcrun simctl list runtimes | grep "^iOS " | grep -v "unavailable"
else
  echo "✗ No iOS simulator runtime installed."
  echo "  Needs ~8.5 GB free disk space, then run: xcodebuild -downloadPlatform iOS"
  ok=0
fi

echo
echo "== Credentials (.env) =="
if [[ -f "$ROOT/.env" ]] && grep -q "^BITDRIFT_SDK_KEY=" "$ROOT/.env" \
   && ! grep -q "^BITDRIFT_SDK_KEY=your_sdk_key_here$" "$ROOT/.env"; then
  echo "✓ .env exists and sets BITDRIFT_SDK_KEY."
else
  echo "✗ .env missing or has no real BITDRIFT_SDK_KEY."
  echo "  cp .env.example .env  # then add your SDK key"
  ok=0
fi

echo
if [[ "$ok" == "1" ]]; then
  echo "Done. To boot a simulator: bash scripts/ios-2-start-simulator.sh"
else
  echo "Some steps above need manual action before iOS builds will work."
  exit 1
fi
