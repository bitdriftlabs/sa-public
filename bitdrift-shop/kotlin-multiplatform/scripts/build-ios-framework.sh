#!/bin/bash
# Generates the Shared.framework for iOS from the KMP shared module.
# Run this from the kotlin-multiplatform directory before opening the Xcode project.

set -e

cd "$(dirname "$0")/.."

export JAVA_HOME="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"

echo "=== Building Shared framework for iOS Simulator ==="
./gradlew :shared:linkDebugFrameworkIosSimulatorArm64

FRAMEWORK_PATH="shared/build/bin/iosSimulatorArm64/debugFramework/Shared.framework"

if [ -d "$FRAMEWORK_PATH" ]; then
    echo "✅ Framework built successfully at: $FRAMEWORK_PATH"
    echo ""
    echo "To use in Xcode:"
    echo "  1. Open iosApp/iosApp.xcodeproj"
    echo "  2. Add the framework search path: \$(SRCROOT)/../shared/build/bin/iosSimulatorArm64/debugFramework"
    echo "  3. Link Shared.framework in Build Phases"
else
    echo "❌ Framework build failed"
    exit 1
fi
