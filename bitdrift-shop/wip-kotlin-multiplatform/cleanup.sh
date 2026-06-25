#!/bin/bash
# Cleans build artifacts and caches from the KMP project.
# Safe to run anytime — only removes generated/cached files.

set -e
cd "$(dirname "$0")"

echo "=== Cleaning KMP project ==="

# Gradle clean (removes build/ dirs in all modules)
./gradlew clean 2>/dev/null && echo "✅ Gradle clean done" || echo "⚠️  Gradle clean skipped (daemon not available)"

# Kotlin metadata cache
rm -rf .kotlin/
echo "✅ Removed .kotlin/ cache"

# Gradle caches
rm -rf .gradle/
rm -rf androidApp/.gradle/
echo "✅ Removed .gradle/ caches"

# IDE project files for the androidApp subproject (not root)
rm -rf androidApp/.idea/
rm -rf androidApp/local.properties
echo "✅ Removed androidApp IDE files"

# Shared framework build output
rm -rf shared/build/
echo "✅ Removed shared/build/"

# Android build output
rm -rf androidApp/build/
echo "✅ Removed androidApp/build/"

# Root build output
rm -rf build/
echo "✅ Removed root build/"

# macOS junk
find . -name ".DS_Store" -delete 2>/dev/null
echo "✅ Removed .DS_Store files"

echo ""
echo "=== Cleanup complete ==="
echo "Next steps:"
echo "  Android: Open root project in Android Studio and sync"
echo "  iOS:     Run ./scripts/build-ios-framework.sh then open Xcode"
