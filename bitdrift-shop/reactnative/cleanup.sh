#!/bin/bash

# Cleanup script for Shopping Demo (React Native SDK)
# Run this before committing to git to remove build artifacts

echo "Cleaning up build artifacts..."

# Remove node_modules
if [ -d "node_modules" ]; then
    echo "Removing node_modules..."
    rm -rf node_modules
fi

# Remove iOS build artifacts
if [ -d "ios/Pods" ]; then
    echo "Removing ios/Pods..."
    rm -rf ios/Pods
fi

if [ -f "ios/Podfile.lock" ]; then
    echo "Removing ios/Podfile.lock..."
    rm -f ios/Podfile.lock
fi

if [ -d "ios/build" ]; then
    echo "Removing ios/build..."
    rm -rf ios/build
fi

if [ -f "ios/.xcode.env.local" ]; then
    echo "Removing ios/.xcode.env.local..."
    rm -f ios/.xcode.env.local
fi

# Remove Xcode derived data for this project
if [ -d "ios/ShopDemoRN.xcworkspace/xcuserdata" ]; then
    echo "Removing Xcode user data..."
    rm -rf ios/ShopDemoRN.xcworkspace/xcuserdata
fi

if [ -d "ios/ShopDemoRN.xcodeproj/xcuserdata" ]; then
    rm -rf ios/ShopDemoRN.xcodeproj/xcuserdata
fi

if [ -d "ios/ShopDemoRN.xcodeproj/project.xcworkspace/xcuserdata" ]; then
    rm -rf ios/ShopDemoRN.xcodeproj/project.xcworkspace/xcuserdata
fi

# Remove Android build artifacts
if [ -d "android/build" ]; then
    echo "Removing android/build..."
    rm -rf android/build
fi

if [ -d "android/app/build" ]; then
    echo "Removing android/app/build..."
    rm -rf android/app/build
fi

if [ -d "android/.gradle" ]; then
    echo "Removing android/.gradle..."
    rm -rf android/.gradle
fi

if [ -d "android/.cxx" ]; then
    echo "Removing android/.cxx..."
    rm -rf android/.cxx
fi

if [ -d "android/app/.cxx" ]; then
    echo "Removing android/app/.cxx..."
    rm -rf android/app/.cxx
fi

# Remove iOS codegen build artifacts
if [ -d "ios/build" ]; then
    echo "Removing ios/build (codegen artifacts)..."
    rm -rf ios/build
fi

# Remove Metro bundler cache
if [ -d ".metro" ]; then
    echo "Removing Metro cache..."
    rm -rf .metro
fi

echo "Removing Metro temp caches..."
rm -rf /tmp/metro-* "${TMPDIR}"metro-* 2>/dev/null || true

# Remove temporary files
echo "Removing temporary files..."
find . -name "*.log" -type f -delete 2>/dev/null
find . -name ".DS_Store" -type f -delete 2>/dev/null

echo "Cleanup complete!"
echo ""
echo "To rebuild after cloning:"
echo "  cp .env.example .env  # then add your API key"
echo "  npm install"
echo "  cd ios && pod install && cd .."
echo "  echo \"export NODE_BINARY=\$(which node)\" > ios/.xcode.env.local"
echo "  ./start.sh ios  # or ./start.sh android"
