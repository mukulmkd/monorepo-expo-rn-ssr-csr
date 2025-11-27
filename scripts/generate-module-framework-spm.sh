#!/usr/bin/env bash
set -euo pipefail

########################################
# Module Framework SPM Generator
#
# Generates SPM packages (.xcframeworks) for React Native modules
# that are published to Verdaccio.
#
# Usage:
#   ./scripts/generate-module-framework-spm.sh <module-name>
#   Example: ./scripts/generate-module-framework-spm.sh products
#
# Module names: products, cart, pdp
#
# Workflow:
#   1. Fetch latest module from Verdaccio
#   2. Create JavaScript bundle
#   3. Build Swift framework
#   4. Create xcframework (device + simulator)
#   5. Package as SPM with bundle embedded
#
########################################

MONOREPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Module name parameter
MODULE_NAME="${1:-}"
if [ -z "$MODULE_NAME" ]; then
  echo "Usage: $0 <module-name>"
  echo "Module names: products, cart, pdp"
  exit 1
fi

# Normalize module name
case "$MODULE_NAME" in
  products|Products|PRODUCTS)
    MODULE_NAME="products"
    MODULE_PACKAGE="@app/module-products"
    MODULE_COMPONENT="ModuleProducts"
    ;;
  cart|Cart|CART)
    MODULE_NAME="cart"
    MODULE_PACKAGE="@app/module-cart"
    MODULE_COMPONENT="ModuleCart"
    ;;
  pdp|PDP|Pdp)
    MODULE_NAME="pdp"
    MODULE_PACKAGE="@app/module-pdp"
    MODULE_COMPONENT="ModulePDP"
    ;;
  *)
    echo "Error: Unknown module name: $MODULE_NAME"
    echo "Valid module names: products, cart, pdp"
    exit 1
    ;;
esac

# Configuration
# MODULE_COMPONENT is already set in the case statement above (e.g., "ModuleProducts", "ModuleCart", "ModulePDP")
FRAMEWORK_NAME="${MODULE_COMPONENT}Framework"  # ModuleProductsFramework, ModuleCartFramework, etc.
FRAMEWORK_DIR="${MONOREPO_ROOT}/frameworks/ios/${FRAMEWORK_NAME}"
BUILD_DIR="${FRAMEWORK_DIR}/build"
DIST_DIR="${FRAMEWORK_DIR}/dist"
# Resources should be inside Sources directory (SPM convention)
SOURCES_DIR="${FRAMEWORK_DIR}/Sources/${FRAMEWORK_NAME}"
RESOURCES_DIR="${SOURCES_DIR}/Resources"
BUNDLE_FILE="${RESOURCES_DIR}/module-${MODULE_NAME}.bundle"

# Temporary npm environment for bundling (only used if module not in monorepo)
TEMP_NPM_DIR="${BUILD_DIR}/npm-env"

# Verdaccio configuration
VERDACCIO_URL="http://localhost:4873"

########################################
# Helpers
########################################
log(){ echo -e "\n==> $*\n"; }
err(){ echo -e "\n‼️ ERROR: $*\n" >&2; }
warn(){ echo -e "\n⚠️  WARNING: $*\n"; }

########################################
# Validate environment
########################################
log "Validating environment..."

# Check Verdaccio is running
if ! curl -s "$VERDACCIO_URL" > /dev/null; then
  err "Verdaccio is not running on $VERDACCIO_URL"
  echo "   Please start Verdaccio: npm run verdaccio:start"
  exit 1
fi
log "✅ Verdaccio is accessible"

# Check module exists in Verdaccio
if ! npm view "$MODULE_PACKAGE" --registry "$VERDACCIO_URL" > /dev/null 2>&1; then
  err "Module $MODULE_PACKAGE not found in Verdaccio"
  echo "   Please publish the module: npm run verdaccio:publish-all"
  exit 1
fi
log "✅ Module $MODULE_PACKAGE found in Verdaccio"

# Check required tools
if ! command -v xcodebuild &> /dev/null; then
  err "xcodebuild not found. Please install Xcode Command Line Tools."
  exit 1
fi

if ! command -v npx &> /dev/null; then
  err "npx not found. Please install Node.js."
  exit 1
fi

########################################
# Ensure directory structure
########################################
log "Setting up directory structure..."

# Ensure frameworks/ios exists
FRAMEWORKS_DIR="${MONOREPO_ROOT}/frameworks"
FRAMEWORKS_IOS_DIR="${MONOREPO_ROOT}/frameworks/ios"

if [ ! -d "$FRAMEWORKS_DIR" ]; then
  log "Creating frameworks directory..."
  mkdir -p "$FRAMEWORKS_DIR"
fi

if [ ! -d "$FRAMEWORKS_IOS_DIR" ]; then
  log "Creating frameworks/ios directory..."
  mkdir -p "$FRAMEWORKS_IOS_DIR"
fi

# Create framework directory structure
mkdir -p "$FRAMEWORK_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$DIST_DIR"
mkdir -p "$RESOURCES_DIR"
mkdir -p "$SOURCES_DIR"

# Clean previous builds
rm -rf "$BUILD_DIR"/*
rm -rf "$DIST_DIR"/*

########################################
# Step 1: Fetch from Verdaccio and Bundle
########################################
log "Step 1: Fetching from Verdaccio and creating bundle..."

# Use monorepo's node_modules to avoid reinstalling everything
MONOREPO_NODE_MODULES="${MONOREPO_ROOT}/node_modules"
MODULE_APP_DIR="${MONOREPO_ROOT}/apps/module-${MODULE_NAME}"

# Check if module exists in monorepo (faster path)
if [ -d "$MODULE_APP_DIR" ] && [ -f "${MODULE_APP_DIR}/index.js" ]; then
  log "  Using module from monorepo (fast path - no npm install needed)..."
  MODULE_ENTRY="${MODULE_APP_DIR}/index.js"
  MODULE_DIR="$MODULE_APP_DIR"
  
  # Use monorepo's react-native directly
  if [ ! -d "$MONOREPO_NODE_MODULES/react-native" ]; then
    err "react-native not found in monorepo node_modules"
    err "Please run: npm install"
    exit 1
  fi
else
  # Fallback: Install from Verdaccio (slower)
  log "  Module not in monorepo, installing from Verdaccio..."
  rm -rf "$TEMP_NPM_DIR"
  mkdir -p "$TEMP_NPM_DIR"
  
  cat > "$TEMP_NPM_DIR/package.json" <<EOF
{
  "name": "framework-bundle-temp",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "$MODULE_PACKAGE": "*"
  }
}
EOF
  
  cat > "$TEMP_NPM_DIR/.npmrc" <<EOF
@app:registry=$VERDACCIO_URL
@pkg:registry=$VERDACCIO_URL
registry=$VERDACCIO_URL
EOF
  
  cd "$TEMP_NPM_DIR"
  npm install --legacy-peer-deps --no-save > /dev/null 2>&1
  
  if [ ! -d "node_modules/@app/module-${MODULE_NAME}" ]; then
    err "Failed to install $MODULE_PACKAGE from Verdaccio"
    exit 1
  fi
  
  MODULE_ENTRY="node_modules/@app/module-${MODULE_NAME}/index.js"
  MODULE_DIR="$TEMP_NPM_DIR/node_modules/@app/module-${MODULE_NAME}"
  
  if [ ! -f "$MODULE_ENTRY" ]; then
    err "Module entry point not found: $MODULE_ENTRY"
    exit 1
  fi
fi

# Ensure Resources directory exists
mkdir -p "$RESOURCES_DIR"

# Bundle JavaScript
log "  Bundling JavaScript for iOS..."
cd "$MONOREPO_ROOT"

# Find Metro config (use module's config if available)
METRO_CONFIG=""
if [ -f "${MODULE_DIR}/metro.config.js" ]; then
  METRO_CONFIG="--config ${MODULE_DIR}/metro.config.js"
elif [ -f "${MONOREPO_ROOT}/metro.config.js" ]; then
  METRO_CONFIG="--config ${MONOREPO_ROOT}/metro.config.js"
fi

# Use monorepo's react-native bundle command directly (faster than npx)
REACT_NATIVE_CLI="${MONOREPO_NODE_MODULES}/.bin/react-native"
if [ ! -f "$REACT_NATIVE_CLI" ]; then
  # Fallback to npx if not found
  REACT_NATIVE_CLI="npx --yes react-native"
fi

log "  Using entry point: $MODULE_ENTRY"

# Bundle with optimizations:
# - No --reset-cache: Uses Metro cache (much faster on subsequent runs)
# - Uses monorepo's node_modules for faster resolution
# - Reduced output for speed
log "  Bundling (this may take a minute, Metro cache will speed up subsequent runs)..."
$REACT_NATIVE_CLI bundle \
  --platform ios \
  --entry-file "$MODULE_ENTRY" \
  --bundle-output "$BUNDLE_FILE" \
  --assets-dest "$RESOURCES_DIR" \
  --dev false \
  --minify true \
  $METRO_CONFIG 2>&1 | grep -E "(error|Bundling|bundle)" || true

if [ ! -f "$BUNDLE_FILE" ]; then
  err "Bundle was not created: $BUNDLE_FILE"
  err "Check Metro bundler output above for errors"
  exit 1
fi

BUNDLE_SIZE=$(du -h "$BUNDLE_FILE" | cut -f1)
log "  ✅ Bundle created: $BUNDLE_FILE ($BUNDLE_SIZE)"

# Cleanup temp npm environment if used
if [ -d "$TEMP_NPM_DIR" ]; then
  rm -rf "$TEMP_NPM_DIR"
fi

########################################
# Step 2: Create Swift Framework Source
########################################
log "Step 2: Creating Swift framework source..."

# Ensure Sources directory structure
mkdir -p "${SOURCES_DIR}/include"

# Create Swift wrapper
cat > "${SOURCES_DIR}/${FRAMEWORK_NAME}.swift" <<EOF
import UIKit
import React
// React Native types are provided by ReactNativeRuntime SPM package
// The consuming app must add ReactNativeRuntime as a dependency

public class ${FRAMEWORK_NAME} {
    public static let shared = ${FRAMEWORK_NAME}()
    
    private var bridge: RCTBridge?
    
    private init() {}
    
    /// Gets the bundle URL for the ${MODULE_COMPONENT} module
    /// - Returns: The URL to the module-${MODULE_NAME}.bundle file
    public func getBundleURL() -> URL? {
        let frameworkBundle = Bundle(for: type(of: self))
        
        // SPM packages store resources in the module bundle
        // Try multiple resource lookup methods
        
        // Method 1: Direct resource lookup (SPM standard)
        if let bundlePath = frameworkBundle.path(
            forResource: "module-${MODULE_NAME}",
            ofType: "bundle"
        ) {
            return URL(fileURLWithPath: bundlePath)
        }
        
        // Method 2: Use url(forResource:withExtension:) - SPM's preferred method
        if let bundleURL = frameworkBundle.url(
            forResource: "module-${MODULE_NAME}",
            withExtension: "bundle"
        ) {
            return bundleURL
        }
        
        // Method 3: Check if it's in the bundle's resource path directly
        if let resourcePath = frameworkBundle.resourcePath {
            let bundlePath = "\\(resourcePath)/module-${MODULE_NAME}.bundle"
            if FileManager.default.fileExists(atPath: bundlePath) {
                return URL(fileURLWithPath: bundlePath)
            }
        }
        
        // Method 4: Check main bundle (fallback for when resources are copied to main bundle)
        if let mainBundlePath = Bundle.main.path(
            forResource: "module-${MODULE_NAME}",
            ofType: "bundle"
        ) {
            return URL(fileURLWithPath: mainBundlePath)
        }
        
        // Method 5: Check main bundle resource path
        if let resourcePath = Bundle.main.resourcePath {
            let bundlePath = "\\(resourcePath)/module-${MODULE_NAME}.bundle"
            if FileManager.default.fileExists(atPath: bundlePath) {
                return URL(fileURLWithPath: bundlePath)
            }
        }
        
        // Method 6: Try Bundle.module (Swift 5.3+ SPM resource access)
        if #available(iOS 14.0, *) {
            if let bundleURL = Bundle.module.url(
                forResource: "module-${MODULE_NAME}",
                withExtension: "bundle"
            ) {
                return bundleURL
            }
        }
        
        // Debug: Print available resources for troubleshooting
        print("🔍 Debug: Framework bundle path: \\(frameworkBundle.bundlePath)")
        print("🔍 Debug: Framework bundle identifier: \\(frameworkBundle.bundleIdentifier ?? "nil")")
        print("🔍 Debug: Framework bundle resource path: \\(frameworkBundle.resourcePath ?? "nil")")
        if let resourcePath = frameworkBundle.resourcePath {
            print("🔍 Debug: Resources in framework bundle:")
            if let resources = try? FileManager.default.contentsOfDirectory(atPath: resourcePath) {
                resources.forEach { print("     - \\($0)") }
            } else {
                print("     (could not list resources)")
            }
        }
        
        return nil
    }
    
    /// Gets the module name for the ${MODULE_COMPONENT} module
    /// - Returns: The registered module name ("${MODULE_COMPONENT}")
    public func getModuleName() -> String {
        return "${MODULE_COMPONENT}"
    }
    
    /// Creates a React Native root view for the module
    /// - Parameters:
    ///   - moduleName: The registered module name (default: "${MODULE_COMPONENT}")
    ///   - initialProperties: Optional initial props
    /// - Returns: A configured RCTRootView ready to be added to a view hierarchy
    /// - Note: Requires ReactNativeRuntime SPM package to be added to the consuming app
    public func createView(
        moduleName: String = "${MODULE_COMPONENT}",
        initialProperties: [String: Any]? = nil
    ) -> RCTRootView? {
        guard let bundleURL = getBundleURL() else {
            print("❌ ${FRAMEWORK_NAME}: Bundle not found")
            return nil
        }
        
        if bridge == nil {
            bridge = RCTBridge(bundleURL: bundleURL, moduleProvider: nil, launchOptions: nil)
        }
        
        guard let bridge = bridge else {
            return nil
        }
        
        let rootView = RCTRootView(
            bridge: bridge,
            moduleName: moduleName,
            initialProperties: initialProperties
        )
        
        rootView.backgroundColor = .white
        return rootView
    }
    
    /// Invalidates the bridge (call when done)
    public func invalidate() {
        bridge?.invalidate()
        bridge = nil
    }
}
EOF

# Create header file
cat > "${SOURCES_DIR}/include/${FRAMEWORK_NAME}.h" <<EOF
//
//  ${FRAMEWORK_NAME}.h
//  ${FRAMEWORK_NAME}
//
//  Generated SPM framework for ${MODULE_COMPONENT} module
//

#import <Foundation/Foundation.h>

//! Project version number for ${FRAMEWORK_NAME}.
FOUNDATION_EXPORT double ${FRAMEWORK_NAME}VersionNumber;

//! Project version string for ${FRAMEWORK_NAME}.
FOUNDATION_EXPORT const unsigned char ${FRAMEWORK_NAME}VersionString[];
EOF

########################################
# Step 3: Verify Bundle
########################################
log "Step 3: Verifying bundle..."

if [ ! -f "$BUNDLE_FILE" ]; then
  err "Bundle file not found: $BUNDLE_FILE"
  exit 1
fi

BUNDLE_SIZE=$(du -h "$BUNDLE_FILE" | cut -f1)
log "  ✅ Bundle verified: $BUNDLE_FILE ($BUNDLE_SIZE)"

# Note: xcframework will be created by Xcode when the SPM package is consumed
# SPM packages are built on-demand by Xcode, so we don't need to pre-build them

########################################
# Step 4: Create Package.swift
########################################
log "Step 4: Creating SPM Package.swift..."

# Ensure directory exists
mkdir -p "$(dirname "${FRAMEWORK_DIR}/Package.swift")"

cat > "${FRAMEWORK_DIR}/Package.swift" <<EOF
// swift-tools-version: 5.9
// ${FRAMEWORK_NAME} SPM Package
// Generated from ${MODULE_PACKAGE} published to Verdaccio
import PackageDescription

let package = Package(
    name: "${FRAMEWORK_NAME}",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "${FRAMEWORK_NAME}",
            targets: ["${FRAMEWORK_NAME}"]
        ),
    ],
    dependencies: [
        // React Native Runtime - required dependency
        // Path is relative to this package's location
        .package(path: "../ReactNativeRuntime")
    ],
    targets: [
        .target(
            name: "${FRAMEWORK_NAME}",
            dependencies: [
                // React Native types from ReactNativeRuntime
                .product(name: "ReactNativeRuntime", package: "ReactNativeRuntime"),
                .product(name: "React", package: "ReactNativeRuntime")
            ],
            path: "Sources/${FRAMEWORK_NAME}",
            resources: [
                .copy("Resources/module-${MODULE_NAME}.bundle")
            ],
            publicHeadersPath: "include"
        ),
    ]
)
EOF

########################################
# Step 5: Create README
########################################
log "Step 5: Creating README.md..."

cat > "${FRAMEWORK_DIR}/README.md" <<EOF
# ${FRAMEWORK_NAME}

iOS SPM framework for ${MODULE_COMPONENT} React Native module.

## Overview

This framework contains:
- Pre-bundled JavaScript code (module-${MODULE_NAME}.bundle)
- Swift wrapper API for easy integration
- No Verdaccio or npm required at runtime

## Prerequisites

- ReactNativeRuntime SPM package must be added to the consuming app first
- iOS 14.0+
- Xcode 14+

## Usage

### 1. Add ReactNativeRuntime First (Required)

In Xcode:
1. File → Add Package Dependencies → Add Local...
2. Navigate to: \`frameworks/ios/ReactNativeRuntime\`
3. Add to target

**Important:** ReactNativeRuntime must be added before this framework.

### 2. Add This Framework

In Xcode:
1. File → Add Package Dependencies → Add Local...
2. Navigate to: \`frameworks/ios/${FRAMEWORK_NAME}\`
3. Add to target

**Note:** This framework automatically depends on ReactNativeRuntime, so Xcode will resolve it automatically if ReactNativeRuntime is already added.

### 3. Use in Code

\`\`\`swift
import ${FRAMEWORK_NAME}
// React types are automatically available via ReactNativeRuntime dependency

// Option 1: Use convenience method (recommended)
if let rootView = ${FRAMEWORK_NAME}.shared.createView() {
    view.addSubview(rootView)
    rootView.frame = view.bounds
    rootView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
}

// Option 2: Manual setup (if you need more control)
let bundleURL = ${FRAMEWORK_NAME}.shared.getBundleURL()
let moduleName = ${FRAMEWORK_NAME}.shared.getModuleName()
let bridge = RCTBridge(bundleURL: bundleURL, moduleProvider: nil, launchOptions: nil)
let rootView = RCTRootView(bridge: bridge, moduleName: moduleName, initialProperties: nil)
view.addSubview(rootView)
\`\`\`

## API

- \`getBundleURL() -> URL?\` - Returns bundle file URL
- \`getModuleName() -> String\` - Returns registered module name
- \`createView(moduleName:initialProperties:) -> RCTRootView?\` - Creates React Native view
- \`invalidate()\` - Cleans up bridge

## Bundle

The JavaScript bundle is embedded in:
\`Resources/module-${MODULE_NAME}.bundle\`

This bundle was created from the latest version published to Verdaccio.

## Version

Generated from: ${MODULE_PACKAGE}
Source: Verdaccio registry
EOF

########################################
# Summary
########################################
log "🎉 SUCCESS! ${FRAMEWORK_NAME} SPM package generated"
echo ""
echo "📍 Location: $FRAMEWORK_DIR"
echo ""
echo "📦 Contents:"
echo "   • Package.swift"
echo "   • Sources/${FRAMEWORK_NAME}/${FRAMEWORK_NAME}.swift"
echo "   • Resources/module-${MODULE_NAME}.bundle ($BUNDLE_SIZE)"
echo "   • README.md"
echo ""
echo "📝 Next steps:"
echo "   1. Ensure ReactNativeRuntime SPM is generated first:"
echo "      npm run framework:ios:spm:runtime"
echo "   2. Add ReactNativeRuntime to Xcode first:"
echo "      File → Add Package Dependencies → Add Local..."
echo "      Navigate to: frameworks/ios/ReactNativeRuntime"
echo "   3. Add this framework to Xcode:"
echo "      File → Add Package Dependencies → Add Local..."
echo "      Navigate to: $FRAMEWORK_DIR"
echo "   4. Import in code: import ${FRAMEWORK_NAME}"
echo ""
echo "✅ Framework ready for distribution!"
echo "   • React Native types automatically available via dependency"
echo "   • No manual header paths or linker settings needed"
echo ""

