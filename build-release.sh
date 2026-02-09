#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
PROJECT="$SCRIPT_DIR/MultiMonitorWebsite.xcodeproj"
XCODE_BUILD_DIR="$HOME/Library/Developer/Xcode/DerivedData/Build/Products/Release"
VERSION="${1:-2.0}"

echo "Building release configuration (version $VERSION)..."
echo ""

# Clean build directory
rm -rf "$BUILD_DIR/Release"
mkdir -p "$BUILD_DIR/Release/arm64"
mkdir -p "$BUILD_DIR/Release/x86_64"

# Build for Apple Silicon (arm64)
echo "=== Building for Apple Silicon (arm64) ==="
xcodebuild -project "$PROJECT" \
    -scheme MultiMonitorWebsite \
    -configuration Release \
    ARCHS="arm64" \
    ONLY_ACTIVE_ARCH=NO \
    clean build 2>&1 | grep -E "(BUILD|error:)" || true

cp -R "$XCODE_BUILD_DIR/MultiMonitorWebsite.saver" "$BUILD_DIR/Release/arm64/"

# Build for Intel (x86_64)
echo ""
echo "=== Building for Intel (x86_64) ==="
xcodebuild -project "$PROJECT" \
    -scheme MultiMonitorWebsite \
    -configuration Release \
    ARCHS="x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    clean build 2>&1 | grep -E "(BUILD|error:)" || true

cp -R "$XCODE_BUILD_DIR/MultiMonitorWebsite.saver" "$BUILD_DIR/Release/x86_64/"

# Verify architectures
echo ""
echo "=== Verifying builds ==="
echo "Apple Silicon:"
file "$BUILD_DIR/Release/arm64/MultiMonitorWebsite.saver/Contents/MacOS/MultiMonitorWebsite"
echo "Intel:"
file "$BUILD_DIR/Release/x86_64/MultiMonitorWebsite.saver/Contents/MacOS/MultiMonitorWebsite"

# Create DMGs
echo ""
echo "=== Creating DMGs ==="
cd "$BUILD_DIR/Release"

rm -f "MultiMonitorWebsite-$VERSION-AppleSilicon.dmg" "MultiMonitorWebsite-$VERSION-Intel.dmg"

hdiutil create -volname "MultiMonitorWebsite" \
    -srcfolder arm64 \
    -ov -format UDZO \
    "MultiMonitorWebsite-$VERSION-AppleSilicon.dmg"

hdiutil create -volname "MultiMonitorWebsite" \
    -srcfolder x86_64 \
    -ov -format UDZO \
    "MultiMonitorWebsite-$VERSION-Intel.dmg"

# Keep arm64 .saver for convenience, clean up the rest
mv "$BUILD_DIR/Release/arm64/MultiMonitorWebsite.saver" "$BUILD_DIR/Release/"
rm -rf "$BUILD_DIR/Release/arm64"
rm -rf "$BUILD_DIR/Release/x86_64"

echo ""
echo "=== Release build complete ==="
echo ""
ls -lh "$BUILD_DIR/Release/"*.dmg
echo ""
echo "Files:"
echo "  $BUILD_DIR/Release/MultiMonitorWebsite-$VERSION-AppleSilicon.dmg"
echo "  $BUILD_DIR/Release/MultiMonitorWebsite-$VERSION-Intel.dmg"
