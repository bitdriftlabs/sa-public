#!/usr/bin/env bash
# Verify/prepare the iOS toolchain. Unlike android-1-setup.sh, most of this
# cannot be automated: installing Xcode.app, accepting its license, and
# downloading simulator platforms all require interactive `sudo` prompts (or
# an App Store / developer.apple.com sign-in) and are surfaced here as
# instructions rather than run for you. What *can* be automated (CocoaPods)
# is installed automatically. Idempotent — re-run any time to check status.
set -euo pipefail

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
echo "== CocoaPods =="
if command -v pod >/dev/null 2>&1; then
  echo "✓ CocoaPods $(pod --version)"
else
  echo "Installing CocoaPods via Homebrew ..."
  brew install cocoapods
fi

echo
echo "== iOS Simulator runtime =="
if xcrun simctl list runtimes 2>/dev/null | grep -q "^iOS .*(available"; then
  xcrun simctl list runtimes | grep "^iOS .*(available"
else
  echo "✗ No iOS simulator runtime installed."
  echo "  Needs ~8.5 GB free disk space, then run: xcodebuild -downloadPlatform iOS"
  ok=0
fi

echo
if [[ "$ok" == "1" ]]; then
  echo "Done. To boot a simulator: bash scripts/ios-2-start-simulator.sh"
else
  echo "Some steps above need manual action before iOS builds will work."
  exit 1
fi
