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

########################################
# Helpers (define early for use in validation)
########################################
log(){ echo -e "\n==> $*\n"; }
err(){ echo -e "\n‼️ ERROR: $*\n" >&2; }
warn(){ echo -e "\n⚠️  WARNING: $*\n"; }

# Parse environment variables (required - no hardcoded fallbacks)
# Usage: MODULE_NAME=<name> MODULE_PACKAGE=<package> MODULE_COMPONENT=<component> [REGISTRY_VERSION=<version>] ./script.sh

if [ -z "${MODULE_NAME:-}" ] || [ -z "${MODULE_PACKAGE:-}" ] || [ -z "${MODULE_COMPONENT:-}" ]; then
  err "Missing required environment variables!"
  err ""
  err "Usage:"
  err "  MODULE_NAME=<name> MODULE_PACKAGE=<package> MODULE_COMPONENT=<component> [REGISTRY_VERSION=<version>] $0"
  err ""
  err "Example:"
  err "  MODULE_NAME=products MODULE_PACKAGE=@app/module-products MODULE_COMPONENT=ModuleProducts REGISTRY_VERSION=latest $0"
  err ""
  err "Required variables:"
  err "  MODULE_NAME      - Module name (e.g., 'products', 'cart', 'pdp')"
  err "  MODULE_PACKAGE   - NPM package name (e.g., '@app/module-products')"
  err "  MODULE_COMPONENT - React component name (e.g., 'ModuleProducts')"
  err ""
  err "Optional variables:"
  err "  REGISTRY_VERSION - Version to fetch from registry (default: 'latest')"
  exit 1
fi

# Use environment variables directly
MODULE_NAME="${MODULE_NAME}"
MODULE_PACKAGE="${MODULE_PACKAGE}"
MODULE_COMPONENT="${MODULE_COMPONENT}"
REGISTRY_VERSION="${REGISTRY_VERSION:-latest}"

log "Module configuration:"
log "  MODULE_NAME=$MODULE_NAME"
log "  MODULE_PACKAGE=$MODULE_PACKAGE"
log "  MODULE_COMPONENT=$MODULE_COMPONENT"
log "  REGISTRY_VERSION=$REGISTRY_VERSION"

# Configuration
# MODULE_COMPONENT is already set in the case statement above (e.g., "ModuleProducts", "ModuleCart", "ModulePDP")
# Convert module name to proper case for SPM naming
MODULE_NAME_UPPER=$(echo "$MODULE_NAME" | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}')
PACKAGE_NAME="MKDRNModule${MODULE_NAME_UPPER}SPM"  # MKDRNModuleProductsSPM, MKDRNModuleCartSPM, etc.
FRAMEWORK_NAME="${MODULE_COMPONENT}Framework"  # ModuleProductsFramework, ModuleCartFramework, etc. (for Swift class names)
FRAMEWORK_DIR="${MONOREPO_ROOT}/frameworks/ios/${PACKAGE_NAME}"
BUILD_DIR="${FRAMEWORK_DIR}/build"
DIST_DIR="${FRAMEWORK_DIR}/dist"
# Resources should be inside Sources directory (SPM convention)
SOURCES_DIR="${FRAMEWORK_DIR}/Sources/${PACKAGE_NAME}"
RESOURCES_DIR="${SOURCES_DIR}/Resources"
BUNDLE_FILE="${RESOURCES_DIR}/module-${MODULE_NAME}.bundle"

# Temporary npm environment for bundling (only used if module not in monorepo)
TEMP_NPM_DIR="${BUILD_DIR}/npm-env"

# Verdaccio configuration
VERDACCIO_URL="http://localhost:4873"

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

# Always try Verdaccio first (primary source)
log "  Installing module from Verdaccio..."
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

MODULE_INSTALL_DIR="$TEMP_NPM_DIR/node_modules/@app/module-${MODULE_NAME}"
if [ -d "$MODULE_INSTALL_DIR" ] && [ -f "${MODULE_INSTALL_DIR}/index.js" ]; then
  # Successfully installed from Verdaccio
  MODULE_DIR="$MODULE_INSTALL_DIR"
  MODULE_ENTRY="${MODULE_DIR}/index.js"
  log "  ✅ Module installed from Verdaccio: $MODULE_DIR"
else
  # Fallback: Use monorepo if Verdaccio installation failed
  log "  ⚠️  Module not found in Verdaccio, falling back to monorepo..."
  
  if [ -d "$MODULE_APP_DIR" ] && [ -f "${MODULE_APP_DIR}/index.js" ]; then
    # Ensure absolute paths
    MODULE_DIR="$MODULE_APP_DIR"
    MODULE_ENTRY="${MODULE_DIR}/index.js"
    
    # Use monorepo's react-native directly
    if [ ! -d "$MONOREPO_NODE_MODULES/react-native" ]; then
      err "react-native not found in monorepo node_modules"
      err "Please run: npm install"
      exit 1
    fi
    
    log "  ✅ Module found in monorepo (fallback): $MODULE_DIR"
  else
    err "Module $MODULE_PACKAGE not found in Verdaccio and not available in monorepo"
    err "Verdaccio installation directory: $MODULE_INSTALL_DIR"
    err "Monorepo directory: $MODULE_APP_DIR"
    err ""
    err "Please ensure:"
    err "  1. Module is published to Verdaccio: npm run verdaccio:publish-all"
    err "  2. Or module exists in monorepo: apps/module-${MODULE_NAME}/"
    exit 1
  fi
fi

# Ensure Resources directory exists
mkdir -p "$RESOURCES_DIR"

# Bundle JavaScript
log "  Bundling JavaScript for iOS..."

# Verify entry file exists (should already be absolute from above)
if [ ! -f "$MODULE_ENTRY" ]; then
  err "Entry file not found: $MODULE_ENTRY"
  err "Module directory: $MODULE_DIR"
  err "Please ensure the module is properly installed or published to Verdaccio"
  exit 1
fi

# Ensure entry file is absolute (safety check)
if [[ "$MODULE_ENTRY" != /* ]]; then
  err "Internal error: MODULE_ENTRY should be absolute but is relative: $MODULE_ENTRY"
  exit 1
fi

# Ensure bundle output directory exists
mkdir -p "$(dirname "$BUNDLE_FILE")"

# Change to monorepo root for Metro bundling
cd "$MONOREPO_ROOT"

# Find Metro config (use module's config if available, then monorepo root)
METRO_CONFIG=""
if [ -f "${MODULE_DIR}/metro.config.js" ]; then
  METRO_CONFIG="--config ${MODULE_DIR}/metro.config.js"
  log "  Using Metro config: ${MODULE_DIR}/metro.config.js"
elif [ -f "${MONOREPO_ROOT}/metro.config.js" ]; then
  METRO_CONFIG="--config ${MONOREPO_ROOT}/metro.config.js"
  log "  Using Metro config: ${MONOREPO_ROOT}/metro.config.js"
else
  warn "No Metro config found, using default Metro configuration"
fi

# Use react-native CLI - check for required dependencies
# React Native CLI requires @react-native-community/cli and @react-native/metro-config
REACT_NATIVE_CLI="${MONOREPO_NODE_MODULES}/.bin/react-native"
REACT_NATIVE_CLI_PKG="${MONOREPO_NODE_MODULES}/@react-native-community/cli"
REACT_NATIVE_METRO_CONFIG="${MONOREPO_NODE_MODULES}/@react-native/metro-config"

# Check and install missing dependencies
MISSING_DEPS=()
if [ ! -f "$REACT_NATIVE_CLI" ]; then
  MISSING_DEPS+=("react-native")
fi
if [ ! -d "$REACT_NATIVE_CLI_PKG" ]; then
  MISSING_DEPS+=("@react-native-community/cli")
fi
if [ ! -d "$REACT_NATIVE_METRO_CONFIG" ]; then
  MISSING_DEPS+=("@react-native/metro-config")
fi

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
  warn "  Missing React Native CLI dependencies: ${MISSING_DEPS[*]}"
  warn "  Note: These are optional peer dependencies of react-native"
  warn "  They may not be installed on all machines (depends on npm version/package manager)"
  warn "  Attempting to install missing dependencies..."
  cd "$MONOREPO_ROOT"
  
  # Install missing dependencies
  for dep in "${MISSING_DEPS[@]}"; do
    if [ "$dep" = "react-native" ]; then
      npm install --save-dev react-native@latest --legacy-peer-deps > /dev/null 2>&1 || true
    else
      npm install --save-dev "$dep@latest" --legacy-peer-deps > /dev/null 2>&1 || true
    fi
  done
  
  # Verify installations
  ALL_INSTALLED=true
  for dep in "${MISSING_DEPS[@]}"; do
    if [ "$dep" = "react-native" ] && [ ! -f "$REACT_NATIVE_CLI" ]; then
      ALL_INSTALLED=false
    elif [ "$dep" = "@react-native-community/cli" ] && [ ! -d "$REACT_NATIVE_CLI_PKG" ]; then
      ALL_INSTALLED=false
    elif [ "$dep" = "@react-native/metro-config" ] && [ ! -d "$REACT_NATIVE_METRO_CONFIG" ]; then
      ALL_INSTALLED=false
    fi
  done
  
  if [ "$ALL_INSTALLED" = true ]; then
    log "  ✅ All React Native CLI dependencies installed successfully"
  else
    warn "  Some dependencies could not be installed automatically"
    warn "  The script will continue, but bundling may fail"
    warn "  Please install manually: npm install --save-dev ${MISSING_DEPS[*]}"
  fi
fi

# Always use npx to ensure proper dependency resolution
REACT_NATIVE_CLI="npx --yes react-native"
log "  Using npx react-native (ensures proper dependency resolution)"

log "  Entry point: $MODULE_ENTRY"
log "  Bundle output: $BUNDLE_FILE"
log "  Assets destination: $RESOURCES_DIR"

# Bundle with optimizations:
# - No --reset-cache: Uses Metro cache (much faster on subsequent runs)
# - Uses monorepo's node_modules for faster resolution
log "  Bundling (this may take a minute, Metro cache will speed up subsequent runs)..."

# Run bundle command and capture both stdout and stderr
# Temporarily disable exit on error to capture exit code and output
set +e  # Temporarily disable exit on error to capture exit code
BUNDLE_OUTPUT=$($REACT_NATIVE_CLI bundle \
  --platform ios \
  --entry-file "$MODULE_ENTRY" \
  --bundle-output "$BUNDLE_FILE" \
  --assets-dest "$RESOURCES_DIR" \
  --dev false \
  --minify true \
  $METRO_CONFIG 2>&1)

BUNDLE_EXIT_CODE=$?
set -e  # Re-enable exit on error

# Show a summary of Metro output (last 10 lines) for visibility
if [ -n "$BUNDLE_OUTPUT" ]; then
  echo ""
  echo "Metro bundler output (last 10 lines):"
  echo "$BUNDLE_OUTPUT" | tail -n 10 | sed 's/^/  /'
  echo ""
fi

# Check if bundle was created
if [ ! -f "$BUNDLE_FILE" ]; then
  err "Bundle was not created: $BUNDLE_FILE"
  err "Metro bundler exit code: $BUNDLE_EXIT_CODE"
  err ""
  err "Full Metro bundler output:"
  echo "$BUNDLE_OUTPUT" | sed 's/^/  /'
  err ""
  err "Troubleshooting:"
  err "  1. Verify entry file exists: $MODULE_ENTRY"
  err "  2. Check Metro config: ${METRO_CONFIG:-"default"}"
  err "  3. Ensure react-native is installed: npm install"
  err "  4. Try running Metro manually to see detailed errors"
  exit 1
fi

# Check for errors in output even if bundle was created
if echo "$BUNDLE_OUTPUT" | grep -qiE "error|failed|cannot|unable"; then
  warn "Metro bundler reported warnings/errors (but bundle was created):"
  echo "$BUNDLE_OUTPUT" | grep -iE "error|failed|cannot|unable" | sed 's/^/  /' || true
fi

# Verify bundle is not empty
BUNDLE_SIZE=$(stat -f%z "$BUNDLE_FILE" 2>/dev/null || stat -c%s "$BUNDLE_FILE" 2>/dev/null || echo "0")
if [ "$BUNDLE_SIZE" -eq 0 ]; then
  err "Bundle file is empty: $BUNDLE_FILE"
  err "Metro bundler output:"
  echo "$BUNDLE_OUTPUT" | sed 's/^/  /'
  exit 1
fi

BUNDLE_SIZE_HUMAN=$(du -h "$BUNDLE_FILE" | cut -f1)
log "  ✅ Bundle created: $BUNDLE_FILE ($BUNDLE_SIZE_HUMAN)"

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
// React Native types are provided by MKDReactNativeRuntime SPM package
// The consuming app must add MKDReactNativeRuntime as a dependency

public class ${FRAMEWORK_NAME} {
    public static let shared = ${FRAMEWORK_NAME}()
    
    private var bridge: RCTBridge?
    
    private init() {}
    
    /// Gets the bundle URL for the ${MODULE_COMPONENT} module
    /// - Returns: The URL to the module-${MODULE_NAME}.bundle file
    public func getBundleURL() -> URL? {
        // Method 1: Try Bundle.module FIRST (SPM-specific, primary method for Swift Package Manager)
        // Bundle.module is the correct way to access resources in SPM packages
        if let bundleURL = Bundle.module.url(
            forResource: "module-${MODULE_NAME}",
            withExtension: "bundle"
        ) {
            return bundleURL
        }
        
        // Method 2: Try Bundle.module with path lookup
        if let bundlePath = Bundle.module.path(
            forResource: "module-${MODULE_NAME}",
            ofType: "bundle"
        ) {
            return URL(fileURLWithPath: bundlePath)
        }
        
        // Method 3: Check Bundle.module resource path directly
        if let resourcePath = Bundle.module.resourcePath {
            let bundlePath = "\\(resourcePath)/module-${MODULE_NAME}.bundle"
            if FileManager.default.fileExists(atPath: bundlePath) {
                return URL(fileURLWithPath: bundlePath)
            }
        }
        
        // Method 4: Try framework bundle (for non-SPM usage)
        let frameworkBundle = Bundle(for: type(of: self))
        if let bundlePath = frameworkBundle.path(
            forResource: "module-${MODULE_NAME}",
            ofType: "bundle"
        ) {
            return URL(fileURLWithPath: bundlePath)
        }
        
        // Method 5: Try framework bundle URL lookup
        if let bundleURL = frameworkBundle.url(
            forResource: "module-${MODULE_NAME}",
            withExtension: "bundle"
        ) {
            return bundleURL
        }
        
        // Method 6: Check framework bundle resource path directly
        if let resourcePath = frameworkBundle.resourcePath {
            let bundlePath = "\\(resourcePath)/module-${MODULE_NAME}.bundle"
            if FileManager.default.fileExists(atPath: bundlePath) {
                return URL(fileURLWithPath: bundlePath)
            }
        }
        
        // Method 7: Check main bundle (fallback for app-bundled resources)
        if let mainBundlePath = Bundle.main.path(
            forResource: "module-${MODULE_NAME}",
            ofType: "bundle"
        ) {
            return URL(fileURLWithPath: mainBundlePath)
        }
        
        // Method 8: Check main bundle resource path
        if let resourcePath = Bundle.main.resourcePath {
            let bundlePath = "\\(resourcePath)/module-${MODULE_NAME}.bundle"
            if FileManager.default.fileExists(atPath: bundlePath) {
                return URL(fileURLWithPath: bundlePath)
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
    /// - Note: Requires MKDReactNativeRuntime SPM package to be added to the consuming app
    public func createView(
        moduleName: String = "${MODULE_COMPONENT}",
        initialProperties: [String: Any]? = nil
    ) -> RCTRootView? {
        guard let bundleURL = getBundleURL() else {
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
    name: "${PACKAGE_NAME}",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "${PACKAGE_NAME}",
            targets: ["${PACKAGE_NAME}"]
        ),
    ],
    dependencies: [
        // React Native Runtime - required dependency
        // Path is relative to this package's location
                .package(path: "../MKDReactNativeRuntime")
    ],
    targets: [
        .target(
            name: "${PACKAGE_NAME}",
            dependencies: [
                // React Native types from MKDReactNativeRuntime
                .product(name: "MKDReactNativeRuntime", package: "MKDReactNativeRuntime"),
                .product(name: "React", package: "MKDReactNativeRuntime")
            ],
            path: "Sources/${PACKAGE_NAME}",
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

- MKDReactNativeRuntime SPM package must be added to the consuming app first
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
2. Navigate to: \`frameworks/ios/${PACKAGE_NAME}\`
3. Add to target

**Note:** This framework automatically depends on MKDReactNativeRuntime, so Xcode will resolve it automatically if MKDReactNativeRuntime is already added.

### 3. Use in Code

\`\`\`swift
import ${PACKAGE_NAME}
// React types are automatically available via MKDReactNativeRuntime dependency

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
echo "   1. Ensure MKDReactNativeRuntime SPM is generated first:"
echo "      npm run framework:ios:spm:runtime"
echo "   2. Add MKDReactNativeRuntime to Xcode first:"
echo "      File → Add Package Dependencies → Add Local..."
echo "      Navigate to: frameworks/ios/MKDReactNativeRuntime"
echo "   3. Add this framework to Xcode:"
echo "      File → Add Package Dependencies → Add Local..."
echo "      Navigate to: $FRAMEWORK_DIR"
echo "   4. Import in code: import ${PACKAGE_NAME}"
echo ""
########################################
# Cleanup temporary build directories
########################################
log "Cleaning up temporary build directories..."

# Remove build directory (temporary files from generation)
if [ -d "$BUILD_DIR" ]; then
  rm -rf "$BUILD_DIR"
  log "  ✅ Removed build directory"
fi

# Remove dist directory (temporary distribution files)
if [ -d "$DIST_DIR" ]; then
  rm -rf "$DIST_DIR"
  log "  ✅ Removed dist directory"
fi

echo ""
echo "✅ Framework ready for distribution!"
echo "   • React Native types automatically available via dependency"
echo "   • No manual header paths or linker settings needed"
echo ""

