#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="$(dirname "$SCRIPT_DIR")"
MONOREPO_ROOT="$(cd "$FRAMEWORK_DIR/../../.." && pwd)"
SHARED_DIR="$MONOREPO_ROOT/frameworks/shared"
BUILD_DIR="$FRAMEWORK_DIR/build"
BUNDLE_OUTPUT="$FRAMEWORK_DIR/Resources/module-products.bundle"
ASSETS_DEST="$FRAMEWORK_DIR/Resources"

# Source shared utilities
source "$SHARED_DIR/bundle-utils.sh"

echo "📦 Bundling ModuleProducts for iOS..."

# Step 1: Verify Verdaccio
verify_verdaccio

# Step 2: Setup npm environment
TEMP_NPM_DIR="$BUILD_DIR/npm-env"
setup_npm_env "$TEMP_NPM_DIR" "@app/module-products"

# Step 3: Install from Verdaccio
install_from_verdaccio "$TEMP_NPM_DIR"

# Step 4: Create entry file
ENTRY_FILE="$BUILD_DIR/entry.js"
create_entry_file "$ENTRY_FILE" "@app/module-products" "ModuleProducts"

# Step 5: Ensure directories exist
mkdir -p "$(dirname "$BUNDLE_OUTPUT")"
mkdir -p "$ASSETS_DEST"

# Step 6: Bundle JavaScript
bundle_javascript "ios" "$ENTRY_FILE" "$BUNDLE_OUTPUT" "$ASSETS_DEST"

echo "✅ iOS bundle complete!"

