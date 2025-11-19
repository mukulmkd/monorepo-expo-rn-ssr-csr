#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$FRAMEWORK_DIR/build"
DIST_DIR="$FRAMEWORK_DIR/dist"
FRAMEWORK_NAME="ModuleProductsFramework"

echo "📦 Building xcframework for $FRAMEWORK_NAME"

# Clean previous builds
rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$DIST_DIR"

# Step 1: Bundle JavaScript first
echo "🔨 Step 1/3: Bundling JavaScript..."
cd "$FRAMEWORK_DIR"
./scripts/bundle.sh

# Step 2: Build xcframework using xcodebuild
echo "🔨 Step 2/3: Building xcframework..."

# Note: For SPM packages, we need to create an Xcode project first
# Or we can build the framework directly using swift build
# For now, we'll create a simple build script that packages the framework

# Create framework structure
FRAMEWORK_OUTPUT="$DIST_DIR/$FRAMEWORK_NAME.framework"
rm -rf "$FRAMEWORK_OUTPUT"
mkdir -p "$FRAMEWORK_OUTPUT/Resources"
mkdir -p "$FRAMEWORK_OUTPUT/Headers"

# Copy bundle to framework
cp "$FRAMEWORK_DIR/Resources/module-products.bundle" "$FRAMEWORK_OUTPUT/Resources/"

# Create Info.plist
cat > "$FRAMEWORK_OUTPUT/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$FRAMEWORK_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.yourorg.$FRAMEWORK_NAME</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$FRAMEWORK_NAME</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>MinimumOSVersion</key>
    <string>14.0</string>
</dict>
</plist>
EOF

# For a proper xcframework, we'd need to compile the Swift code
# This is a simplified version - in production, you'd use xcodebuild
# to create proper frameworks for device and simulator

echo "⚠️  Note: This creates a basic framework structure."
echo "   For production, use Xcode to build proper xcframework with:"
echo "   xcodebuild -create-xcframework ..."
echo ""
echo "✅ Framework structure created at $FRAMEWORK_OUTPUT"

