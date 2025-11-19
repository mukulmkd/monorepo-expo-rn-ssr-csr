#!/bin/bash

# Common bundling utilities for both iOS and Android

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Verify Verdaccio is running
verify_verdaccio() {
    if ! curl -s http://localhost:4873 > /dev/null; then
        echo -e "${RED}❌ Error: Verdaccio is not running on http://localhost:4873${NC}"
        echo "   Please start Verdaccio: npm run verdaccio:start"
        exit 1
    fi
    echo -e "${GREEN}✅ Verdaccio is accessible${NC}"
}

# Setup isolated npm environment
setup_npm_env() {
    local temp_dir=$1
    local module_name=$2
    
    rm -rf "$temp_dir"
    mkdir -p "$temp_dir"
    
    # Create package.json
    cat > "$temp_dir/package.json" << EOF
{
  "name": "framework-bundle-temp",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "$module_name": "*"
  }
}
EOF

    # Configure npm to use Verdaccio
    cat > "$temp_dir/.npmrc" << EOF
@app:registry=http://localhost:4873
@pkg:registry=http://localhost:4873
registry=http://localhost:4873
EOF
    
    echo "$temp_dir"
}

# Install from Verdaccio
install_from_verdaccio() {
    local temp_dir=$1
    
    echo -e "${YELLOW}📦 Installing from Verdaccio...${NC}"
    cd "$temp_dir"
    npm install --legacy-peer-deps
    
    if [ ! -d "node_modules/@app" ] && [ ! -d "node_modules/@pkg" ]; then
        echo -e "${RED}❌ Error: Failed to install from Verdaccio${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Installed from Verdaccio${NC}"
}

# Create entry file
create_entry_file() {
    local entry_file=$1
    local module_name=$2
    local component_name=$3
    
    cat > "$entry_file" << EOF
import { AppRegistry } from "react-native";
import ${component_name} from "${module_name}";

AppRegistry.registerComponent("${component_name}", () => ${component_name});
EOF
}

# Bundle JavaScript
bundle_javascript() {
    local platform=$1          # "ios" or "android"
    local entry_file=$2
    local bundle_output=$3
    local assets_dest=$4
    
    echo -e "${YELLOW}📦 Bundling JavaScript for ${platform}...${NC}"
    
    npx react-native bundle \
        --platform "$platform" \
        --entry-file "$entry_file" \
        --bundle-output "$bundle_output" \
        --assets-dest "$assets_dest" \
        --dev false \
        --minify true \
        --reset-cache
    
    if [ ! -f "$bundle_output" ]; then
        echo -e "${RED}❌ Error: Bundle was not created${NC}"
        exit 1
    fi
    
    local bundle_size=$(du -h "$bundle_output" | cut -f1)
    echo -e "${GREEN}✅ Bundle created: $bundle_output ($bundle_size)${NC}"
}

