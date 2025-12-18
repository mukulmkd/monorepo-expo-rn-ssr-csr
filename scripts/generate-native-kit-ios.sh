#!/usr/bin/env bash
set -eo pipefail
# Note: 'u' flag removed to allow unbound variables in some edge cases
# We'll handle unbound variables explicitly where needed

########################################
# Native Kit Generator - iOS SPM
#
# Generates vsco-native-kit SPM (iOS) from native dependencies
# detected in modules published to Verdaccio.
#
# Usage:
#   ./scripts/generate-native-kit-ios.sh
#
# Workflow:
#   1. Install all modules from Verdaccio
#   2. Detect shared native dependencies from all modules
#   3. Install native packages from npm registry
#   4. Bundle iOS native code into vsco-native-kit
#   5. Update iOS Package.swift
#   6. Create iOS stub headers and fix imports
#
########################################

MONOREPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANDROID_PROPS_DIR="${MONOREPO_ROOT}/android-props"

########################################
# Helpers
########################################
log(){ echo -e "\n==> $*\n"; }
err(){ echo -e "\n‼️ ERROR: $*\n" >&2; }
warn(){ echo -e "\n⚠️  WARNING: $*\n"; }

# Configuration
VERDACCIO_URL="http://localhost:4873"
KIT_DIR="${MONOREPO_ROOT}/vsco-native-kit"
KIT_IOS_DIR="${KIT_DIR}/ios"
KIT_IOS_PACKAGE_DIR="${KIT_IOS_DIR}/VSCONativeKit"
TEMP_NPM_DIR="${MONOREPO_ROOT}/.tmp-native-kit-gen"
ROOT_PACKAGE_JSON="${MONOREPO_ROOT}/package.json"

########################################
# Cleanup function (called on exit)
########################################
cleanup() {
    local exit_code=$?
    if [ -d "$TEMP_NPM_DIR" ]; then
        log "Cleaning up temporary directories..."
        rm -rf "$TEMP_NPM_DIR"
        log "  ✅ Removed temporary npm environment"
    fi
    # Clean up any leftover test directories
    if [ -d "${MONOREPO_ROOT}/.tmp-ios-kit-test" ]; then
        rm -rf "${MONOREPO_ROOT}/.tmp-ios-kit-test"
        log "  ✅ Removed leftover test directory"
    fi
    if [ $exit_code -ne 0 ]; then
        err "Script failed with exit code $exit_code"
    fi
    exit $exit_code
}

# Register cleanup function to run on exit
trap cleanup EXIT

# Module packages to scan (from Verdaccio)
MODULE_PACKAGES=(
    "@app/module-cart"
    "@app/module-pdp"
    "@app/module-products"
)

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

# Check all modules exist in Verdaccio
log "  Checking modules in Verdaccio..."
for module_pkg in "${MODULE_PACKAGES[@]}"; do
  if ! npm view "$module_pkg" --registry "$VERDACCIO_URL" > /dev/null 2>&1; then
    err "Module $module_pkg not found in Verdaccio"
    err "   Please publish the module: npm run publish:verdaccio"
    exit 1
  fi
  log "  ✅ $module_pkg found"
done

# Check required tools
if ! command -v node &> /dev/null; then
  err "Node.js not found. Please install Node.js."
  exit 1
fi

if ! command -v npm &> /dev/null; then
  err "npm not found. Please install npm."
  exit 1
fi

# Ensure kit directory exists with full iOS structure
mkdir -p "$KIT_DIR"
mkdir -p "$KIT_IOS_DIR"
mkdir -p "$KIT_IOS_PACKAGE_DIR"
mkdir -p "$KIT_IOS_PACKAGE_DIR/Sources"
log "  ✅ Created iOS directory structure"

########################################
# Step 1: Install all modules from Verdaccio
########################################
log "Step 1: Installing all modules from Verdaccio..."

rm -rf "$TEMP_NPM_DIR"
mkdir -p "$TEMP_NPM_DIR"

# Create package.json with all modules
cat > "$TEMP_NPM_DIR/package.json" <<EOF
{
  "name": "native-kit-detection-temp",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "@app/module-cart": "*",
    "@app/module-pdp": "*",
    "@app/module-products": "*"
  }
}
EOF

cat > "$TEMP_NPM_DIR/.npmrc" <<EOF
@app:registry=$VERDACCIO_URL
@pkg:registry=$VERDACCIO_URL
registry=$VERDACCIO_URL
EOF

cd "$TEMP_NPM_DIR"
log "  Installing modules from Verdaccio (this may take a minute)..."
npm install --legacy-peer-deps --no-save > /dev/null 2>&1

# Verify installations
INSTALLED_MODULES=()
for module_pkg in "${MODULE_PACKAGES[@]}"; do
  module_name=$(echo "$module_pkg" | sed 's/@app\/module-//')
  module_dir="$TEMP_NPM_DIR/node_modules/@app/module-${module_name}"
  
  if [ -d "$module_dir" ] && [ -f "${module_dir}/package.json" ]; then
    INSTALLED_MODULES+=("$module_dir")
    log "  ✅ Installed: $module_pkg"
  else
    err "Failed to install $module_pkg from Verdaccio"
    exit 1
  fi
done

########################################
# Step 2: Detect shared native dependencies
########################################
log "Step 2: Detecting shared native dependencies from modules..."

# Function to detect native dependencies from a module (enhanced version with transitive dependency support)
# This is the same enhanced logic from generate-module-framework-aar.sh
detect_native_dependencies() {
    local module_dir="$1"
    local module_package_json="$2"
    local root_package_json="$ROOT_PACKAGE_JSON"
    local temp_npm_dir="${3:-}"  # Optional third parameter for TEMP_NPM_DIR
    local detected_packages=""
    
    if [ ! -d "$module_dir" ]; then
        warn "Module directory not found: $module_dir"
        return
    fi
    
    # Scan source files for react-native-* and expo-* imports
    # Pattern matches: import ... from "react-native-xxx" or import ... from "expo-xxx"
    # Also scan transitive dependencies (like @pkg/ui) that may use native libraries
    local source_files=$(find "$module_dir" -type f \( -name "*.tsx" -o -name "*.ts" -o -name "*.js" -o -name "*.jsx" \) 2>/dev/null)
    
    # Also scan source files from dependencies (transitive dependencies like @pkg/ui)
    # Check node_modules for @pkg/* packages and scan their source files too
    # This handles cases where react-native-svg is used in @pkg/ui but module-cart depends on @pkg/ui
    local dependency_source_files=""
    
    # Check multiple possible locations for node_modules
    # Priority: 1. TEMP_NPM_DIR (where module is installed from Verdaccio), 2. module_dir/node_modules, 3. monorepo node_modules
    local possible_node_modules=()
    if [ -n "$temp_npm_dir" ] && [ -d "$temp_npm_dir" ]; then
        possible_node_modules+=("${temp_npm_dir}/node_modules")
    fi
    if [ -d "${module_dir}/node_modules" ]; then
        possible_node_modules+=("${module_dir}/node_modules")
    fi
    if [ -d "${MONOREPO_ROOT}/node_modules" ]; then
        possible_node_modules+=("${MONOREPO_ROOT}/node_modules")
    fi
    
    # Recursive function to scan @pkg/* dependencies
    # This handles nested dependencies: module-cart -> @pkg/cart-ui -> @pkg/ui -> react-native-svg
    scan_pkg_dependencies() {
        local pkg_dir="$1"
        local scanned_pkgs="$2"  # Track already scanned packages to avoid infinite loops
        local node_modules_dir="$3"
        
        if [ ! -d "$pkg_dir" ] || [ ! -d "${pkg_dir}/src" ]; then
            return
        fi
        
        local pkg_name=$(basename "$pkg_dir")
        
        # Avoid infinite loops - skip if already scanned
        if echo "$scanned_pkgs" | grep -q "^${pkg_name}$"; then
            return
        fi
        scanned_pkgs="${scanned_pkgs}${pkg_name}"$'\n'
        
        # Scan this package's source files for @pkg/* imports
        local pkg_source_files=$(find "$pkg_dir/src" -type f \( -name "*.tsx" -o -name "*.ts" -o -name "*.js" -o -name "*.jsx" \) 2>/dev/null)
        
        if [ -n "$pkg_source_files" ]; then
            # Add this package's source files to dependency_source_files
            dependency_source_files="${dependency_source_files}${pkg_source_files}"$'\n'
            
            # Check if this package imports other @pkg/* packages (nested dependencies)
            local nested_pkg_imports=$(echo "$pkg_source_files" | tr '\n' '\0' | xargs -0 grep -hE "from ['\"]@pkg/" 2>/dev/null | \
                grep -oE "@pkg/[a-zA-Z0-9_-]+" | \
                sed 's/@pkg\///' | \
                sort -u | \
                tr '\n' ' ' | \
                xargs)
            
            # Recursively scan nested @pkg/* dependencies
            if [ -n "$nested_pkg_imports" ]; then
                for nested_pkg in $nested_pkg_imports; do
                    local nested_pkg_dir="${node_modules_dir}/@pkg/${nested_pkg}"
                    if [ -d "$nested_pkg_dir" ]; then
                        scan_pkg_dependencies "$nested_pkg_dir" "$scanned_pkgs" "$node_modules_dir"
                    fi
                done
            fi
        fi
    }
    
    for node_modules_dir in "${possible_node_modules[@]}"; do
        if [ -d "${node_modules_dir}/@pkg" ]; then
            for pkg_dir in "${node_modules_dir}/@pkg"/*; do
                if [ -d "$pkg_dir" ] && [ -d "${pkg_dir}/src" ]; then
                    local pkg_name=$(basename "$pkg_dir")
                    
                    # Check if this @pkg/* package is imported by the module
                    # This works with Verdaccio-installed modules because we scan the module's source files
                    if [ -n "$source_files" ] && echo "$source_files" | tr '\n' '\0' | xargs -0 grep -q "from ['\"]@pkg/${pkg_name}"; then
                        # Extract component names that are actually imported from this package
                        # Pattern: import { Component1, Component2 } from "@pkg/ui"
                        local imported_from_this_pkg=$(echo "$source_files" | tr '\n' '\0' | xargs -0 grep -hE "from ['\"]@pkg/${pkg_name}" 2>/dev/null | \
                            grep -oE "\{[^}]*\}" | \
                            sed 's/[{}]//g' | \
                            tr ',' '\n' | \
                            sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
                            grep -v "^$" | \
                            sort -u | \
                            tr '\n' ' ' | \
                            xargs)
                        
                        if [ -n "$imported_from_this_pkg" ]; then
                            # Only scan source files for components that are actually imported
                            for component in $imported_from_this_pkg; do
                                # Look for component file in primitives/ or directly in src/
                                # This works with Verdaccio because source files are included in the published package
                                local component_file=$(find "$pkg_dir/src" -type f \( \
                                    -path "*/primitives/${component}.tsx" -o \
                                    -path "*/primitives/${component}.ts" -o \
                                    -path "*/${component}.tsx" -o \
                                    -path "*/${component}.ts" -o \
                                    -path "*/${component}.jsx" -o \
                                    -path "*/${component}.js" \
                                \) 2>/dev/null | head -1)
                                
                                if [ -n "$component_file" ] && [ -f "$component_file" ]; then
                                    dependency_source_files="${dependency_source_files}${component_file}"$'\n'
                                fi
                            done
                            
                            # Recursively scan nested @pkg/* dependencies (e.g., @pkg/cart-ui -> @pkg/ui)
                            scan_pkg_dependencies "$pkg_dir" "" "$node_modules_dir"
                        else
                            # If we can't determine specific components (e.g., import * from "@pkg/ui")
                            # Scan all source files as fallback (conservative approach)
                            local pkg_sources=$(find "$pkg_dir" -type f \( -name "*.tsx" -o -name "*.ts" -o -name "*.js" -o -name "*.jsx" \) 2>/dev/null)
                            if [ -n "$pkg_sources" ]; then
                                dependency_source_files="${dependency_source_files}${pkg_sources}"$'\n'
                            fi
                            
                            # Recursively scan nested @pkg/* dependencies
                            scan_pkg_dependencies "$pkg_dir" "" "$node_modules_dir"
                        fi
                    fi
                fi
            done
        fi
    done
    
    # Combine module source files and dependency source files
    # Ensure proper newline separation between the two sets of files
    local all_source_files=""
    if [ -n "$source_files" ]; then
        all_source_files="$source_files"
    fi
    if [ -n "$dependency_source_files" ]; then
        if [ -n "$all_source_files" ]; then
            all_source_files="${all_source_files}"$'\n'"${dependency_source_files}"
        else
            all_source_files="$dependency_source_files"
        fi
    fi
    
    if [ -z "$all_source_files" ]; then
        # Don't warn - this is expected if scanning installed module from Verdaccio
        echo ""
        return
    fi
    
    # Extract package names from imports
    # Matches: from "react-native-xxx" or from 'react-native-xxx' or require("react-native-xxx")
    # Use a simpler approach: process all files at once with xargs
    local imported_packages=""
    if [ -n "$all_source_files" ]; then
        # Use xargs with -0 for null-separated input (more reliable)
        imported_packages=$(echo "$all_source_files" | tr '\n' '\0' | xargs -0 grep -hE "from ['\"](react-native-|expo-)" 2>/dev/null | \
            grep -oE "(react-native-|expo-)[a-zA-Z0-9_-]+" | \
            sort -u | \
            grep -v "^react-native$" | \
            tr '\n' ' ' | \
            xargs)
    fi
    
    if [ -z "$imported_packages" ]; then
        echo ""
        return
    fi
    
    # For each imported package, check if it exists in package.json and has native code
    if command -v node &> /dev/null; then
        # Use a more robust approach: write imported packages to a temp file to avoid shell escaping issues
        local temp_imports_file=$(mktemp)
        echo "$imported_packages" > "$temp_imports_file"
        
        detected_packages=$(node -e "
            const fs = require('fs');
            const path = require('path');
            
            // Read imported packages from temp file to avoid shell escaping issues
            const importedPkgsStr = fs.readFileSync('$temp_imports_file', 'utf8').trim();
            const importedPkgs = importedPkgsStr ? importedPkgsStr.split(/\\s+/).filter(p => p && p.trim()) : [];
            
            const modulePkgJson = '$module_package_json';
            const rootPkgJson = '$root_package_json';
            const monorepoRoot = process.env.MONOREPO_ROOT || '${MONOREPO_ROOT}';
            const moduleDir = '$module_dir';
            
            const nativeDeps = [];
            
            for (const pkg of importedPkgs) {
                // Skip if not a native package pattern
                if (!pkg.startsWith('react-native-') && !pkg.startsWith('expo-')) {
                    continue;
                }
                if (pkg === 'react-native') {
                    continue;
                }
                
                // Check module package.json first (if provided)
                let pkgVersion = null;
                let foundInModule = false;
                
                if (modulePkgJson && modulePkgJson.trim() !== '' && fs.existsSync(modulePkgJson)) {
                    try {
                        const modulePkg = JSON.parse(fs.readFileSync(modulePkgJson, 'utf8'));
                        const allDeps = {
                            ...(modulePkg.dependencies || {}),
                            ...(modulePkg.peerDependencies || {}),
                            ...(modulePkg.devDependencies || {})
                        };
                        if (allDeps[pkg]) {
                            pkgVersion = allDeps[pkg];
                            foundInModule = true;
                        }
                    } catch (e) {
                        // Continue to root check
                    }
                }
                
                // Fallback to root package.json
                if (!pkgVersion && fs.existsSync(rootPkgJson)) {
                    try {
                        const rootPkg = JSON.parse(fs.readFileSync(rootPkgJson, 'utf8'));
                        const allDeps = {
                            ...(rootPkg.dependencies || {}),
                            ...(rootPkg.peerDependencies || {}),
                            ...(rootPkg.devDependencies || {})
                        };
                        if (allDeps[pkg]) {
                            pkgVersion = allDeps[pkg];
                        }
                    } catch (e) {
                        // Continue
                    }
                }
                
                // If package found in either package.json, check for native code
                if (pkgVersion) {
                    // Check multiple possible locations for native code
                    // Priority: 1. Installed package's node_modules, 2. Monorepo node_modules, 3. Current dir node_modules
                    const possiblePaths = [
                        ...(moduleDir && moduleDir.trim() !== '' ? [path.join(moduleDir, 'node_modules', pkg)] : []),
                        path.join(monorepoRoot, 'node_modules', pkg),
                        ...(modulePkgJson && modulePkgJson.trim() !== '' ? [path.join(path.dirname(modulePkgJson), 'node_modules', pkg)] : []),
                        path.join(process.cwd(), 'node_modules', pkg)
                    ];
                    
                    let hasNativeCode = false;
                    for (const pkgPath of possiblePaths) {
                        try {
                            const androidJava = path.join(pkgPath, 'android', 'src', 'main', 'java');
                            const androidKotlin = path.join(pkgPath, 'android', 'src', 'main', 'kotlin');
                            const androidPaper = path.join(pkgPath, 'android', 'src', 'paper', 'java');
                            const ios = path.join(pkgPath, 'ios');
                            const apple = path.join(pkgPath, 'apple');
                            
                            if (fs.existsSync(androidJava) || 
                                fs.existsSync(androidKotlin) || 
                                fs.existsSync(androidPaper) ||
                                fs.existsSync(ios) || 
                                fs.existsSync(apple)) {
                                hasNativeCode = true;
                                break;
                            }
                        } catch (e) {
                            // Continue checking other paths
                        }
                    }
                    
                    if (hasNativeCode) {
                        nativeDeps.push(pkg);
                    }
                }
            }
            
            console.log(nativeDeps.join(' '));
        " 2>/dev/null)
        
        # Clean up temp file
        rm -f "$temp_imports_file"
    else
        # Fallback: simple approach without node
        warn "Node.js not available, using fallback detection"
        detected_packages=$(echo "$imported_packages" | tr '\n' ' ')
    fi
    
    echo "$detected_packages"
}

# Detect native dependencies from each module
# Use a simple approach: track all deps and count occurrences manually (bash 3.2 compatible)
ALL_NATIVE_DEPS=()
ALL_NATIVE_DEPS_WITH_COUNTS=()  # Format: "package_name:count"

for module_dir in "${INSTALLED_MODULES[@]}"; do
    module_name=$(basename "$module_dir" | sed 's/module-//')
    module_package_json="${module_dir}/package.json"
    
    log "  Scanning module: $module_name"
    # Pass TEMP_NPM_DIR so detection can scan transitive dependencies like @pkg/ui
    module_deps=$(detect_native_dependencies "$module_dir" "$module_package_json" "$TEMP_NPM_DIR")
    
    if [ -n "$module_deps" ]; then
        log "    Found: $module_deps"
        for dep in $module_deps; do
            # Add to all deps list (deduplicated)
            found=false
            if [ ${#ALL_NATIVE_DEPS[@]} -gt 0 ]; then
                for existing_dep in "${ALL_NATIVE_DEPS[@]}"; do
                    if [ "$existing_dep" = "$dep" ]; then
                        found=true
                        # Increment count for this package
                        for i in "${!ALL_NATIVE_DEPS_WITH_COUNTS[@]}"; do
                            if [[ "${ALL_NATIVE_DEPS_WITH_COUNTS[$i]}" == "$dep:"* ]]; then
                                current_count=$(echo "${ALL_NATIVE_DEPS_WITH_COUNTS[$i]}" | cut -d: -f2)
                                new_count=$((current_count + 1))
                                ALL_NATIVE_DEPS_WITH_COUNTS[$i]="$dep:$new_count"
                                break
                            fi
                        done
                        break
                    fi
                done
            fi
            
            if [ "$found" = false ]; then
                ALL_NATIVE_DEPS+=("$dep")
                ALL_NATIVE_DEPS_WITH_COUNTS+=("$dep:1")
            fi
        done
    else
        log "    No native dependencies found"
    fi
done

# Find shared dependencies (used by 2+ modules)
SHARED_NATIVE_DEPS=()
log ""
log "  Native dependency usage summary:"
for entry in "${ALL_NATIVE_DEPS_WITH_COUNTS[@]}"; do
    dep=$(echo "$entry" | cut -d: -f1)
    count=$(echo "$entry" | cut -d: -f2)
    
    if [ "$count" -ge 2 ]; then
        SHARED_NATIVE_DEPS+=("$dep")
        log "    ✅ $dep: Used by $count modules (SHARED - will be bundled)"
    else
        log "    ℹ️  $dep: Used by $count module(s) (module-specific - will be bundled anyway for now)"
        # For now, include all native deps in the kit
        # Later we can make this configurable
        already_added=false
        if [ ${#SHARED_NATIVE_DEPS[@]} -gt 0 ]; then
            for existing in "${SHARED_NATIVE_DEPS[@]}"; do
                if [ "$existing" = "$dep" ]; then
                    already_added=true
                    break
                fi
            done
        fi
        if [ "$already_added" = false ]; then
            SHARED_NATIVE_DEPS+=("$dep")
        fi
    fi
done

if [ ${#SHARED_NATIVE_DEPS[@]} -eq 0 ]; then
    warn "No native dependencies found across modules"
    warn "The kit will be empty. This is unusual - check if modules are using native libraries."
    exit 1
fi

log ""
log "  📦 Native dependencies to bundle: ${SHARED_NATIVE_DEPS[*]}"

########################################
# Step 3: Install native packages from npm registry
########################################
log "Step 3: Installing native packages from npm registry..."

# Install native packages in temp directory (from npm, not Verdaccio)
cd "$TEMP_NPM_DIR"
rm -f package.json .npmrc

# Create package.json with native dependencies
cat > "$TEMP_NPM_DIR/package.json" <<EOF
{
  "name": "native-kit-install-temp",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
EOF

for dep in "${SHARED_NATIVE_DEPS[@]}"; do
    # Get version from root package.json or use latest
    version=$(node -e "
        const fs = require('fs');
        const rootPkg = JSON.parse(fs.readFileSync('$ROOT_PACKAGE_JSON', 'utf8'));
        const allDeps = {
            ...(rootPkg.dependencies || {}),
            ...(rootPkg.peerDependencies || {}),
            ...(rootPkg.devDependencies || {})
        };
        console.log(allDeps['$dep'] || 'latest');
    " 2>/dev/null || echo "latest")
    
    echo "    \"$dep\": \"$version\"," >> "$TEMP_NPM_DIR/package.json"
done

cat >> "$TEMP_NPM_DIR/package.json" <<EOF
    "react-native": "0.81.5"
  }
}
EOF

# Use npm registry (not Verdaccio) for public packages
cat > "$TEMP_NPM_DIR/.npmrc" <<EOF
registry=https://registry.npmjs.org/
EOF

log "  Installing native packages from npm registry..."
npm install --legacy-peer-deps --no-save > /dev/null 2>&1

# Verify installations
for dep in "${SHARED_NATIVE_DEPS[@]}"; do
    if [ -d "$TEMP_NPM_DIR/node_modules/$dep" ]; then
        log "  ✅ Installed: $dep"
    else
        err "Failed to install $dep from npm registry"
        exit 1
    fi
done

########################################
# Step 3.1: Recursively detect transitive native dependencies
########################################
log "Step 3.1: Detecting transitive native dependencies..."

# Function to recursively find transitive native dependencies
find_transitive_native_deps() {
    local package_name="$1"
    local package_dir="$2"
    local visited_packages="$3"  # Track visited packages to avoid infinite loops
    local transitive_deps=()
    
    # Check if already visited
    if echo "$visited_packages" | grep -q "^${package_name}$"; then
        return
    fi
    visited_packages="${visited_packages}${package_name}"$'\n'
    
    # Check if package directory exists
    if [ ! -d "$package_dir" ]; then
        return
    fi
    
    # Check package.json for dependencies
    local package_json="${package_dir}/package.json"
    if [ ! -f "$package_json" ]; then
        return
    fi
    
    # Extract dependencies that are native packages (react-native-* or expo-*)
    local deps=$(node -e "
        const fs = require('fs');
        try {
            const pkg = JSON.parse(fs.readFileSync('$package_json', 'utf8'));
            const allDeps = {
                ...(pkg.dependencies || {}),
                ...(pkg.peerDependencies || {}),
                ...(pkg.devDependencies || {})
            };
            const nativeDeps = [];
            for (const [depName, depVersion] of Object.entries(allDeps)) {
                if ((depName.startsWith('react-native-') || depName.startsWith('expo-')) && 
                    depName !== 'react-native') {
                    nativeDeps.push(depName);
                }
            }
            console.log(nativeDeps.join(' '));
        } catch (e) {
            // Ignore errors
        }
    " 2>/dev/null || echo "")
    
    if [ -z "$deps" ]; then
        return
    fi
    
    # For each dependency, check if it has native code and recurse
    for dep in $deps; do
        # Skip if already in SHARED_NATIVE_DEPS
        local already_included=false
        for existing_dep in "${SHARED_NATIVE_DEPS[@]}"; do
            if [ "$existing_dep" = "$dep" ]; then
                already_included=true
                break
            fi
        done
        
        if [ "$already_included" = true ]; then
            continue
        fi
        
        # Check if dependency is installed and has native code
        local dep_dir="${TEMP_NPM_DIR}/node_modules/${dep}"
        if [ ! -d "$dep_dir" ]; then
            # Try to find it in other locations
            dep_dir="${MONOREPO_ROOT}/node_modules/${dep}"
            if [ ! -d "$dep_dir" ]; then
                continue
            fi
        fi
        
        # Check for native code
        local has_native=false
        if [ -d "${dep_dir}/android/src/main/java" ] || \
           [ -d "${dep_dir}/android/src/main/kotlin" ] || \
           [ -d "${dep_dir}/android/src/paper/java" ] || \
           [ -d "${dep_dir}/ios" ] || \
           [ -d "${dep_dir}/apple" ]; then
            has_native=true
        fi
        
        if [ "$has_native" = true ]; then
            transitive_deps+=("$dep")
            log "    Found transitive native dependency: $dep (from $package_name)"
            
            # Recursively find its transitive dependencies
            local sub_transitive=$(find_transitive_native_deps "$dep" "$dep_dir" "$visited_packages")
            if [ -n "$sub_transitive" ]; then
                for sub_dep in $sub_transitive; do
                    # Check if not already added
                    local already_added=false
                    for existing in "${transitive_deps[@]}"; do
                        if [ "$existing" = "$sub_dep" ]; then
                            already_added=true
                            break
                        fi
                    done
                    if [ "$already_added" = false ]; then
                        transitive_deps+=("$sub_dep")
                    fi
                done
            fi
        fi
    done
    
    # Return transitive dependencies as space-separated string
    if [ ${#transitive_deps[@]} -gt 0 ]; then
        echo "${transitive_deps[*]}"
    fi
}

# Find all transitive native dependencies
ALL_TRANSITIVE_DEPS=()
for dep in "${SHARED_NATIVE_DEPS[@]}"; do
    dep_dir="${TEMP_NPM_DIR}/node_modules/${dep}"
    if [ -d "$dep_dir" ]; then
        log "  Checking transitive dependencies for: $dep"
        transitive=$(find_transitive_native_deps "$dep" "$dep_dir" "")
        if [ -n "$transitive" ]; then
            for trans_dep in $transitive; do
                # Add to ALL_TRANSITIVE_DEPS if not already present
                local already_added=false
                for existing in "${ALL_TRANSITIVE_DEPS[@]}"; do
                    if [ "$existing" = "$trans_dep" ]; then
                        already_added=true
                        break
                    fi
                done
                if [ "$already_added" = false ]; then
                    ALL_TRANSITIVE_DEPS+=("$trans_dep")
                fi
            done
        fi
    fi
done

# Install transitive dependencies if any found
if [ ${#ALL_TRANSITIVE_DEPS[@]} -gt 0 ]; then
    log ""
    log "  📦 Found ${#ALL_TRANSITIVE_DEPS[@]} transitive native dependencies: ${ALL_TRANSITIVE_DEPS[*]}"
    log "  Installing transitive dependencies..."
    
    # Add transitive dependencies to package.json
    for trans_dep in "${ALL_TRANSITIVE_DEPS[@]}"; do
        # Get version from installed package or use latest
        version=$(node -e "
            const fs = require('fs');
            const path = require('path');
            const depDir = path.join('$TEMP_NPM_DIR', 'node_modules', '$trans_dep');
            const monorepoDir = path.join('$MONOREPO_ROOT', 'node_modules', '$trans_dep');
            let pkgJson = null;
            if (fs.existsSync(path.join(depDir, 'package.json'))) {
                pkgJson = path.join(depDir, 'package.json');
            } else if (fs.existsSync(path.join(monorepoDir, 'package.json'))) {
                pkgJson = path.join(monorepoDir, 'package.json');
            }
            if (pkgJson) {
                const pkg = JSON.parse(fs.readFileSync(pkgJson, 'utf8'));
                console.log(pkg.version || 'latest');
            } else {
                console.log('latest');
            }
        " 2>/dev/null || echo "latest")
        
        # Add to package.json
        sed -i.bak "/\"react-native\":/i\\
    \"$trans_dep\": \"$version\",
" "$TEMP_NPM_DIR/package.json"
        rm -f "$TEMP_NPM_DIR/package.json.bak"
    done
    
    # Install transitive dependencies
    npm install --legacy-peer-deps --no-save > /dev/null 2>&1
    
    # Verify and add to SHARED_NATIVE_DEPS
    for trans_dep in "${ALL_TRANSITIVE_DEPS[@]}"; do
        if [ -d "$TEMP_NPM_DIR/node_modules/$trans_dep" ]; then
            log "  ✅ Installed transitive: $trans_dep"
            SHARED_NATIVE_DEPS+=("$trans_dep")
        else
            warn "  ⚠️  Failed to install transitive: $trans_dep"
        fi
    done
    
    log ""
    log "  📦 Total native dependencies to bundle: ${SHARED_NATIVE_DEPS[*]}"
else
    log "  ℹ️  No transitive native dependencies found"
fi

# Check if any expo packages are detected and add expo-modules-core if needed
HAS_EXPO_PACKAGES=false
for dep in "${SHARED_NATIVE_DEPS[@]}"; do
    if [[ "$dep" == expo-* ]]; then
        HAS_EXPO_PACKAGES=true
        break
    fi
done

if [ "$HAS_EXPO_PACKAGES" = true ]; then
    log ""
    log "  📦 Expo packages detected - checking for expo-modules-core..."
    
    # Check if expo-modules-core is already in SHARED_NATIVE_DEPS
    expo_core_found=false
    for dep in "${SHARED_NATIVE_DEPS[@]}"; do
        if [ "$dep" = "expo-modules-core" ]; then
            expo_core_found=true
            break
        fi
    done
    
    if [ "$expo_core_found" = false ]; then
        # Check if expo-modules-core exists in node_modules or expo-modules-core-source
        expo_core_source=""
        
        # First check expo-modules-core-source directory (if provided)
        if [ -d "${MONOREPO_ROOT}/expo-modules-core-source/ios" ]; then
            expo_core_source="${MONOREPO_ROOT}/expo-modules-core-source"
            log "    Found expo-modules-core in expo-modules-core-source/"
        elif [ -d "${TEMP_NPM_DIR}/node_modules/expo-modules-core/ios" ]; then
            expo_core_source="${TEMP_NPM_DIR}/node_modules/expo-modules-core"
            log "    Found expo-modules-core in node_modules/"
        elif [ -d "${MONOREPO_ROOT}/node_modules/expo-modules-core/ios" ]; then
            expo_core_source="${MONOREPO_ROOT}/node_modules/expo-modules-core"
            log "    Found expo-modules-core in monorepo node_modules/"
        fi
        
        if [ -n "$expo_core_source" ]; then
            SHARED_NATIVE_DEPS+=("expo-modules-core")
            log "    ✅ Added expo-modules-core to native dependencies"
        else
            warn "    ⚠️  expo-modules-core not found - expo packages may not work correctly"
            warn "    Expected locations:"
            warn "      - ${MONOREPO_ROOT}/expo-modules-core-source/ios"
            warn "      - ${TEMP_NPM_DIR}/node_modules/expo-modules-core/ios"
            warn "      - ${MONOREPO_ROOT}/node_modules/expo-modules-core/ios"
        fi
    else
        log "    ✅ expo-modules-core already in dependencies"
    fi
fi

########################################
# Step 4: Bundle iOS native code to vsco-native-kit
########################################
log "Step 4: Bundling iOS native code to vsco-native-kit..."

# Function to bundle iOS native dependency
bundle_ios_to_kit() {
    local package_name="$1"
    local package_source="$2"
    
    log "  Bundling $package_name (iOS)..."
    
    # Verify iOS native code exists
    local has_ios=false
    
    if [ -d "${package_source}/ios" ] || [ -d "${package_source}/apple" ]; then
        has_ios=true
    fi
    
    if [ "$has_ios" = false ]; then
        warn "    $package_name has no iOS native code - skipping"
        return 1
    fi
    
    local ios_source_dir=""
    if [ -d "${package_source}/apple" ]; then
        ios_source_dir="${package_source}/apple"
    elif [ -d "${package_source}/ios" ]; then
        ios_source_dir="${package_source}/ios"
    fi
    
    if [ -n "$ios_source_dir" ]; then
        # Create module directory in iOS Sources
        # Convert package name to module name
        # react-native-svg -> VSCOSvg
        # react-native-safe-area-context -> VSCOSafeAreaContext
        # expo-file-system -> VSCOExpoFileSystem
        # expo-modules-core -> VSCOExpoModulesCore
        local module_name=$(node -e "
            const pkg = '$package_name';
            let name = pkg.replace(/^(react-native-|expo-)/, '');
            const isExpo = pkg.startsWith('expo-');
            // Convert kebab-case to PascalCase
            name = name.split('-').map(word => 
                word.charAt(0).toUpperCase() + word.slice(1)
            ).join('');
            const prefix = isExpo ? 'VSCOExpo' : 'VSCO';
            console.log(prefix + name);
        " 2>/dev/null)
        
        if [ -z "$module_name" ]; then
            # Fallback if node fails
            if [[ "$package_name" == expo-* ]]; then
                module_name="VSCOExpo$(echo "$package_name" | sed 's/expo-//' | sed 's/-\([a-z]\)/\U\1/g' | sed 's/^./\U&/')"
            else
                module_name="VSCO$(echo "$package_name" | sed 's/react-native-//' | sed 's/-\([a-z]\)/\U\1/g' | sed 's/^./\U&/')"
            fi
        fi
        
        local ios_target_dir="${KIT_IOS_PACKAGE_DIR}/Sources/${module_name}"
        log "    Copying iOS native code to ${module_name}..."
        mkdir -p "$ios_target_dir"
        cp -R "$ios_source_dir"/* "$ios_target_dir/" 2>/dev/null || true
        
        # Special handling for expo-modules-core: copy common/cpp headers
        if [ "$package_name" = "expo-modules-core" ]; then
            if [ -d "${package_source}/common/cpp" ]; then
                log "    Copying common/cpp headers for expo-modules-core..."
                # Copy C++ headers to JSI directory (where they're expected)
                local jsi_dir="${ios_target_dir}/JSI"
                if [ -d "$jsi_dir" ]; then
                    cp "${package_source}/common/cpp"/*.h "$jsi_dir/" 2>/dev/null || true
                    log "    ✅ common/cpp headers copied"
                else
                    # If JSI directory doesn't exist, copy to root of module
                    cp "${package_source}/common/cpp"/*.h "$ios_target_dir/" 2>/dev/null || true
                    log "    ✅ common/cpp headers copied to module root"
                fi
            fi
        fi
        
        log "    ✅ iOS native code bundled"
    fi
    
    return 0
}

# Bundle each native dependency (iOS only)
for dep in "${SHARED_NATIVE_DEPS[@]}"; do
    package_source=""
    
    # Special handling for expo-modules-core - check expo-modules-core-source first
    if [ "$dep" = "expo-modules-core" ]; then
        if [ -d "${MONOREPO_ROOT}/expo-modules-core-source/ios" ]; then
            package_source="${MONOREPO_ROOT}/expo-modules-core-source"
            log "  Using expo-modules-core from expo-modules-core-source/"
        elif [ -d "${TEMP_NPM_DIR}/node_modules/expo-modules-core" ]; then
            package_source="${TEMP_NPM_DIR}/node_modules/expo-modules-core"
        elif [ -d "${MONOREPO_ROOT}/node_modules/expo-modules-core" ]; then
            package_source="${MONOREPO_ROOT}/node_modules/expo-modules-core"
        fi
    else
        # For other packages, check node_modules
        package_source="$TEMP_NPM_DIR/node_modules/$dep"
        
        # Fallback to monorepo node_modules if not found
        if [ ! -d "$package_source" ]; then
            package_source="${MONOREPO_ROOT}/node_modules/$dep"
        fi
    fi
    
    if [ -n "$package_source" ] && [ -d "$package_source" ]; then
        bundle_ios_to_kit "$dep" "$package_source"
    else
        warn "    $dep not found (checked: node_modules, expo-modules-core-source)"
    fi
done

log "  ✅ iOS native code bundled to vsco-native-kit"

# Step 6.5: Copy common/cpp headers and JSI headers for expo-modules-core
########################################
# Check if VSCOExpoModulesCore exists and needs additional headers
if [ -d "${KIT_IOS_PACKAGE_DIR}/Sources/VSCOExpoModulesCore" ]; then
    log "Step 6.5: Copying additional headers for VSCOExpoModulesCore..."
    
    # Find expo-modules-core source directory
    expo_core_source=""
    if [ -d "${MONOREPO_ROOT}/expo-modules-core-source" ]; then
        expo_core_source="${MONOREPO_ROOT}/expo-modules-core-source"
    elif [ -d "${TEMP_NPM_DIR}/node_modules/expo-modules-core" ]; then
        expo_core_source="${TEMP_NPM_DIR}/node_modules/expo-modules-core"
    elif [ -d "${MONOREPO_ROOT}/node_modules/expo-modules-core" ]; then
        expo_core_source="${MONOREPO_ROOT}/node_modules/expo-modules-core"
    fi
    
    if [ -n "$expo_core_source" ] && [ -d "$expo_core_source" ]; then
        # Copy common/cpp headers to JSI directory (where they're expected)
        if [ -d "${expo_core_source}/common/cpp" ]; then
            jsi_dir="${KIT_IOS_PACKAGE_DIR}/Sources/VSCOExpoModulesCore/JSI"
            if [ -d "$jsi_dir" ]; then
                log "  Copying common/cpp headers to JSI directory..."
                cp "${expo_core_source}/common/cpp"/*.h "$jsi_dir/" 2>/dev/null || true
                log "  ✅ common/cpp headers copied"
            else
                # If JSI directory doesn't exist, copy to root of module
                log "  Copying common/cpp headers to module root..."
                cp "${expo_core_source}/common/cpp"/*.h "${KIT_IOS_PACKAGE_DIR}/Sources/VSCOExpoModulesCore/" 2>/dev/null || true
                log "  ✅ common/cpp headers copied to module root"
            fi
        fi
    fi
    
    # Copy JSI headers from Hermes
    log "  Copying JSI headers from Hermes..."
    
    # Find Hermes JSI headers
    # Note: For Expo modules, we only use expo-modules-core-source and node_modules (Verdaccio)
    # We do NOT use rn-runtime-source for Expo-related operations
    JSI_HEADER_SOURCE=""
    
    # Check common locations for Hermes JSI headers (only in node_modules, not rn-runtime-source)
    if [ -f "${MONOREPO_ROOT}/node_modules/hermes-engine/destroot/include/jsi/jsi.h" ]; then
        JSI_HEADER_SOURCE="${MONOREPO_ROOT}/node_modules/hermes-engine/destroot/include/jsi"
        log "  Found Hermes JSI headers in node_modules"
    elif [ -f "${TEMP_NPM_DIR}/node_modules/hermes-engine/destroot/include/jsi/jsi.h" ]; then
        JSI_HEADER_SOURCE="${TEMP_NPM_DIR}/node_modules/hermes-engine/destroot/include/jsi"
        log "  Found Hermes JSI headers in temp node_modules"
    fi
    
    if [ -n "$JSI_HEADER_SOURCE" ] && [ -d "$JSI_HEADER_SOURCE" ]; then
        # Create jsi subdirectory in VSCOExpoModulesCore/JSI
        jsi_wrapper_dir="${KIT_IOS_PACKAGE_DIR}/Sources/VSCOExpoModulesCore/JSI/jsi"
        mkdir -p "$jsi_wrapper_dir"
        
        # Copy jsi.h and jsi-inl.h
        if [ -f "${JSI_HEADER_SOURCE}/jsi.h" ]; then
            cp "${JSI_HEADER_SOURCE}/jsi.h" "$jsi_wrapper_dir/" 2>/dev/null || true
            log "  ✅ Copied jsi.h"
            
            # Fix const-correctness issue in jsi.h (buffer.data() const issue)
            if grep -qE 'buffer\.data\(\),' "$jsi_wrapper_dir/jsi.h" 2>/dev/null; then
                log "  Fixing const-correctness issue in jsi.h..."
                perl -pi -e 's/buffer\.data\(\)/const_cast<char*>(buffer.data())/g' "$jsi_wrapper_dir/jsi.h" 2>/dev/null || true
                log "  ✅ Fixed const-correctness in jsi.h"
            fi
        fi
        
        if [ -f "${JSI_HEADER_SOURCE}/jsi-inl.h" ]; then
            cp "${JSI_HEADER_SOURCE}/jsi-inl.h" "$jsi_wrapper_dir/" 2>/dev/null || true
            log "  ✅ Copied jsi-inl.h"
        fi
        
        log "  ✅ JSI headers copied and fixed"
    else
        warn "  ⚠️  Hermes JSI headers not found - JSI functionality may not work"
        warn "  Expected locations:"
        warn "    - ${MONOREPO_ROOT}/node_modules/hermes-engine/destroot/include/jsi"
        warn "    - ${TEMP_NPM_DIR}/node_modules/hermes-engine/destroot/include/jsi"
    fi
fi

# Step 7: Update iOS Package.swift
########################################
log "Step 7: Updating iOS Package.swift..."

# Detect iOS modules (exclude VSCONativeKit wrapper)
IOS_MODULES=()
if [ -d "${KIT_IOS_PACKAGE_DIR}/Sources" ]; then
    for module_dir in "${KIT_IOS_PACKAGE_DIR}/Sources"/*; do
        if [ -d "$module_dir" ]; then
            module_name=$(basename "$module_dir")
            # Skip VSCONativeKit wrapper - it's added separately
            if [ "$module_name" != "VSCONativeKit" ]; then
                IOS_MODULES+=("$module_name")
            fi
        fi
    done
fi

# Pre-process modules to detect mixed languages (before generating Package.swift)
# Store results in temporary files for compatibility with bash 3.2
MIXED_LANG_TEMP_DIR=$(mktemp -d)
for module in "${IOS_MODULES[@]}"; do
    module_dir="${KIT_IOS_PACKAGE_DIR}/Sources/$module"
    
    has_swift=false
    has_objc=false
    if [ -d "$module_dir" ]; then
        # More robust Swift detection - use count instead of head -1 | grep
        swift_count=$(find "$module_dir" -name "*.swift" -type f 2>/dev/null | wc -l | tr -d ' ')
        if [ -n "$swift_count" ] && [ "$swift_count" -gt 0 ] 2>/dev/null; then
            has_swift=true
        fi
        # More robust Objective-C detection - use count instead of head -1 | grep
        objc_count=$(find "$module_dir" \( -name "*.m" -o -name "*.mm" \) -type f 2>/dev/null | wc -l | tr -d ' ')
        if [ -n "$objc_count" ] && [ "$objc_count" -gt 0 ] 2>/dev/null; then
            has_objc=true
        fi
    fi
    
    # Store detection results in temp files
    echo "$has_swift" > "${MIXED_LANG_TEMP_DIR}/${module}_has_swift"
    echo "$has_objc" > "${MIXED_LANG_TEMP_DIR}/${module}_has_objc"
    
    is_mixed_language=false
    if [ "$has_swift" = true ] && [ "$has_objc" = true ]; then
        is_mixed_language=true
        echo "true" > "${MIXED_LANG_TEMP_DIR}/${module}_is_mixed"
        if [[ "$module" == VSCOExpo* ]]; then
            log "    $module detected as mixed-language (Swift + Objective-C) - will be split into separate targets"
        fi
    else
        echo "false" > "${MIXED_LANG_TEMP_DIR}/${module}_is_mixed"
        # Debug: Log why expo packages aren't detected as mixed
        if [[ "$module" == VSCOExpo* ]]; then
            log "    $module detection: has_swift=$has_swift (swift_count=$swift_count), has_objc=$has_objc (objc_count=$objc_count), is_mixed=$is_mixed_language"
        fi
    fi
done

# Generate Package.swift with all fixes for RN 0.81.5 compatibility
cat > "${KIT_IOS_PACKAGE_DIR}/Package.swift" <<EOF
// swift-tools-version:5.7
// VSCO Native Kit - Unified iOS SPM Package
// Generated from native dependencies detected in Verdaccio modules
// Compatible with React Native 0.81.5
import PackageDescription

let package = Package(
    name: "VSCONativeKit",
    platforms: [.iOS(.v14)],  // iOS 14.0+ required for React Native 0.81.5
    products: [
        .library(
            name: "VSCONativeKit",
            targets: ["VSCONativeKit"]
        )$(if [ ${#IOS_MODULES[@]} -gt 0 ]; then
    echo ","
    for module in "${IOS_MODULES[@]}"; do
        echo "        .library("
        echo "            name: \"$module\","
        echo "            targets: [\"$module\"]"
        echo "        ),"
    done | sed '$ s/,$//'
fi)
    ],
    dependencies: [
        // React Native Runtime - required for React Native headers
        // Path is relative to this package's location (vsco-native-kit/ios/VSCONativeKit/)
        .package(path: "../../../frameworks/ios/VSCOReactNativeRuntime")
    ],
    targets: [
$(if [ ${#IOS_MODULES[@]} -gt 0 ]; then
    for module in "${IOS_MODULES[@]}"; do
        module_dir="${KIT_IOS_PACKAGE_DIR}/Sources/$module"
        
        # Dynamically detect if Fabric directory exists (for any module)
        has_fabric=false
        if [ -d "${module_dir}/Fabric" ]; then
            has_fabric=true
        fi
        
        # Use pre-computed mixed-language detection from temp files
        if [ -f "${MIXED_LANG_TEMP_DIR}/${module}_has_swift" ]; then
            has_swift=$(cat "${MIXED_LANG_TEMP_DIR}/${module}_has_swift")
        else
            has_swift=false
        fi
        if [ -f "${MIXED_LANG_TEMP_DIR}/${module}_has_objc" ]; then
            has_objc=$(cat "${MIXED_LANG_TEMP_DIR}/${module}_has_objc")
        else
            has_objc=false
        fi
        if [ -f "${MIXED_LANG_TEMP_DIR}/${module}_is_mixed" ]; then
            is_mixed_language=$(cat "${MIXED_LANG_TEMP_DIR}/${module}_is_mixed" 2>/dev/null || echo "false")
        else
            is_mixed_language=false
        fi
        
        # Debug: For expo packages, verify detection and force re-check if needed
        if [[ "$module" == VSCOExpo* ]]; then
            # Always re-check from temp file for expo packages to ensure accuracy
            if [ -f "${MIXED_LANG_TEMP_DIR}/${module}_is_mixed" ]; then
                file_content=$(cat "${MIXED_LANG_TEMP_DIR}/${module}_is_mixed" 2>/dev/null | tr -d '\n\r ')
                if [ "$file_content" = "true" ]; then
                    is_mixed_language="true"
                else
                    is_mixed_language="false"
                fi
            fi
        fi
        
        # Dynamically detect if module has subdirectories that need header search paths
        # Include both top-level and nested subdirectories that contain header files
        needs_header_paths=false
        subdirs=()
        if [ -d "$module_dir" ]; then
            for subdir in "$module_dir"/*; do
                if [ -d "$subdir" ]; then
                    subdir_name=$(basename "$subdir")
                    # Skip Stubs directory from header paths (it's added separately if it exists)
                    if [[ "$subdir_name" != "Stubs" ]] && [[ "$subdir_name" != "Fabric" ]]; then
                        subdirs+=("$subdir_name")
                        needs_header_paths=true
                        
                        # Also check for nested subdirectories (e.g., Filters/MetalCI)
                        # Only add if they contain header files
                        for nested_subdir in "$subdir"/*; do
                            if [ -d "$nested_subdir" ] && find "$nested_subdir" -name "*.h" -type f 2>/dev/null | head -1 | grep -q .; then
                                nested_name=$(basename "$nested_subdir")
                                nested_path="${subdir_name}/${nested_name}"
                                # Only add if not already in the list
                                if [[ ! " ${subdirs[@]} " =~ " ${nested_path} " ]]; then
                                    subdirs+=("$nested_path")
                                fi
                            fi
                        done
                    fi
                fi
            done
        fi
        
        # For mixed-language targets, SPM doesn't support them in the same target
        # We need to create separate targets: one for Objective-C and one for Swift
        # SPM will automatically bridge ObjC types to Swift when the Swift target depends on the ObjC target
        if [ "$is_mixed_language" = "true" ]; then
            # Collect Objective-C files (.m, .mm, .h) and Swift files
            # Exclude test files and directories (Tests/, TestUtils/, etc.)
            objc_files=()
            swift_files=()
            if [ -d "$module_dir" ]; then
                while IFS= read -r file; do
                    # Exclude test files, Fabric files, and SwiftUI files that depend on Fabric
                    if [[ "$file" != *"/Tests/"* ]] && \
                       [[ "$file" != *"/TestUtils/"* ]] && \
                       [[ "$file" != *"/Fabric/"* ]] && \
                       [[ "$(basename "$file")" != *"Test."* ]] && \
                       [[ "$(basename "$file")" != *"Spec."* ]] && \
                       [[ "$(basename "$file")" != "SwiftUIVirtualViewObjC.mm" ]] && \
                       [[ "$(basename "$file")" != "SwiftUIVirtualViewObjC.h" ]]; then
                        objc_files+=("${file#$module_dir/}")
                    fi
                done < <(find "$module_dir" -type f \( -name "*.m" -o -name "*.mm" -o -name "*.h" \) ! -name "*-Bridging-Header.h" 2>/dev/null)
                
                # For VSCOExpoModulesCoreObjC, also include C++ implementation files (.cpp)
                # These provide the implementations for C++ symbols referenced by .mm files
                if [ "$module" = "VSCOExpoModulesCore" ]; then
                    while IFS= read -r file; do
                        # Only include C++ files from JSI directory (the ones that provide implementations)
                        if [[ "$file" == *"/JSI/"* ]] && \
                           [[ "$file" != *"/Tests/"* ]] && \
                           [[ "$file" != *"/TestUtils/"* ]] && \
                           [[ "$file" != *"/Fabric/"* ]]; then
                            objc_files+=("${file#$module_dir/}")
                        fi
                    done < <(find "$module_dir" -type f -name "*.cpp" 2>/dev/null)
                fi
                
                while IFS= read -r file; do
                    # Exclude test files and Fabric-related SwiftUI files
                    if [[ "$file" != *"/Tests/"* ]] && \
                       [[ "$file" != *"/TestUtils/"* ]] && \
                       [[ "$file" != *"/Fabric/"* ]] && \
                       [[ "$(basename "$file")" != *"Test."* ]] && \
                       [[ "$(basename "$file")" != *"Spec."* ]]; then
                        swift_files+=("${file#$module_dir/}")
                    fi
                done < <(find "$module_dir" -type f -name "*.swift" 2>/dev/null)
            fi
            
            # Check if module imports ExpoModulesCore (for expo packages)
            # Skip if this module IS VSCOExpoModulesCore (it shouldn't depend on itself)
            needs_expo_modules_core=false
            if [ "$module" != "VSCOExpoModulesCore" ] && [ -d "$module_dir" ]; then
                if find "$module_dir" -type f \( -name "*.m" -o -name "*.mm" -o -name "*.h" \) -exec grep -l "ExpoModulesCore\|expo-modules-core" {} \; 2>/dev/null | head -1 | grep -q .; then
                    needs_expo_modules_core=true
                fi
            fi
            
            # Create Objective-C target first (contains .m, .mm, .h files)
            objc_target_name="${module}ObjC"
            echo "        .target("
            echo "            name: \"$objc_target_name\","
            echo "            dependencies: ["
            echo -n "                .product(name: \"React\", package: \"VSCOReactNativeRuntime\")"
            # NOTE: VSCOExpoModulesCoreObjC should NOT depend on VSCOExpoModulesCore to avoid circular dependency
            # The C++ implementation files are included in VSCOExpoModulesCoreObjC sources instead
            if [ "$objc_target_name" = "VSCOExpoModulesCoreObjC" ]; then
                # No dependency on VSCOExpoModulesCore - fixes circular dependency
                echo ""
            elif [ "$needs_expo_modules_core" = true ]; then
                echo ","
                echo "                .target(name: \"VSCOExpoModulesCore\")"
            else
                echo ""
            fi
            echo "            ],"
            echo "            path: \"Sources/$module\","
            # Exclude Fabric and Tests directories
            exclude_items=()
            if [ "$has_fabric" = true ]; then
                exclude_items+=("Fabric")
            fi
            # Always exclude Tests and TestUtils directories (they contain test dependencies)
            # Only add to exclude if the directory actually exists
            if [ -d "${module_dir}/Tests" ]; then
                exclude_items+=("Tests")
            fi
            if [ -d "${module_dir}/TestUtils" ]; then
                exclude_items+=("TestUtils")
            fi
            if [ ${#exclude_items[@]} -gt 0 ]; then
                echo -n "            exclude: ["
                first=true
                for item in "${exclude_items[@]}"; do
                    if [ "$first" = true ]; then
                        echo -n "\"$item\""
                        first=false
                    else
                        echo -n ", \"$item\""
                    fi
                done
                echo "],  // Exclude Fabric (New Architecture) files and test files"
            fi
            # Output sources if there are objc_files (including C++ files for VSCOExpoModulesCoreObjC)
            # or if there are swift_files (mixed-language target)
            if [ ${#objc_files[@]} -gt 0 ] || [ ${#swift_files[@]} -gt 0 ]; then
                echo -n "            sources: ["
                first=true
                for file in "${objc_files[@]}"; do
                    if [ "$first" = true ]; then
                        echo -n "\"$file\""
                        first=false
                    else
                        echo ","
                        echo -n "                \"$file\""
                    fi
                done
                echo ""
                echo "            ],"
            fi
            echo "            publicHeadersPath: \".\","
            if [ "$needs_header_paths" = true ] && [ ${#subdirs[@]} -gt 0 ]; then
                echo "            cSettings: ["
                echo -n "                .headerSearchPath(\".\")"
                for subdir in "${subdirs[@]}"; do
                    echo ","
                    echo -n "                .headerSearchPath(\"$subdir\")"
                done
                if [ -d "${module_dir}/Stubs" ]; then
                    echo ","
                    echo -n "                .headerSearchPath(\"Stubs\")"
                fi
                echo ""
                echo "            ],"
                echo "            cxxSettings: ["
                echo -n "                .headerSearchPath(\".\")"
                for subdir in "${subdirs[@]}"; do
                    echo ","
                    echo -n "                .headerSearchPath(\"$subdir\")"
                done
                if [ -d "${module_dir}/Stubs" ]; then
                    echo ","
                    echo -n "                .headerSearchPath(\"Stubs\")"
                fi
                echo ""
                echo "            ]"
            else
                echo "            cSettings: ["
                echo "                .headerSearchPath(\".\")"
                echo "            ],"
                echo "            cxxSettings: ["
                echo "                .headerSearchPath(\".\")"
                echo "            ]"
            fi
            echo "        ),"
            
            # Check if Swift files also import ExpoModulesCore
            # Skip if this module IS VSCOExpoModulesCore (it shouldn't depend on itself)
            needs_expo_modules_core_swift=false
            if [ "$module" != "VSCOExpoModulesCore" ] && [ -d "$module_dir" ]; then
                if find "$module_dir" -type f -name "*.swift" -exec grep -l "ExpoModulesCore\|expo-modules-core\|import ExpoModulesCore" {} \; 2>/dev/null | head -1 | grep -q .; then
                    needs_expo_modules_core_swift=true
                fi
            fi
            
            # Create Swift target that depends on Objective-C target
            echo "        .target("
            echo "            name: \"$module\","
            echo "            dependencies: ["
            echo -n "                .product(name: \"React\", package: \"VSCOReactNativeRuntime\"),"
            echo ""
            echo -n "                .target(name: \"$objc_target_name\")"
            if [ "$needs_expo_modules_core_swift" = true ]; then
                echo ","
                echo "                .target(name: \"VSCOExpoModulesCore\")"
            else
                echo ""
            fi
            echo "            ],"
            echo "            path: \"Sources/$module\","
            # Exclude Fabric and Tests directories
            exclude_items=()
            if [ "$has_fabric" = true ]; then
                exclude_items+=("Fabric")
            fi
            # Always exclude Tests and TestUtils directories (they contain test dependencies)
            # Only add to exclude if the directory actually exists
            if [ -d "${module_dir}/Tests" ]; then
                exclude_items+=("Tests")
            fi
            if [ -d "${module_dir}/TestUtils" ]; then
                exclude_items+=("TestUtils")
            fi
            if [ ${#exclude_items[@]} -gt 0 ]; then
                echo -n "            exclude: ["
                first=true
                for item in "${exclude_items[@]}"; do
                    if [ "$first" = true ]; then
                        echo -n "\"$item\""
                        first=false
                    else
                        echo -n ", \"$item\""
                    fi
                done
                echo "],  // Exclude Fabric (New Architecture) files and test files"
            fi
            if [ ${#swift_files[@]} -gt 0 ]; then
                echo -n "            sources: ["
                first=true
                for file in "${swift_files[@]}"; do
                    if [ "$first" = true ]; then
                        echo -n "\"$file\""
                        first=false
                    else
                        echo ","
                        echo -n "                \"$file\""
                    fi
                done
                echo ""
                echo "            ]"
            fi
            echo "        ),"
        else
            # Non-mixed language target - generate single target
        # Check if module imports ExpoModulesCore (for expo packages)
        # Skip if this module IS VSCOExpoModulesCore (it shouldn't depend on itself)
        needs_expo_modules_core=false
        if [ "$module" != "VSCOExpoModulesCore" ] && [ -d "$module_dir" ]; then
            if find "$module_dir" -type f \( -name "*.swift" -o -name "*.m" -o -name "*.mm" -o -name "*.h" \) -exec grep -l "ExpoModulesCore\|expo-modules-core" {} \; 2>/dev/null | head -1 | grep -q .; then
                needs_expo_modules_core=true
            fi
        fi
        
        echo "        .target("
        echo "            name: \"$module\","
        echo "            dependencies: ["
        echo -n "                .product(name: \"React\", package: \"VSCOReactNativeRuntime\")"
        if [ "$needs_expo_modules_core" = true ]; then
            echo ","
            echo "                .target(name: \"VSCOExpoModulesCore\")"
        else
            echo ""
        fi
        echo "            ],"
            echo "            path: \"Sources/$module\","
            
            # Exclude Fabric and Tests directories if they exist (generic for any module)
            exclude_items=()
            if [ "$has_fabric" = true ]; then
                exclude_items+=("Fabric")
            fi
            # Always exclude Tests and TestUtils directories (they contain test dependencies)
            # Only add to exclude if the directory actually exists
            if [ -d "${module_dir}/Tests" ]; then
                exclude_items+=("Tests")
            fi
            if [ -d "${module_dir}/TestUtils" ]; then
                exclude_items+=("TestUtils")
            fi
            if [ ${#exclude_items[@]} -gt 0 ]; then
                echo -n "            exclude: ["
                first=true
                for item in "${exclude_items[@]}"; do
                    if [ "$first" = true ]; then
                        echo -n "\"$item\""
                        first=false
                    else
                        echo -n ", \"$item\""
                    fi
                done
                echo "],  // Exclude Fabric (New Architecture) files and test files - we use Legacy Architecture"
            fi
            
            if [ "$needs_header_paths" = true ] && [ ${#subdirs[@]} -gt 0 ]; then
                # Objective-C only target with subdirectories
                echo "            publicHeadersPath: \".\","
                echo "            cSettings: ["
                echo -n "                .headerSearchPath(\".\")"
                for subdir in "${subdirs[@]}"; do
                    echo ","
                    echo -n "                .headerSearchPath(\"$subdir\")"
                done
                if [ -d "${module_dir}/Stubs" ]; then
                    echo ","
                    echo -n "                .headerSearchPath(\"Stubs\")"
                fi
                echo ""
                echo "            ],"
                echo "            cxxSettings: ["
                echo -n "                .headerSearchPath(\".\")"
                for subdir in "${subdirs[@]}"; do
                    echo ","
                    echo -n "                .headerSearchPath(\"$subdir\")"
                done
                if [ -d "${module_dir}/Stubs" ]; then
                    echo ","
                    echo -n "                .headerSearchPath(\"Stubs\")"
                fi
                echo ""
                echo "            ]"
            elif [ "$has_objc" = true ]; then
                # Objective-C only target (no subdirectories)
                echo "            publicHeadersPath: \".\","
                echo "            cSettings: ["
                echo "                .headerSearchPath(\".\")"
                echo "            ],"
                echo "            cxxSettings: ["
                echo "                .headerSearchPath(\".\")"
                echo "            ]"
            else
                # Swift only target
                echo "            publicHeadersPath: \".\""
            fi
            
            echo "        ),"
        fi
    done
    # Generate VSCONativeKit wrapper target dependencies
    wrapper_deps=""
    for module in "${IOS_MODULES[@]}"; do
        if [ -z "$wrapper_deps" ]; then
            wrapper_deps="\"$module\""
        else
            wrapper_deps="$wrapper_deps, \"$module\""
        fi
    done
    echo "        .target("
    echo "            name: \"VSCONativeKit\","
    echo "            dependencies: [$wrapper_deps],"
    echo "            path: \"Sources/VSCONativeKit\","
    echo "            publicHeadersPath: \".\""
    echo "        )"
else
    echo "        // No iOS modules found"
fi)
    ]
)
EOF

log "  ✅ Updated Package.swift"

# Clean up mixed-language detection temp files
if [ -n "$MIXED_LANG_TEMP_DIR" ] && [ -d "$MIXED_LANG_TEMP_DIR" ]; then
    rm -rf "$MIXED_LANG_TEMP_DIR"
fi

########################################
# Step 7.0.5: Create bridging headers for mixed-language targets
########################################
log "Step 7.0.5: Creating bridging headers for mixed-language targets..."

for module in "${IOS_MODULES[@]}"; do
    module_dir="${KIT_IOS_PACKAGE_DIR}/Sources/$module"
    
    # Check if module has mixed languages
    has_swift=false
    has_objc=false
    if [ -d "$module_dir" ]; then
        if find "$module_dir" -name "*.swift" -type f 2>/dev/null | head -1 | grep -q .; then
            has_swift=true
        fi
        if find "$module_dir" -name "*.m" -o -name "*.mm" -type f 2>/dev/null | head -1 | grep -q .; then
            has_objc=true
        fi
    fi
    
    # Create bridging header for mixed-language targets
    if [ "$has_swift" = true ] && [ "$has_objc" = true ]; then
        bridging_header="${module_dir}/${module}-Bridging-Header.h"
        if [ ! -f "$bridging_header" ]; then
            log "  Creating bridging header for $module..."
            cat > "$bridging_header" <<EOF
//
//  ${module}-Bridging-Header.h
//  ${module}
//
//  Bridging header for mixed-language target (Swift + Objective-C)
//  This header allows Swift code to access Objective-C classes and functions
//

#import <React/RCTBridgeModule.h>
#import <React/RCTViewManager.h>
#import <React/RCTUIManager.h>
#import <React/RCTEventEmitter.h>

// Import all Objective-C headers that Swift needs to access
EOF
            # Find and add all .h files (excluding the bridging header itself)
            find "$module_dir" -name "*.h" -type f ! -name "*-Bridging-Header.h" | while read -r header_file; do
                # Get relative path from module_dir
                rel_path="${header_file#$module_dir/}"
                echo "#import \"$rel_path\"" >> "$bridging_header"
            done
            
            log "  ✅ Created bridging header: ${module}-Bridging-Header.h"
        fi
    fi
done

########################################
# Step 7.1: Create iOS stub headers and fix imports
########################################
log "Step 7.1: Creating iOS stub headers and fixing imports..."

# Generic stub header creation - detect any module that needs ImageLoader stubs
log "  Creating iOS stub headers and fixing imports..."

# Detect modules that import RCTImageLoaderProtocol (any module, not just VSCOSvg)
for module_dir in "${KIT_IOS_PACKAGE_DIR}/Sources"/*; do
    if [ ! -d "$module_dir" ]; then
        continue
    fi
    
    module_name=$(basename "$module_dir")
    
    # Skip VSCONativeKit wrapper module
    if [ "$module_name" = "VSCONativeKit" ]; then
        continue
    fi
    
    # Check if any file in this module imports RCTImageLoaderProtocol or related headers
    if find "$module_dir" -type f \( -name "*.m" -o -name "*.mm" -o -name "*.h" \) -exec grep -l "RCTImageLoaderProtocol\|RCTImageShadowView\|RCTImageURLLoader\|RCTImageView" {} \; 2>/dev/null | head -1 | grep -q .; then
        log "  Creating ImageLoader stub headers for $module_name..."
        mkdir -p "${module_dir}/Stubs"
        
        # Create RCTImageLoaderProtocol.h
        cat > "${module_dir}/Stubs/RCTImageLoaderProtocol.h" <<'STUB_EOF'
/**
 * Stub header for RCTImageLoaderProtocol
 * This is a minimal stub to allow native modules to compile.
 * The actual ImageLoader module should be provided by the consuming app.
 */

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class RCTImageSource;

typedef void (^RCTImageLoaderCancellationBlock)(void);
typedef void (^RCTImageLoaderCompletionBlock)(NSError *error, UIImage *image);
typedef void (^RCTImageLoaderProgressBlock)(int64_t progress, int64_t total);

@protocol RCTImageLoaderProtocol <NSObject>

- (RCTImageLoaderCancellationBlock)loadImageWithURLRequest:(NSURLRequest *)imageURLRequest
                                                  callback:(RCTImageLoaderCompletionBlock)callback;

- (RCTImageLoaderCancellationBlock)loadImageWithURLRequest:(NSURLRequest *)imageURLRequest
                                                  progress:(RCTImageLoaderProgressBlock)progressBlock
                                                  callback:(RCTImageLoaderCompletionBlock)callback;

@end
STUB_EOF
        
        # Create RCTImageShadowView.h
        cat > "${module_dir}/Stubs/RCTImageShadowView.h" <<'STUB_EOF'
/**
 * Stub header for RCTImageShadowView
 * This is a minimal stub to allow native modules to compile.
 */

#import <Foundation/Foundation.h>

@interface RCTImageShadowView : NSObject
@end
STUB_EOF
        
        # Create RCTImageURLLoader.h
        cat > "${module_dir}/Stubs/RCTImageURLLoader.h" <<'STUB_EOF'
/**
 * Stub header for RCTImageURLLoader
 * This is a minimal stub to allow native modules to compile.
 */

#import <Foundation/Foundation.h>

@protocol RCTImageURLLoader <NSObject>
@end
STUB_EOF
        
        # Create RCTImageView.h
        cat > "${module_dir}/Stubs/RCTImageView.h" <<'STUB_EOF'
/**
 * Stub header for RCTImageView
 * This is a minimal stub to allow native modules to compile.
 */

#import <UIKit/UIKit.h>

@interface RCTImageView : UIView
@end
STUB_EOF
        
        log "  ✅ Created ImageLoader stub headers for $module_name"
        
        # Fix any .mm or .m files that import ImageLoader headers
        find "$module_dir" -type f \( -name "*.mm" -o -name "*.m" \) -exec grep -l "RCTImageLoaderProtocol\|RCTImageShadowView\|RCTImageURLLoader\|RCTImageView" {} \; 2>/dev/null | while read file; do
            if [ -f "$file" ]; then
                log "  Fixing imports in $module_name/$(basename "$file")..."
                # Apply the same perl replacement (generic)
                perl -0777 -pi -e 's/#else\n\n#import <React\/RCTImageLoaderProtocol\.h>\n#import <React\/RCTImageShadowView\.h>\n#import <React\/RCTImageURLLoader\.h>\n#import <React\/RCTImageView\.h>\n\n#endif \/\/ RCT_NEW_ARCH_ENABLED/#else\n\n\/\/ Use stub headers if React Native ImageLoader headers are not available\n#if __has_include(<React\/RCTImageLoaderProtocol.h>)\n#import <React\/RCTImageLoaderProtocol.h>\n#else\n#import "RCTImageLoaderProtocol.h"\n#endif\n\n#if __has_include(<React\/RCTImageShadowView.h>)\n#import <React\/RCTImageShadowView.h>\n#else\n#import "RCTImageShadowView.h"\n#endif\n\n#if __has_include(<React\/RCTImageURLLoader.h>)\n#import <React\/RCTImageURLLoader.h>\n#else\n#import "RCTImageURLLoader.h"\n#endif\n\n#if __has_include(<React\/RCTImageView.h>)\n#import <React\/RCTImageView.h>\n#else\n#import "RCTImageView.h"\n#endif\n\n#endif \/\/ RCT_NEW_ARCH_ENABLED/gs' "$file" 2>/dev/null || true
            fi
        done
        
        log "  ✅ Fixed ImageLoader imports for $module_name"
    fi
done

# Generic Foundation/UIKit import fix - ensure all iOS files have necessary imports
# This is a generic fix that applies to all iOS source files, not specific to any library
# Headers and implementation files that use NSObject, NSArray, UIImage, etc. need Foundation/UIKit
log "  Ensuring Foundation/UIKit imports in iOS files..."
find "${KIT_IOS_PACKAGE_DIR}/Sources" -type f \( -name "*.h" -o -name "*.m" -o -name "*.mm" \) | while read file; do
    if [ -f "$file" ]; then
        # Check if file uses Foundation types but doesn't import Foundation/UIKit
        uses_foundation_types=false
        if grep -qE '\b(NSObject|NSArray|NSString|NSDictionary|NSNumber|NSError|NSLog|BOOL|YES|NO)\b' "$file" 2>/dev/null; then
            uses_foundation_types=true
        fi
        
        # Check if file uses UIKit types
        uses_uikit_types=false
        if grep -qE '\b(UIImage|UIView|UIViewController|UIColor|UIFont)\b' "$file" 2>/dev/null; then
            uses_uikit_types=true
        fi
        
        # Add imports if needed
        if [ "$uses_foundation_types" = true ] || [ "$uses_uikit_types" = true ]; then
            # Check if file already has Foundation or UIKit import
            has_foundation=false
            has_uikit=false
            if grep -qE '#import\s+<Foundation/Foundation\.h>|@import\s+Foundation' "$file" 2>/dev/null; then
                has_foundation=true
            fi
            if grep -qE '#import\s+<UIKit/UIKit\.h>|@import\s+UIKit' "$file" 2>/dev/null; then
                has_uikit=true
            fi
            
            # Add missing imports (UIKit includes Foundation, so prefer UIKit if UIKit types are used)
            if [ "$uses_uikit_types" = true ] && [ "$has_uikit" = false ]; then
                module_name=$(echo "$file" | sed "s|${KIT_IOS_PACKAGE_DIR}/Sources/||" | cut -d'/' -f1)
                file_name=$(basename "$file")
                log "  Adding UIKit import to $module_name/$file_name..."
                # Add #import <UIKit/UIKit.h> at the top (UIKit includes Foundation)
                # Find the first line that's not a comment or blank, and add before it
                if grep -q "^#import\|^#if\|^@interface\|^@implementation\|^@class" "$file" 2>/dev/null; then
                    # Add before first #import, #if, @interface, @implementation, or @class
                    perl -pi -e 's/^(#import|#if|@interface|@implementation|@class)/#import <UIKit\/UIKit.h>\n$1/' "$file" 2>/dev/null || true
                else
                    # Add at the very beginning
                    perl -pi -e 's/^(.*)/#import <UIKit\/UIKit.h>\n$1/' "$file" 2>/dev/null || true
                fi
            elif [ "$uses_foundation_types" = true ] && [ "$has_foundation" = false ] && [ "$has_uikit" = false ]; then
                # Only add Foundation if UIKit wasn't added (UIKit includes Foundation)
                module_name=$(echo "$file" | sed "s|${KIT_IOS_PACKAGE_DIR}/Sources/||" | cut -d'/' -f1)
                file_name=$(basename "$file")
                log "  Adding Foundation import to $module_name/$file_name..."
                # Add #import <Foundation/Foundation.h> at the top
                if grep -q "^#import\|^#if\|^@interface\|^@implementation\|^@class" "$file" 2>/dev/null; then
                    # Add before first #import, #if, @interface, @implementation, or @class
                    perl -pi -e 's/^(#import|#if|@interface|@implementation|@class)/#import <Foundation\/Foundation.h>\n$1/' "$file" 2>/dev/null || true
                else
                    # Add at the very beginning
                    perl -pi -e 's/^(.*)/#import <Foundation\/Foundation.h>\n$1/' "$file" 2>/dev/null || true
                fi
            fi
        fi
    fi
done

# Remove duplicate Foundation/UIKit imports
# This is a generic cleanup that applies to all iOS files, not specific to any library
# Add Foundation imports to ALL Swift files (Foundation is required for most Swift code)
log "  Adding Foundation imports to Swift files..."
find "${KIT_IOS_PACKAGE_DIR}/Sources" -type f -name "*.swift" | while read file; do
    if [ -f "$file" ]; then
        # Check if file already has Foundation import
        has_foundation=false
        if grep -qE '^import Foundation\b' "$file" 2>/dev/null; then
            has_foundation=true
        fi
        
        # Add Foundation import if missing (Foundation is required for NSObject, String, Array, etc.)
        if [ "$has_foundation" = false ]; then
            module_name=$(echo "$file" | sed "s|${KIT_IOS_PACKAGE_DIR}/Sources/||" | cut -d'/' -f1)
            file_name=$(basename "$file")
            log "  Adding Foundation import to $module_name/$file_name..."
            
            # Add import Foundation at the top (before any other imports)
            if grep -qE '^import ' "$file" 2>/dev/null; then
                # Add before first import statement
                perl -pi -e 's/^(import )/import Foundation\n$1/' "$file" 2>/dev/null || true
            else
                # Add at the top of file (after copyright/header comments if any)
                perl -0777 -pi -e 's/(^\/\/[^\n]*\n(?:^\/\/[^\n]*\n)*|^\/\*[\s\S]*?\*\/\n*)?/import Foundation\n$1/' "$file" 2>/dev/null || true
            fi
        fi
    fi
done

# Add UIKit imports to Swift files that use UIView or other UIKit types
log "  Adding UIKit imports to Swift files that need them..."
find "${KIT_IOS_PACKAGE_DIR}/Sources" -type f -name "*.swift" | while read file; do
    if [ -f "$file" ]; then
        # Check if file uses UIKit types but doesn't import UIKit
        uses_uikit_types=false
        if grep -qE '\b(UIView|UIViewController|UIColor|UIFont|UIImage|UIButton|UILabel|UIApplication|UIWindow|CGRect|CGSize|CGFloat|UIUserInterfaceIdiom|UIInterfaceOrientationMask|UIBackgroundFetchResult|UIApplicationShortcutItem|UIUserActivityRestoring)\b' "$file" 2>/dev/null; then
            uses_uikit_types=true
        fi
        
        # Check if file already has UIKit import
        has_uikit=false
        if grep -qE '^import UIKit\b' "$file" 2>/dev/null; then
            has_uikit=true
        fi
        
        # Add UIKit import if needed
        if [ "$uses_uikit_types" = true ] && [ "$has_uikit" = false ]; then
            module_name=$(echo "$file" | sed "s|${KIT_IOS_PACKAGE_DIR}/Sources/||" | cut -d'/' -f1)
            file_name=$(basename "$file")
            log "  Adding UIKit import to $module_name/$file_name..."
            
            # Add import UIKit after Foundation import or at the top
            if grep -qE '^import ' "$file" 2>/dev/null; then
                # Add after last import statement
                perl -0777 -pi -e 's/(^import [^\n]+\n(?:^import [^\n]+\n)*)/$1import UIKit\n/' "$file" 2>/dev/null || true
            else
                # Add at the top of file (after copyright/header comments if any)
                perl -0777 -pi -e 's/(^\/\/[^\n]*\n(?:^\/\/[^\n]*\n)*|^\/\*[\s\S]*?\*\/\n*)?/import UIKit\n$1/' "$file" 2>/dev/null || true
            fi
        fi
    fi
done

log "  Removing duplicate Foundation/UIKit imports..."
find "${KIT_IOS_PACKAGE_DIR}/Sources" -type f \( -name "*.h" -o -name "*.m" -o -name "*.mm" \) | while read file; do
    if [ -f "$file" ]; then
        # Count occurrences of UIKit import
        uikit_count=$(grep -c "#import <UIKit/UIKit.h>" "$file" 2>/dev/null || echo "0")
        # Count occurrences of Foundation import
        foundation_count=$(grep -c "#import <Foundation/Foundation.h>" "$file" 2>/dev/null || echo "0")
        
        # Remove duplicates if found
        if [ "$uikit_count" -gt 1 ] || [ "$foundation_count" -gt 1 ]; then
            module_name=$(echo "$file" | sed "s|${KIT_IOS_PACKAGE_DIR}/Sources/||" | cut -d'/' -f1)
            file_name=$(basename "$file")
            log "  Removing duplicate imports in $module_name/$file_name..."
            
            # Remove duplicate UIKit imports (keep only the first one)
            # Use awk to keep first occurrence and remove rest
            awk '!seen_ui || !/^#import <UIKit\/UIKit\.h>$/ { if (/^#import <UIKit\/UIKit\.h>$/) seen_ui=1; print }' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file" 2>/dev/null || true
            
            # Remove duplicate Foundation imports (keep only the first one)
            awk '!seen_foundation || !/^#import <Foundation\/Foundation\.h>$/ { if (/^#import <Foundation\/Foundation\.h>$/) seen_foundation=1; print }' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file" 2>/dev/null || true
            
            # If both UIKit and Foundation are present, remove Foundation (UIKit includes Foundation)
            if grep -q "#import <UIKit/UIKit.h>" "$file" 2>/dev/null && grep -q "#import <Foundation/Foundation.h>" "$file" 2>/dev/null; then
                # Remove Foundation import if UIKit is present
                perl -pi -e 's/^#import <Foundation\/Foundation\.h>$//g' "$file" 2>/dev/null || true
                # Remove blank lines left by removal
                perl -pi -e 's/^\n\n+/\n/g' "$file" 2>/dev/null || true
            fi
        fi
    fi
done

# Fix ExpoModulesCore imports in VSCOExpoModulesCore - replace module imports with local imports
# Since we renamed the module, files within VSCOExpoModulesCore should use local imports
log "  Fixing ExpoModulesCore imports in VSCOExpoModulesCore..."
find "${KIT_IOS_PACKAGE_DIR}/Sources/VSCOExpoModulesCore" -type f \( -name "*.h" -o -name "*.m" -o -name "*.mm" \) | while read file; do
    if [ -f "$file" ]; then
        # Replace <ExpoModulesCore/Header.h> with "Header.h" for local headers
        if grep -qE '#import <ExpoModulesCore/' "$file" 2>/dev/null; then
            module_name=$(echo "$file" | sed "s|${KIT_IOS_PACKAGE_DIR}/Sources/||" | cut -d'/' -f1)
            file_name=$(basename "$file")
            log "  Fixing ExpoModulesCore imports in $module_name/$file_name..."
            
            # Replace <ExpoModulesCore/Header.h> with "Header.h"
            perl -pi -e 's/#import <ExpoModulesCore\/([^>]+)>/#import "$1"/g' "$file" 2>/dev/null || true
        fi
        
        # Fix Swift.h imports - replace ExpoModulesCore-Swift.h with VSCOExpoModulesCore-Swift.h
        # Also make the import conditional with __has_include since the Swift header is generated during build
        if grep -qE 'ExpoModulesCore-Swift\.h' "$file" 2>/dev/null; then
            module_name=$(echo "$file" | sed "s|${KIT_IOS_PACKAGE_DIR}/Sources/||" | cut -d'/' -f1)
            file_name=$(basename "$file")
            log "  Fixing Swift.h import in $module_name/$file_name..."
            
            # Replace ExpoModulesCore-Swift.h with VSCOExpoModulesCore-Swift.h
            perl -pi -e 's/ExpoModulesCore-Swift\.h/VSCOExpoModulesCore-Swift.h/g' "$file" 2>/dev/null || true
            # Also fix module-style imports
            perl -pi -e 's/<ExpoModulesCore\/ExpoModulesCore-Swift\.h>/<VSCOExpoModulesCore\/VSCOExpoModulesCore-Swift.h>/g' "$file" 2>/dev/null || true
        fi
        
        # Make Swift.h imports conditional with __has_include (the Swift header is generated during build)
        # However, add a forward declaration fallback for Swift classes that are needed before the header is generated
        if [[ "$file" == *"Swift.h" ]]; then
            if grep -qE '#import.*VSCOExpoModulesCore-Swift\.h' "$file" 2>/dev/null && ! grep -qE '__has_include.*VSCOExpoModulesCore-Swift|@class EXAppContext' "$file" 2>/dev/null; then
                module_name=$(echo "$file" | sed "s|${KIT_IOS_PACKAGE_DIR}/Sources/||" | cut -d'/' -f1)
                file_name=$(basename "$file")
                log "  Making Swift.h import conditional with fallback in $module_name/$file_name..."
                
                # Replace the endif with a fallback forward declaration
                perl -0777 -pi -e 's/(#elif __has_include\("VSCOExpoModulesCore-Swift\.h"\)\n#import "VSCOExpoModulesCore-Swift\.h"\n#endif)/$1\n#else\n\/\/ Swift header not generated yet - forward declare EXAppContext for now\n\/\/ The actual definition will be available once the Swift target builds\n@class EXAppContext;\n#endif/g' "$file" 2>/dev/null || true
                
                # If the pattern doesn't match, try adding the fallback after the last #endif
                if ! grep -qE '@class EXAppContext' "$file" 2>/dev/null; then
                    perl -0777 -pi -e 's/(#endif\s*$)/#else\n\/\/ Swift header not generated yet - forward declare EXAppContext for now\n\/\/ The actual definition will be available once the Swift target builds\n@class EXAppContext;\n#endif/g' "$file" 2>/dev/null || true
                fi
            fi
        fi
    fi
done

# Fix Fabric-related imports - make them conditional since we exclude Fabric directory
log "  Fixing Fabric-related imports (making them conditional)..."
find "${KIT_IOS_PACKAGE_DIR}/Sources/VSCOExpoModulesCore" -type f \( -name "*.h" -o -name "*.m" -o -name "*.mm" \) | while read file; do
    if [ -f "$file" ]; then
        # Check if file imports ExpoFabricViewObjC.h unconditionally
        if grep -qE '^#import "ExpoFabricViewObjC\.h"$' "$file" 2>/dev/null; then
            module_name=$(echo "$file" | sed "s|${KIT_IOS_PACKAGE_DIR}/Sources/||" | cut -d'/' -f1)
            file_name=$(basename "$file")
            log "  Making ExpoFabricViewObjC.h import conditional in $module_name/$file_name..."
            
            # Replace unconditional import with conditional import
            perl -pi -e 's/^#import "ExpoFabricViewObjC\.h"$/#if RCT_NEW_ARCH_ENABLED\n#import "ExpoFabricViewObjC.h"\n#endif/g' "$file" 2>/dev/null || true
        fi
        
        # Check if file imports RCTComponentViewFactory.h unconditionally (Fabric-related)
        if grep -qE '#import <React/RCTComponentViewFactory\.h>' "$file" 2>/dev/null && ! grep -qE '__has_include.*RCTComponentViewFactory' "$file" 2>/dev/null; then
            module_name=$(echo "$file" | sed "s|${KIT_IOS_PACKAGE_DIR}/Sources/||" | cut -d'/' -f1)
            file_name=$(basename "$file")
            log "  Making RCTComponentViewFactory.h import conditional in $module_name/$file_name..."
            
            # Replace unconditional import with conditional import
            perl -pi -e 's/^#import <React\/RCTComponentViewFactory\.h>/#if __has_include(<React\/RCTComponentViewFactory.h>)\n#import <React\/RCTComponentViewFactory.h>\n#endif/g' "$file" 2>/dev/null || true
        fi
    fi
done

# Fix JSI header imports - JSI headers are provided by React Native
# React Native exposes JSI headers as <jsi/jsi.h> through its header search paths
# The React product should make these headers available, so keep as <jsi/jsi.h>
# Convert #import to #include for C++ files
# Note: jsi-inl.h is an inline implementation file that requires jsi.h to be included first
# We should NOT use jsi-inl.h directly - use jsi/jsi.h instead
log "  Fixing JSI header imports..."
find "${KIT_IOS_PACKAGE_DIR}/Sources" -type f \( -name "*.h" -o -name "*.mm" \) | while read file; do
    if [ -f "$file" ]; then
        # Check if file uses #import for jsi/jsi.h (should be #include for C++)
        if grep -qE '#import <jsi/jsi\.h>' "$file" 2>/dev/null; then
            module_name=$(echo "$file" | sed "s|${KIT_IOS_PACKAGE_DIR}/Sources/||" | cut -d'/' -f1)
            file_name=$(basename "$file")
            log "  Converting jsi/jsi.h import to include in $module_name/$file_name..."
            
            # Replace #import with #include for C++ headers
            perl -pi -e 's/#import <jsi\/jsi\.h>/#include <jsi\/jsi.h>/g' "$file" 2>/dev/null || true
        fi
        
        # Revert jsi-inl.h back to jsi/jsi.h if it was incorrectly changed
        # jsi-inl.h is an inline implementation file, not a standalone header
        if grep -qE '#include <ReactCommon/jsi/jsi/jsi-inl\.h>' "$file" 2>/dev/null; then
            module_name=$(echo "$file" | sed "s|${KIT_IOS_PACKAGE_DIR}/Sources/||" | cut -d'/' -f1)
            file_name=$(basename "$file")
            log "  Reverting jsi-inl.h to jsi/jsi.h in $module_name/$file_name..."
            
            # Replace with standard jsi/jsi.h path (React product should expose this)
            perl -pi -e 's/#include <ReactCommon\/jsi\/jsi\/jsi-inl\.h>/#include <jsi\/jsi.h>/g' "$file" 2>/dev/null || true
        fi
        
        # Add fallback for jsi/jsi.h in header files if it's not already conditional
        # This ensures JSI headers are accessible even if React product doesn't expose them correctly
        if [[ "$file" == *.h ]] && grep -qE '#include <jsi/jsi\.h>' "$file" 2>/dev/null && ! grep -qE '__has_include.*jsi' "$file" 2>/dev/null; then
            module_name=$(echo "$file" | sed "s|${KIT_IOS_PACKAGE_DIR}/Sources/||" | cut -d'/' -f1)
            file_name=$(basename "$file")
            log "  Adding JSI header fallback to $module_name/$file_name..."
            
            # Add fallback: if jsi/jsi.h is not found, try jsilib.h
            perl -0777 -pi -e 's/(#ifdef __cplusplus\s*\n)(#include <jsi\/jsi\.h>)/$1#if __has_include(<jsi\/jsi.h>)\n$2\n#elif __has_include(<ReactCommon\/jsi\/jsi\/jsilib.h>)\n#include <ReactCommon\/jsi\/jsi\/jsilib.h>\n#else\n#include <ReactCommon\/jsi\/jsi\/jsilib.h>\n#endif/g' "$file" 2>/dev/null || true
        fi
    fi
done

# Fix ReactCommon header imports - ReactCommon headers may not be accessible through the React product
# Make ReactCommon imports conditional with __has_include to handle cases where headers are not available
# This is especially important for TurboModule headers which may not be in all React Native versions
log "  Making ReactCommon header imports conditional..."
find "${KIT_IOS_PACKAGE_DIR}/Sources" -type f \( -name "*.h" -o -name "*.mm" \) | while read file; do
    if [ -f "$file" ]; then
        # Handle RCTTurboModule.h specifically (common case)
        if grep -qE '#import <ReactCommon/RCTTurboModule\.h>' "$file" 2>/dev/null && ! grep -qE '#if __has_include.*RCTTurboModule' "$file" 2>/dev/null; then
            module_name=$(echo "$file" | sed "s|${KIT_IOS_PACKAGE_DIR}/Sources/||" | cut -d'/' -f1)
            file_name=$(basename "$file")
            log "  Making RCTTurboModule import conditional in $module_name/$file_name..."
            
            # Replace unconditional import with conditional import
            perl -0777 -pi -e 's/#import <ReactCommon\/RCTTurboModule\.h>/#if __has_include(<ReactCommon\/RCTTurboModule.h>)\n#import <ReactCommon\/RCTTurboModule.h>\n#endif/g' "$file" 2>/dev/null || true
        fi
        
        # Fix ExpoBridgeModule.mm - add missing EXJSIInstaller.h import
        if [[ "$file" == *"ExpoBridgeModule.mm" ]]; then
            # Check if file uses EXJavaScriptRuntimeManager but doesn't import EXJSIInstaller.h
            if grep -qE 'EXJavaScriptRuntimeManager' "$file" 2>/dev/null && ! grep -qE '#import.*EXJSIInstaller\.h' "$file" 2>/dev/null; then
                module_name=$(echo "$file" | sed "s|${KIT_IOS_PACKAGE_DIR}/Sources/||" | cut -d'/' -f1)
                file_name=$(basename "$file")
                log "  Adding EXJSIInstaller.h import to $module_name/$file_name..."
                # Add import after Swift.h import
                perl -pi -e 's/(#import "Swift\.h")/$1\n#import "EXJSIInstaller.h"/g' "$file" 2>/dev/null || true
            fi
        fi
    fi
done

# Fix missing imports for ExpoBridgeModule.mm
log "  Fixing missing imports for ExpoBridgeModule.mm..."
expo_bridge_module="${KIT_IOS_PACKAGE_DIR}/Sources/VSCOExpoModulesCore/Core/ExpoBridgeModule.mm"
if [ -f "$expo_bridge_module" ]; then
    # Check if file uses EXJavaScriptRuntimeManager but doesn't import EXJSIInstaller.h
    if grep -qE 'EXJavaScriptRuntimeManager' "$expo_bridge_module" 2>/dev/null && ! grep -qE '#import.*EXJSIInstaller\.h' "$expo_bridge_module" 2>/dev/null; then
        log "  Adding EXJSIInstaller.h import to ExpoBridgeModule.mm..."
        # Add import after Swift.h import
        perl -pi -e 's/(#import "Swift\.h")/$1\n#import "EXJSIInstaller.h"/g' "$expo_bridge_module" 2>/dev/null || true
    fi
fi

# Continue with ReactCommon imports
log "  Making ReactCommon header imports conditional (continued)..."
find "${KIT_IOS_PACKAGE_DIR}/Sources" -type f \( -name "*.h" -o -name "*.mm" \) | while read file; do
    if [ -f "$file" ]; then
        # Handle other ReactCommon imports that are not already conditional
        # Skip files that already have __has_include checks for ReactCommon
        if grep -qE '#import <ReactCommon/[^>]+\.h>' "$file" 2>/dev/null; then
            # Check each ReactCommon import individually
            while IFS= read -r line; do
                if echo "$line" | grep -qE '#import <ReactCommon/[^>]+\.h>' && ! echo "$line" | grep -qE 'RCTTurboModule|RCTRuntimeExecutor'; then
                    reactcommon_header=$(echo "$line" | sed 's/.*#import <\(ReactCommon\/[^>]*\)>.*/\1/')
                    if [ -n "$reactcommon_header" ]; then
                        # Check if this specific import is already conditional in the file
                        if ! grep -qE "#if __has_include.*$reactcommon_header" "$file" 2>/dev/null; then
                            module_name=$(echo "$file" | sed "s|${KIT_IOS_PACKAGE_DIR}/Sources/||" | cut -d'/' -f1)
                            file_name=$(basename "$file")
                            log "  Making ReactCommon import conditional in $module_name/$file_name: $reactcommon_header"
                            
                            # Replace unconditional import with conditional import
                            perl -0777 -pi -e "s|#import <$reactcommon_header>|#if __has_include(<$reactcommon_header>)\n#import <$reactcommon_header>\n#endif|g" "$file" 2>/dev/null || true
                        fi
                    fi
                fi
            done < <(grep -E '#import <ReactCommon/[^>]+\.h>' "$file" 2>/dev/null)
        fi
    fi
done

# -----------------------------------------------------------------------------
# VSCO ExpoModulesCore runtime shims (RN 0.81.5 / VSCOReactNativeRuntime)
# -----------------------------------------------------------------------------
# Some RN distributions we ship (VSCOReactNativeRuntime) don't expose all ReactCommon headers publicly.
# ExpoModulesCore's ObjC++ code expects:
# - <ReactCommon/CallInvoker.h>
# - <ReactCommon/TurboModuleUtils.h>
# - <react/bridging/CallbackWrapper.h>
# We provide minimal *declaration* shims inside VSCOExpoModulesCore so compilation links against the
# implementations exported by the RN runtime binary.
#
# Additionally, to avoid ABI/vtable mismatches that can call Instance::JSCallInvoker::invokeSync(),
# we patch a few call sites to use RN's non-virtual overloads.
if [ -d "${KIT_IOS_PACKAGE_DIR}/Sources/VSCOExpoModulesCore" ]; then
    log "  Adding VSCOExpoModulesCore ReactCommon shims (CallInvoker/TurboModuleUtils/CallbackWrapper)..."

    expo_core_dir="${KIT_IOS_PACKAGE_DIR}/Sources/VSCOExpoModulesCore"
    mkdir -p "${expo_core_dir}/ReactCommon"
    mkdir -p "${expo_core_dir}/react/bridging"

    # Shim: ReactCommon/CallInvoker.h
    cat > "${expo_core_dir}/ReactCommon/CallInvoker.h" <<'EOF'
// Shim header for React Native's ReactCommon/CallInvoker.h.
// Some distributions used in this repo don't expose the full ReactCommon headers publicly,
// but ExpoModulesCore needs the CallInvoker type for scheduling work on the JS thread.
//
// If the real header exists later in the include search paths, prefer it.
#pragma once

#if __has_include_next(<ReactCommon/CallInvoker.h>)
#include_next <ReactCommon/CallInvoker.h>
#else

#ifdef __cplusplus

#include <functional>

// SchedulerPriority is part of RN callinvoker. Include it at global scope (NOT inside namespaces),
// otherwise its internal `namespace facebook::react { ... }` gets nested and breaks symbol lookup.
#if __has_include(<ReactCommon/callinvoker/ReactCommon/SchedulerPriority.h>)
#include <ReactCommon/callinvoker/ReactCommon/SchedulerPriority.h>
#endif

namespace facebook {
namespace jsi {
class Runtime;
} // namespace jsi
namespace react {

// RN 0.81+ CallInvoker API uses CallFunc = std::function<void(jsi::Runtime&)>
using CallFunc = std::function<void(::facebook::jsi::Runtime &)>;

/**
 * NOTE: This shim must match the ABI of the React Native runtime that ships in VSCOReactNativeRuntime.
 * RN 0.81.5 exports (non-virtual) overloads:
 * - CallInvoker::invokeAsync(std::function<void()>)
 * - CallInvoker::invokeSync(std::function<void()>)
 * and an overload:
 * - CallInvoker::invokeAsync(SchedulerPriority, CallFunc)
 * alongside the core virtual methods:
 * - invokeAsync(CallFunc)
 * - invokeSync(CallFunc)
 */
class CallInvoker {
public:
  virtual ~CallInvoker() = default;

  // Core virtual interface implemented by JSCallInvoker, RuntimeSchedulerCallInvoker, etc.
  virtual void invokeAsync(CallFunc &&func) noexcept = 0;
  virtual void invokeSync(CallFunc &&func) = 0;

  // Priority-aware overload provided by RN. Keep it NON-virtual to avoid vtable/ABI mismatch.
#if __has_include(<ReactCommon/callinvoker/ReactCommon/SchedulerPriority.h>)
  void invokeAsync(::facebook::react::SchedulerPriority priority, CallFunc &&func) noexcept;
#endif

  // Convenience overloads implemented in RN (operate on std::function<void()>).
  void invokeAsync(std::function<void(void)> &&func) noexcept;
  void invokeSync(std::function<void(void)> &&func);
};

} // namespace react
} // namespace facebook

#endif // __cplusplus

#endif

EOF

    # Shim: ReactCommon/TurboModuleUtils.h
    cat > "${expo_core_dir}/ReactCommon/TurboModuleUtils.h" <<'EOF'
// Shim header for React Native's TurboModuleUtils.
// Some React Native distributions (like VSCOReactNativeRuntime) don't ship `ReactCommon/TurboModuleUtils.h`
// in the public headers. ExpoModulesCore's JSI bridge uses `createPromiseAsJSIValue`, so we provide a
// declaration shim that links against the real implementation shipped in the React Native runtime binary.
//
// If the real header exists later in the include search paths, we prefer it.
//
// This file is Objective-C++/C++ only.
#pragma once

#if __has_include_next(<ReactCommon/TurboModuleUtils.h>)
// Prefer the real RN header if it exists.
#include_next <ReactCommon/TurboModuleUtils.h>
#else

#ifdef __cplusplus
// JSI header location differs depending on distribution.
// Prefer standard include if available, otherwise fall back to vendored headers in VSCOExpoModulesCore.
#if __has_include(<jsi/jsi.h>)
#include <jsi/jsi.h>
#elif __has_include("jsi/jsi.h")
#include "jsi/jsi.h"
#else
#include "JSI/jsi/jsi.h"
#endif

#include <memory>
#include <functional>
#include <string>

namespace facebook {
namespace react {

// Forward declare CallInvoker to match RN signature surface.
class CallInvoker;

// RN 0.81.5 exports a `facebook::react::Promise` class (not just a struct).
class Promise {
public:
  Promise(facebook::jsi::Runtime &runtime, facebook::jsi::Function resolve, facebook::jsi::Function reject);
  virtual ~Promise();

  void resolve(facebook::jsi::Value const &value);
  void reject(std::string const &message);
};

/**
 * Declares the RN helper exported from the runtime binary.
 * Mangled symbol (RN 0.81.5): facebook::react::createPromiseAsJSIValue(jsi::Runtime&, std::function<void(jsi::Runtime&, std::shared_ptr<Promise>)>&&)
 */
facebook::jsi::Value createPromiseAsJSIValue(
  facebook::jsi::Runtime &runtime,
  std::function<void(facebook::jsi::Runtime &, std::shared_ptr<facebook::react::Promise>)> &&promiseSetup
);

} // namespace react
} // namespace facebook

// ExpoModulesCore calls `createPromiseAsJSIValue(...)` unqualified in ObjC++ files.
using facebook::react::createPromiseAsJSIValue;

#endif // __cplusplus

#endif

EOF

    # Shim: react/bridging/CallbackWrapper.h
    cat > "${expo_core_dir}/react/bridging/CallbackWrapper.h" <<'EOF'
/*
 * Minimal declaration shim for React Native's <react/bridging/CallbackWrapper.h>.
 *
 * VSCOReactNativeRuntime (RN 0.81.5) exports `facebook::react::CallbackWrapper::createWeak(...)`
 * in the binary, but doesn't ship the public header. We provide a compatible declaration so that
 * ExpoModulesCore can compile and link against the real implementation in the RN runtime.
 */

#pragma once

#ifdef __cplusplus

// JSI header location differs depending on distribution.
#if __has_include(<jsi/jsi.h>)
#include <jsi/jsi.h>
#elif __has_include("jsi/jsi.h")
#include "jsi/jsi.h"
#else
#include "JSI/jsi/jsi.h"
#endif

#include <memory>

// CallInvoker header location also differs; ExpoModulesCore provides a shim at <ReactCommon/CallInvoker.h>.
#if __has_include(<ReactCommon/CallInvoker.h>)
#include <ReactCommon/CallInvoker.h>
#endif

namespace facebook::react {

class CallbackWrapper {
public:
  static std::weak_ptr<CallbackWrapper> createWeak(
    facebook::jsi::Function &&callback,
    facebook::jsi::Runtime &runtime,
    std::shared_ptr<facebook::react::CallInvoker> jsInvoker
  );

  virtual ~CallbackWrapper() = default;

  virtual facebook::jsi::Function &callback() = 0;
  virtual facebook::jsi::Runtime &runtime() = 0;
  virtual std::shared_ptr<facebook::react::CallInvoker> &jsInvoker() = 0;
  virtual void destroy() = 0;
};

} // namespace facebook::react

#endif // __cplusplus

EOF

    log "  ✅ Added ExpoModulesCore shim headers"

    # Patch call sites to avoid direct virtual CallInvoker dispatch (prevents invokeSync() aborts).
    # These patches are intentionally small and pattern-based.
    if [ -f "${expo_core_dir}/JSI/EXJavaScriptRuntime.mm" ]; then
        log "  Patching EXJavaScriptRuntime.mm to avoid virtual CallInvoker dispatch..."
        # Replace the virtual CallFunc signature (jsi::Runtime&) with RN's non-virtual std::function<void()> overload.
        perl -pi -e 's/_jsCallInvoker->invokeAsync\(\[block\]\(jsi::Runtime\s*&\)\s*\{\s*block\(\);\s*\}\s*\);/_jsCallInvoker->invokeAsync([block]() { block(); });/g' "${expo_core_dir}/JSI/EXJavaScriptRuntime.mm" 2>/dev/null || true
    fi

    if [ -f "${expo_core_dir}/JSI/EXJSIConversions.mm" ]; then
        log "  Patching EXJSIConversions.mm to avoid virtual CallInvoker dispatch..."
        perl -pi -e 's/invokeAsync\(\[weakWrapper, responses\]\(jsi::Runtime\s*&\)\s*\{/invokeAsync([weakWrapper, responses]() {/g' "${expo_core_dir}/JSI/EXJSIConversions.mm" 2>/dev/null || true
    fi

    if [ -f "${expo_core_dir}/JSI/EXJSIUtils.mm" ]; then
        log "  Patching EXJSIUtils.mm promise settlement scheduling..."
        # Add priority overload (non-virtual) for resolve/reject scheduling.
        perl -pi -e 's/jsInvoker->invokeAsync\(\[promise,/jsInvoker->invokeAsync(::facebook::react::SchedulerPriority::NormalPriority, [promise,/g' "${expo_core_dir}/JSI/EXJSIUtils.mm" 2>/dev/null || true
    fi
fi

# Fix RCTCallInvoker imports - React Native uses ReactCommon/CallInvoker.h but it might not be available
# Use forward declaration or check if we need to include it differently
log "  Fixing RCTCallInvoker/CallInvoker imports..."
find "${KIT_IOS_PACKAGE_DIR}/Sources/VSCOExpoModulesCore" -type f \( -name "*.h" -o -name "*.m" -o -name "*.mm" \) | while read file; do
    if [ -f "$file" ]; then
        # Check if file imports React/RCTCallInvoker.h
        if grep -qE '#import <React/RCTCallInvoker\.h>' "$file" 2>/dev/null; then
            module_name=$(echo "$file" | sed "s|${KIT_IOS_PACKAGE_DIR}/Sources/||" | cut -d'/' -f1)
            file_name=$(basename "$file")
            log "  Fixing RCTCallInvoker import in $module_name/$file_name..."
            
            # Replace React/RCTCallInvoker.h with ReactCommon/CallInvoker.h
            perl -pi -e 's/#import <React\/RCTCallInvoker\.h>/#import <ReactCommon\/CallInvoker.h>/g' "$file" 2>/dev/null || true
        fi
        
        # Check if file imports ReactCommon/CallInvoker.h but it's not found
        # Use forward declaration instead if it's only used as a pointer/reference
        if grep -qE '#import <ReactCommon/CallInvoker\.h>' "$file" 2>/dev/null; then
            # If we provided a CallInvoker shim inside VSCOExpoModulesCore, keep the include.
            # It may be required for SchedulerPriority and other types used in ObjC++ sources.
            if [ ! -f "${KIT_IOS_PACKAGE_DIR}/Sources/VSCOExpoModulesCore/ReactCommon/CallInvoker.h" ]; then
                # Check if CallInvoker is only used as std::shared_ptr (forward declaration is enough)
                if grep -qE 'std::shared_ptr<.*CallInvoker>' "$file" 2>/dev/null && ! grep -qE 'CallInvoker\s+[^{]' "$file" 2>/dev/null; then
                    module_name=$(echo "$file" | sed "s|${KIT_IOS_PACKAGE_DIR}/Sources/||" | cut -d'/' -f1)
                    file_name=$(basename "$file")
                    log "  Replacing ReactCommon/CallInvoker.h with forward declaration in $module_name/$file_name..."
                    
                    # Replace import with forward declaration
                    perl -0777 -pi -e 's/#import <ReactCommon\/CallInvoker\.h>\n?/#ifdef __cplusplus\nnamespace facebook { namespace react { class CallInvoker; } }\n#endif\n/g' "$file" 2>/dev/null || true
                fi
            fi
        fi
    fi
done

# Fix Objective-C boolean literals (false -> NO, true -> YES)
# This is a generic fix that applies to all Objective-C files, not specific to any library
log "  Fixing Objective-C boolean literals..."
find "${KIT_IOS_PACKAGE_DIR}/Sources" -type f \( -name "*.m" -o -name "*.mm" \) | while read file; do
    if [ -f "$file" ]; then
        # Check if file uses C++ boolean literals (false/true) instead of Objective-C (NO/YES)
        if grep -qE '\b(false|true)\b' "$file" 2>/dev/null; then
            module_name=$(echo "$file" | sed "s|${KIT_IOS_PACKAGE_DIR}/Sources/||" | cut -d'/' -f1)
            file_name=$(basename "$file")
            log "  Fixing boolean literals in $module_name/$file_name..."
            # Replace false with NO and true with YES (but be careful not to replace in strings or comments)
            # Use word boundaries to avoid replacing "false" in variable names
            perl -pi -e 's/\bfalse\b/NO/g; s/\btrue\b/YES/g' "$file" 2>/dev/null || true
        fi
    fi
done

# Generic RCTConvert import fix - detect any module that uses RCTConvert
log "  Fixing RCTConvert imports..."

# For .m files (Objective-C only): use @import React;
# For .h files with category declarations: use @import React; (works with SPM modules)
# For .h files without categories: keep #import <React/RCTConvert.h> (C++ compatibility)
# For .mm files (C++): keep #import <React/RCTConvert.h> (C++ compatibility)

# First, fix .m files
find "${KIT_IOS_PACKAGE_DIR}/Sources" -type f -name "*.m" -exec grep -l "#import <React/RCTConvert.h>" {} \; 2>/dev/null | while read file; do
    if [ -f "$file" ]; then
        # Extract module name from path (e.g., Sources/VSCOSafeAreaContext/file.m -> VSCOSafeAreaContext)
        module_name=$(echo "$file" | sed "s|${KIT_IOS_PACKAGE_DIR}/Sources/||" | cut -d'/' -f1)
        file_name=$(basename "$file")
        log "  Fixing RCTConvert import in $module_name/$file_name (Objective-C file)..."
        perl -pi -e 's/#import <React\/RCTConvert\.h>/@import React;/g' "$file" 2>/dev/null || true
    fi
done

# For .h files: convert @import React; back to #import <React/RCTConvert.h>
# Headers can be included in C++ files (.mm), and @import doesn't work in C++ without modules enabled
# This is a generic fix that applies to all header files, not specific to any library
find "${KIT_IOS_PACKAGE_DIR}/Sources" -type f -name "*.h" -exec grep -l "@import React;" {} \; 2>/dev/null | while read file; do
    if [ -f "$file" ]; then
        module_name=$(echo "$file" | sed "s|${KIT_IOS_PACKAGE_DIR}/Sources/||" | cut -d'/' -f1)
        file_name=$(basename "$file")
        log "  Fixing RCTConvert import in $module_name/$file_name (header file, using #import for C++ compatibility)..."
        # Replace @import React; with #import <React/RCTConvert.h> in header files
        # Headers must use #import because they can be included in C++ files
        # Handle both standalone @import React; and @import React; followed by other content
        perl -pi -e 's/@import React;/#import <React\/RCTConvert.h>/g' "$file" 2>/dev/null || true
        # Clean up any malformed patterns like @import#import that might have been created
        perl -pi -e 's/@import#import/#import/g' "$file" 2>/dev/null || true
    fi
done

# For .mm files: ensure they use #import <React/RCTConvert.h> (NOT @import)
# C++ files cannot use @import when C++ modules are disabled
# This is a generic fix that applies to all C++ files, not specific to any library
find "${KIT_IOS_PACKAGE_DIR}/Sources" -type f -name "*.mm" -exec grep -l "@import React;" {} \; 2>/dev/null | while read file; do
    if [ -f "$file" ]; then
        module_name=$(echo "$file" | sed "s|${KIT_IOS_PACKAGE_DIR}/Sources/||" | cut -d'/' -f1)
        file_name=$(basename "$file")
        log "  Fixing RCTConvert import in $module_name/$file_name (C++ file, using #import)..."
        # Replace @import React; with #import <React/RCTConvert.h> in C++ files
        perl -pi -e 's/@import React;/#import <React\/RCTConvert.h>/g' "$file" 2>/dev/null || true
        # Clean up any malformed patterns like @import#import that might have been created
        perl -pi -e 's/@import#import/#import/g' "$file" 2>/dev/null || true
    fi
done

# For headers that include other headers with RCTConvert categories, ensure React is imported
# This fixes module visibility issues when headers are included transitively
log "  Ensuring React import in headers that include RCTConvert category headers..."
find "${KIT_IOS_PACKAGE_DIR}/Sources" -type f -name "*.h" | while read header_file; do
    if [ -f "$header_file" ]; then
        # Check if this header includes another header that declares an RCTConvert category
        if grep -q "@interface RCTConvert" "$header_file" 2>/dev/null; then
            # This header itself declares a category
            module_name=$(echo "$header_file" | sed "s|${KIT_IOS_PACKAGE_DIR}/Sources/||" | cut -d'/' -f1)
            file_name=$(basename "$header_file")
            
            # Check if this header is included in any .mm (C++) files
            # If so, we must use #import instead of @import (C++ modules are disabled)
            header_basename=$(basename "$header_file" .h)
            is_included_in_cpp=false
            if find "${KIT_IOS_PACKAGE_DIR}/Sources" -name "*.mm" -type f -exec grep -l "#import.*${header_basename}\.h\|#include.*${header_basename}\.h" {} \; 2>/dev/null | grep -q .; then
                is_included_in_cpp=true
            fi
            
            if [ "$is_included_in_cpp" = true ]; then
                # Header is included in C++ files - use #import (works in both .m and .mm)
                if ! grep -q "#import <React/RCTConvert.h>" "$header_file" 2>/dev/null; then
                    log "  Adding RCTConvert import to $module_name/$file_name (category declaration, included in C++ files, using #import)..."
                    # Remove any @import React.Base.RCTConvert; first
                    perl -pi -e 's/@import React\.Base\.RCTConvert;//g' "$header_file" 2>/dev/null || true
                    # Add #import <React/RCTConvert.h> after Foundation import or at the top
                    if grep -q "#import <Foundation/Foundation.h>" "$header_file" 2>/dev/null; then
                        perl -pi -e 's/(#import <Foundation\/Foundation\.h>)/$1\n#import <React\/RCTConvert.h>/' "$header_file" 2>/dev/null || true
                    else
                        # Add at the top after any existing imports
                        perl -pi -e 's/(^#import.*\n)/$1#import <React\/RCTConvert.h>\n/' "$header_file" 2>/dev/null || true
                    fi
                fi
            else
                # Header is only included in .m files - use @import React.Base.RCTConvert; for module compatibility
                # This ensures module compatibility when .m files use @import React;
                if grep -q "#import <React/RCTConvert.h>" "$header_file" 2>/dev/null; then
                    log "  Updating RCTConvert import in $module_name/$file_name (category declaration, using @import)..."
                    perl -pi -e 's/#import <React\/RCTConvert\.h>/@import React.Base.RCTConvert;/g' "$header_file" 2>/dev/null || true
                elif ! grep -q "@import React" "$header_file" 2>/dev/null; then
                    log "  Adding RCTConvert import to $module_name/$file_name (has category declaration)..."
                    # Add @import React.Base.RCTConvert; after Foundation import or at the top
                    if grep -q "#import <Foundation/Foundation.h>" "$header_file" 2>/dev/null; then
                        perl -pi -e 's/(#import <Foundation\/Foundation\.h>)/$1\n@import React.Base.RCTConvert;/' "$header_file" 2>/dev/null || true
                    else
                        # Add at the top after any existing imports
                        perl -pi -e 's/(^#import.*\n)/$1@import React.Base.RCTConvert;\n/' "$header_file" 2>/dev/null || true
                    fi
                fi
                # Remove duplicate @import React.Base.RCTConvert; statements and fix malformed patterns
                perl -pi -e 's/@import@import/@import/g; s/ React\.Base\.RCTConvert;/@import React.Base.RCTConvert;/g; s/^ React\.Base\.RCTConvert;/@import React.Base.RCTConvert;/g' "$header_file" 2>/dev/null || true
                awk '!seen || !/@import React.Base.RCTConvert;/ { if (/@import React.Base.RCTConvert;/) seen=1; print }' "$header_file" > "${header_file}.tmp" && mv "${header_file}.tmp" "$header_file" 2>/dev/null || true
            fi
        else
            # Recursive function to check if a header (transitively) includes a header with a category
            check_includes_category() {
                local check_file="$1"
                local visited_files="$2"
                
                # Avoid infinite loops
                if echo "$visited_files" | grep -q "$check_file"; then
                    return 1
                fi
                visited_files="$visited_files|$check_file"
                
                # Check if this file itself has a category
                if grep -q "@interface RCTConvert" "$check_file" 2>/dev/null; then
                    return 0
                fi
                
                # Check all included headers recursively
                local included_headers=$(grep -E '^#import\s+"[^"]+\.h"' "$check_file" 2>/dev/null | sed 's/.*"\([^"]*\)".*/\1/' || true)
                for included in $included_headers; do
                    # Find the actual header file
                    local included_path=$(find "${KIT_IOS_PACKAGE_DIR}/Sources" -name "$included" 2>/dev/null | head -1)
                    if [ -f "$included_path" ]; then
                        if check_includes_category "$included_path" "$visited_files"; then
                            return 0
                        fi
                    fi
                done
                
                return 1
            }
            
            # Check if this header (transitively) includes a header with a category
            if check_includes_category "$header_file" ""; then
                # This header includes (transitively) another header with an RCTConvert category
                # Ensure this header also imports React to make RCTConvert visible
                if ! grep -q "#import <React/RCTConvert.h>" "$header_file" 2>/dev/null; then
                    module_name=$(echo "$header_file" | sed "s|${KIT_IOS_PACKAGE_DIR}/Sources/||" | cut -d'/' -f1)
                    file_name=$(basename "$header_file")
                    log "  Adding RCTConvert import to $module_name/$file_name (includes header with category, transitively)..."
                    if grep -q "#import <Foundation/Foundation.h>" "$header_file" 2>/dev/null; then
                        perl -pi -e 's/(#import <Foundation\/Foundation\.h>)/$1\n#import <React\/RCTConvert\.h>/' "$header_file" 2>/dev/null || true
                    elif grep -q "#import <UIKit/UIKit.h>" "$header_file" 2>/dev/null; then
                        perl -pi -e 's/(#import <UIKit\/UIKit\.h>)/$1\n#import <React\/RCTConvert\.h>/' "$header_file" 2>/dev/null || true
                    elif grep -q "#import <AppKit/AppKit.h>" "$header_file" 2>/dev/null; then
                        perl -pi -e 's/(#import <AppKit\/AppKit\.h>)/$1\n#import <React\/RCTConvert\.h>/' "$header_file" 2>/dev/null || true
                    else
                        # Add at the top after any existing imports
                        perl -pi -e 's/(^#import.*\n)/$1#import <React\/RCTConvert\.h>\n/' "$header_file" 2>/dev/null || true
                    fi
                fi
            fi
        fi
    fi
done

# Note: .h files must keep #import <React/RCTConvert.h> for category declarations to work
# Note: .mm files must keep #import <React/RCTConvert.h> for C++ compatibility

# Fix malformed @import statements (where @import got corrupted to just " React;" or "React;")
# This is a generic fix that applies to all iOS source files, not specific to any library
# Handles cases where @import React; was corrupted to standalone " React;" or "React;" 
# either on its own line or on the same line as other content
log "  Fixing malformed @import React statements..."
find "${KIT_IOS_PACKAGE_DIR}/Sources" -type f \( -name "*.m" -o -name "*.mm" -o -name "*.h" \) | while read file; do
    if [ -f "$file" ]; then
        # Check if file contains malformed React imports (standalone " React;" or "React;" in any form)
        # Exclude "@import React;" from the match (we only want to find malformed patterns)
        # Also check for " React;" or "React;" at the start of a line followed by non-whitespace (e.g., " React;@implementation")
        # Pattern matches: " React;" at start of line, " React;" followed by non-whitespace, standalone " React;"
        # Use a simpler pattern that catches all variations
        # Also match standalone lines with just " React;" (with or without trailing whitespace)
        if grep -qE '^[[:space:]]*React;[^[:space:]]|^[[:space:]]+React;[[:space:]]*$|^[[:space:]]*React;[[:space:]]*$| React;[^@[:space:]]' "$file" 2>/dev/null; then
            module_name=$(echo "$file" | sed "s|${KIT_IOS_PACKAGE_DIR}/Sources/||" | cut -d'/' -f1)
            file_name=$(basename "$file")
            log "  Fixing malformed import in $module_name/$file_name..."
            
            # Fix all variations of malformed @import React statements:
            # This is a generic fix that works for any library, not specific to react-native-svg
            # Handles: standalone " React;", " React;@implementation", " React;#import", " React; React;", etc.
            # Use a comprehensive approach that catches all cases in multiple passes
            # Determine file extension to use correct import syntax
            file_ext="${file##*.}"
            if [ "$file_ext" = "m" ]; then
                # Objective-C .m files: use @import React;
                perl -pi -e '
                    # Pass 1: Fix " React;" at start of line followed by non-whitespace (e.g., " React;@implementation")
                    # This must come first to handle cases like " React;@implementation" before they become standalone
                    s/^(\s*)React;([^\s\n])/$1@import React;\n$1$2/g;
                    
                    # Pass 2: Fix standalone lines with just " React;" or "React;" (with optional whitespace)
                    s/^\s*React;\s*$/@import React;/g;
                    
                    # Pass 3: Fix " React;" followed by non-whitespace in the middle of a line (not @)
                    s/ React;([^@\s\n])/\n@import React;\n$1/g;
                ' "$file" 2>/dev/null || true
            else
                # Header .h and C++ .mm files: use #import <React/RCTConvert.h> or @import React.Base.RCTConvert;
                # First check if it's a header with category declaration
                if [ "$file_ext" = "h" ] && grep -qE "@interface\s+RCTConvert\s*\(" "$file" 2>/dev/null; then
                    # Header with category: use @import React.Base.RCTConvert;
                    perl -pi -e '
                        # Pass 1: Fix " React.Base.RCTConvert;" at start of line or with leading whitespace
                        s/^(\s*)React\.Base\.RCTConvert;/$1@import React.Base.RCTConvert;/g;
                        s/ React\.Base\.RCTConvert;/@import React.Base.RCTConvert;/g;
                        
                        # Pass 2: Fix " React;" at start of line followed by non-whitespace
                        s/^(\s*)React;([^\s])/$1@import React.Base.RCTConvert;\n$1$2/g;
                        
                        # Pass 3: Fix standalone lines with whitespace (entire line is " React;" or "  React;")
                        s/^\s+React;\s*$/@import React.Base.RCTConvert;/g;
                    ' "$file" 2>/dev/null || true
                else
                    # Header without category or .mm file: use #import <React/RCTConvert.h>
                    perl -pi -e '
                        # Pass 1: Fix " React.Base.RCTConvert;" -> "#import <React/RCTConvert.h>"
                        s/^(\s*)React\.Base\.RCTConvert;/$1#import <React\/RCTConvert.h>/g;
                        s/ React\.Base\.RCTConvert;/#import <React\/RCTConvert.h>/g;
                        
                        # Pass 2: Fix " React;" at start of line followed by non-whitespace
                        s/^(\s*)React;([^\s])/$1#import <React\/RCTConvert.h>\n$1$2/g;
                        
                        # Pass 3: Fix standalone lines with whitespace (entire line is " React;" or "  React;")
                        s/^\s+React;\s*$/#import <React\/RCTConvert.h>/g;
                        
                        # Pass 4: Fix " React;" followed by non-whitespace in the middle of a line (not @)
                        s/ React;([^@\s])/\n#import <React\/RCTConvert.h>\n$1/g;
                    ' "$file" 2>/dev/null || true
                fi
            fi
            
            # Second pass: Clean up duplicates and fix any remaining issues
            perl -pi -e '
                # Fix duplicate @import statements (@import@import -> @import)
                s/@import@import/@import/g;
                s/@import[[:space:]]*@import[[:space:]]*React;/@import React;/g;
                s/@import[[:space:]]*@import[[:space:]]*React\.Base\.RCTConvert;/@import React.Base.RCTConvert;/g;
                
                # Remove duplicate consecutive @import React; statements (keep only one)
                s/(@import React;[[:space:]]*\n)[[:space:]]*@import React;[[:space:]]*\n/$1/g;
                s/(@import React\.Base\.RCTConvert;[[:space:]]*\n)[[:space:]]*@import React\.Base\.RCTConvert;[[:space:]]*\n/$1/g;
                
                # Final pass: Fix any remaining " React;" patterns that might have been missed
                # This catches edge cases where the pattern appears in unusual contexts
                s/ React;([^[:space:]])/\n@import React;\n$1/g;
                s/^[[:space:]]+React;[[:space:]]*$/@import React;/g;
                s/^React;[[:space:]]*$/@import React;/g;
            ' "$file" 2>/dev/null || true
        fi
    fi
done

log "  ✅ Fixed RCTConvert imports"

# -----------------------------------------------------------------------------
# Apply golden Expo iOS fixes (from IOSExpoCoreBackup)
# -----------------------------------------------------------------------------
# If the repo contains a known-good backup kit, use it as the source of truth for
# the Expo iOS core + file-system modules. This makes the generator 100% repeatable
# without manual edits.
#
# Note: We copy *only the module folders*, so Package.swift remains dynamically generated
# based on whatever modules are detected on a given run.
IOS_EXPO_BACKUP_DIR="${MONOREPO_ROOT}/IOSExpoCoreBackup/VSCONativeKit"
if [ -d "$IOS_EXPO_BACKUP_DIR" ]; then
    log "  Applying iOS golden fixes from IOSExpoCoreBackup..."

    # Helper: rsync if available, otherwise fall back to cp -R
    sync_dir() {
        local src_dir="$1"
        local dst_dir="$2"
        local label="$3"

        if [ ! -d "$src_dir" ]; then
            warn "  ⚠️  Backup missing $label at: $src_dir"
            return 0
        fi
        if [ ! -d "$dst_dir" ]; then
            # Not all modules will exist on every run.
            log "  ℹ️  Skipping $label (not generated in this run)"
            return 0
        fi

        log "  Syncing $label..."
        if command -v rsync >/dev/null 2>&1; then
            rsync -a "$src_dir/" "$dst_dir/" 2>/dev/null || true
        else
            # macOS always has rsync, but keep a safe fallback.
            cp -R "$src_dir/"* "$dst_dir/" 2>/dev/null || true
        fi
        log "  ✅ Synced $label"
    }

    # Non-Expo modules that have shown corruption from import normalization.
    sync_dir "${IOS_EXPO_BACKUP_DIR}/Sources/VSCOSafeAreaContext" \
             "${KIT_IOS_PACKAGE_DIR}/Sources/VSCOSafeAreaContext" \
             "VSCOSafeAreaContext"

    sync_dir "${IOS_EXPO_BACKUP_DIR}/Sources/VSCOCamera" \
             "${KIT_IOS_PACKAGE_DIR}/Sources/VSCOCamera" \
             "VSCOCamera"

    # Expo modules: only sync when expo-* packages were detected/installed in this run.
    if [ "${HAS_EXPO_PACKAGES:-false}" = true ]; then
        sync_dir "${IOS_EXPO_BACKUP_DIR}/Sources/VSCOExpoModulesCore" \
                 "${KIT_IOS_PACKAGE_DIR}/Sources/VSCOExpoModulesCore" \
                 "VSCOExpoModulesCore"

        sync_dir "${IOS_EXPO_BACKUP_DIR}/Sources/VSCOExpoFileSystem" \
                 "${KIT_IOS_PACKAGE_DIR}/Sources/VSCOExpoFileSystem" \
                 "VSCOExpoFileSystem"
    else
        log "  ℹ️  Skipping Expo module sync (no expo-* packages detected)"
    fi

    log "  ✅ Applied iOS golden fixes"
    log "  ℹ️  Package.swift fixes are applied during generation (C++ files, circular dependency fix)"
else
    log "  ℹ️  IOSExpoCoreBackup not found; relying on scripted shims/patches only"
fi

# Create VSCONativeKit.m source file (required for SPM compilation)
log "  Creating VSCONativeKit.m source file..."
mkdir -p "${KIT_IOS_PACKAGE_DIR}/Sources/VSCONativeKit"
cat > "${KIT_IOS_PACKAGE_DIR}/Sources/VSCONativeKit/VSCONativeKit.m" <<'M_EOF'
/**
 * VSCONativeKit - Unified Native Kit
 * 
 * This is a wrapper target that aggregates all bundled native modules.
 * The actual implementations are in the individual module targets.
 */

#import "VSCONativeKit.h"

// This file ensures the target compiles correctly.
// The actual functionality comes from the bundled native module dependencies.
M_EOF

# Ensure VSCONativeKit.h exists
if [ ! -f "${KIT_IOS_PACKAGE_DIR}/Sources/VSCONativeKit/VSCONativeKit.h" ]; then
    cat > "${KIT_IOS_PACKAGE_DIR}/Sources/VSCONativeKit/VSCONativeKit.h" <<'H_EOF'
// VSCONativeKit - Unified Native Kit Header
// This file aggregates all native kit modules
H_EOF
fi

log "  ✅ Created VSCONativeKit source files"

cd "$MONOREPO_ROOT"

########################################
# Summary
########################################
log "🎉 SUCCESS! vsco-native-kit iOS SPM generated"
echo ""
echo "📍 Location: $KIT_IOS_PACKAGE_DIR"
echo ""
echo "📦 iOS SPM:"
echo "   • Location: $KIT_IOS_PACKAGE_DIR"
IOS_MODULES=()
if [ -d "${KIT_IOS_PACKAGE_DIR}/Sources" ]; then
    for module_dir in "${KIT_IOS_PACKAGE_DIR}/Sources"/*; do
        if [ -d "$module_dir" ]; then
            module_name=$(basename "$module_dir")
            if [ "$module_name" != "VSCONativeKit" ]; then
                IOS_MODULES+=("$module_name")
            fi
        fi
    done
fi
echo "   • Modules: ${IOS_MODULES[*]:-none}"
echo ""
echo "📋 Bundled Native Dependencies:"
for dep in "${SHARED_NATIVE_DEPS[@]}"; do
    echo "   • $dep"
done
echo ""
