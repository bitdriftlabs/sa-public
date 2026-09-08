#!/usr/bin/env bash
# Install the Flutter SDK from git (no Android Studio, no brew).
# Idempotent: skips the clone if Flutter is already present.
set -euo pipefail

FLUTTER_DIR="${FLUTTER_DIR:-$HOME/development/flutter}"
BRANCH="${FLUTTER_BRANCH:-stable}"

if [[ -x "$FLUTTER_DIR/bin/flutter" ]]; then
  echo "Flutter already present at: $FLUTTER_DIR"
else
  echo "Cloning Flutter ($BRANCH) into: $FLUTTER_DIR"
  git clone --depth 1 -b "$BRANCH" https://github.com/flutter/flutter "$FLUTTER_DIR"
fi

export PATH="$FLUTTER_DIR/bin:$PATH"

echo
echo "Add this to your shell profile so 'flutter' is on PATH in new terminals:"
echo "  export PATH=\"$FLUTTER_DIR/bin:\$PATH\""
echo
echo "Running 'flutter doctor' (this also downloads the Dart SDK on first run)..."
flutter doctor
echo
echo "Done. Flutter is at: $FLUTTER_DIR"
