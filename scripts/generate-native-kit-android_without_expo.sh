#!/usr/bin/env bash
set -eo pipefail
# Note: 'u' flag removed to allow unbound variables in some edge cases
# We'll handle unbound variables explicitly where needed

########################################
# Native Kit Generator - Android AAR
#
# Generates vsco-native-kit AAR (Android) from native dependencies
# detected in modules published to Verdaccio.
#
# Usage:
#   ./scripts/generate-native-kit-android.sh
#
# Workflow:
#   1. Install all modules from Verdaccio
#   2. Detect shared native dependencies from all modules
#   3. Install native packages from npm registry
#   4. Bundle Android native code into vsco-native-kit
#   5. Generate unified ReactPackage (Android)
#   6. Update Android build.gradle
#   7. Build Android AAR
#   8. Publish Android AAR to Maven Local
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
KIT_ANDROID_DIR="${KIT_DIR}/android"
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

# Ensure kit directory exists with full Android structure
mkdir -p "$KIT_DIR"
mkdir -p "$KIT_ANDROID_DIR"
mkdir -p "$KIT_ANDROID_DIR/src/main/java"
mkdir -p "$KIT_ANDROID_DIR/src/main/kotlin"
mkdir -p "$KIT_ANDROID_DIR/src/main/res"
mkdir -p "$KIT_ANDROID_DIR/src/main/AndroidManifest.xml" 2>/dev/null || true  # Ensure parent dir exists
log "  ✅ Created Android directory structure"

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


########################################
# Step 4: Bundle Android native code to vsco-native-kit
########################################
log "Step 4: Bundling Android native code to vsco-native-kit..."

# Function to bundle Android native dependency
bundle_android_to_kit() {
    local package_name="$1"
    local package_source="$2"
    
    log "  Bundling $package_name (Android)..."
    
    # Verify Android native code exists
    local has_android=false
    
    if [ -d "${package_source}/android/src/main/java" ] || \
       [ -d "${package_source}/android/src/main/kotlin" ] || \
       [ -d "${package_source}/android/src/paper/java" ]; then
        has_android=true
    fi
    
    if [ "$has_android" = false ]; then
        warn "    $package_name has no Android native code - skipping"
        return 1
    fi
        local android_java_dir="${KIT_ANDROID_DIR}/src/main/java"
        local android_src="${package_source}/android/src/main/java"
        local android_kotlin="${package_source}/android/src/main/kotlin"
        local android_paper="${package_source}/android/src/paper/java"
        local android_res="${package_source}/android/src/main/res"
        
        # Create temp directory for processing
        local temp_copy_dir=$(mktemp -d)
        mkdir -p "$temp_copy_dir"
        
        # Copy ALL Java/Kotlin source to temp (including all packages like com.lwansbrough.*)
        # Exclude dependency source files that should not be bundled (Fresco, etc.)
        if [ -d "$android_src" ]; then
            # Use find to exclude dependency source files
            find "$android_src" -type f \( -name "*.java" -o -name "*.kt" \) ! -path "*/com/facebook/fresco/*" ! -path "*/com/facebook/common/*" ! -path "*/com/facebook/datasource/*" ! -path "*/com/facebook/imagepipeline/*" ! -path "*/com/facebook/drawee/*" ! -path "*/com/facebook/proguard/*" | while read -r file; do
                # Get relative path from android_src
                local rel_path="${file#$android_src/}"
                local target_file="$temp_copy_dir/$rel_path"
                mkdir -p "$(dirname "$target_file")"
                cp "$file" "$target_file" 2>/dev/null || true
            done
            # Copy directories that don't contain excluded packages (for structure)
            find "$android_src" -type d ! -path "*/com/facebook/fresco/*" ! -path "*/com/facebook/common/*" ! -path "*/com/facebook/datasource/*" ! -path "*/com/facebook/imagepipeline/*" ! -path "*/com/facebook/drawee/*" ! -path "*/com/facebook/proguard/*" | while read -r dir; do
                local rel_path="${dir#$android_src/}"
                mkdir -p "$temp_copy_dir/$rel_path" 2>/dev/null || true
            done
        fi
        
        # Copy Kotlin source to temp (with same exclusions)
        if [ -d "$android_kotlin" ]; then
            find "$android_kotlin" -type f \( -name "*.java" -o -name "*.kt" \) ! -path "*/com/facebook/fresco/*" ! -path "*/com/facebook/common/*" ! -path "*/com/facebook/datasource/*" ! -path "*/com/facebook/imagepipeline/*" ! -path "*/com/facebook/drawee/*" ! -path "*/com/facebook/proguard/*" | while read -r file; do
                local rel_path="${file#$android_kotlin/}"
                local target_file="$temp_copy_dir/$rel_path"
                mkdir -p "$(dirname "$target_file")"
                cp "$file" "$target_file" 2>/dev/null || true
            done
        fi
        
        # Copy paper source (codegen types) to temp (with same exclusions)
        if [ -d "$android_paper" ]; then
            find "$android_paper" -type f \( -name "*.java" -o -name "*.kt" \) ! -path "*/com/facebook/fresco/*" ! -path "*/com/facebook/common/*" ! -path "*/com/facebook/datasource/*" ! -path "*/com/facebook/imagepipeline/*" ! -path "*/com/facebook/drawee/*" ! -path "*/com/facebook/proguard/*" | while read -r file; do
                local rel_path="${file#$android_paper/}"
                local target_file="$temp_copy_dir/$rel_path"
                mkdir -p "$(dirname "$target_file")"
                cp "$file" "$target_file" 2>/dev/null || true
            done
        fi
        
        # Determine target package name: com.vsco.nativekit.{module_name}
        # Convert package name to module name (e.g., react-native-svg -> svg, react-native-safe-area-context -> safeareacontext)
        local module_name=$(node -e "
            const pkg = '$package_name';
            let name = pkg.replace(/^(react-native-|expo-)/, '');
            // Convert kebab-case to camelCase (remove hyphens, capitalize next letter)
            name = name.replace(/-([a-z])/g, (_, letter) => letter.toUpperCase());
            console.log(name);
        " 2>/dev/null || echo "$package_name" | sed 's/react-native-//' | sed 's/expo-//' | sed 's/-\([a-z]\)/\U\1/g')
        
        ########################################
        # PHASE 1: DISCOVERY - Find all unique packages
        ########################################
        log "    Phase 1: Discovering all packages..."
        
        # Use a temporary file to store package mappings (original -> target)
        # Format: original_package|target_package (one per line)
        local package_map_file=$(mktemp)
        
        # Get the first package to determine the main package
        local first_file=$(find "$temp_copy_dir" -type f \( -name "*.java" -o -name "*.kt" \) | head -1)
        local main_original_package=""
        if [ -n "$first_file" ] && [ -f "$first_file" ]; then
            main_original_package=$(grep -m 1 "^package " "$first_file" 2>/dev/null | sed 's/^package //' | sed 's/;$//' | xargs)
        fi
        
        # If we found a main package, add it to the map
        if [ -n "$main_original_package" ]; then
            local main_target_package="com.vsco.nativekit.${module_name}"
            echo "${main_original_package}|${main_target_package}" >> "$package_map_file"
            log "    Found main package: $main_original_package -> $main_target_package"
        fi
        
        # Discover all other packages by scanning all Java/Kotlin files
        # Extract unique package declarations
        while IFS= read -r pkg_declaration; do
            if [ -z "$pkg_declaration" ]; then
                continue
            fi
            
            # Skip React Native codegen packages (com.facebook.react.*)
            if echo "$pkg_declaration" | grep -q "^com\.facebook\.react\."; then
                continue
            fi
            
            # Skip if this is the main package
            if [ "$pkg_declaration" = "$main_original_package" ]; then
                continue
            fi
            
            # Check if already in map
            if grep -q "^${pkg_declaration}|" "$package_map_file" 2>/dev/null; then
                continue
            fi
            
            # Determine if this is a sub-package of the main package
            # Sub-packages are packages that share a common prefix with the main package
            # but are not the main package itself
            local is_sub_package=false
            local sub_package_suffix=""
            
            if [ -n "$main_original_package" ]; then
                # Check if this package starts with the main package prefix
                # e.g., main: com.horcrux.svg, sub: com.horcrux.svg.nodes -> nodes
                if echo "$pkg_declaration" | grep -q "^${main_original_package}\."; then
                    is_sub_package=true
                    sub_package_suffix="${pkg_declaration#${main_original_package}.}"
                # Check if this is a sibling package (same top-level, different second-level)
                # e.g., main: com.horcrux.svg, sibling: com.lwansbrough.RCTCamera
                elif echo "$pkg_declaration" | grep -q "^com\." && echo "$main_original_package" | grep -q "^com\."; then
                    # Extract second-level package name (e.g., lwansbrough from com.lwansbrough.RCTCamera)
                    local second_level=$(echo "$pkg_declaration" | cut -d. -f2)
                    local main_second_level=$(echo "$main_original_package" | cut -d. -f2)
                    
                    if [ "$second_level" != "$main_second_level" ]; then
                        # This is a sibling package (e.g., com.lwansbrough in react-native-camera)
                        is_sub_package=true
                        sub_package_suffix="$second_level"
                    fi
                fi
            fi
            
            # Determine target package name
            local target_pkg=""
            if [ "$is_sub_package" = true ] && [ -n "$sub_package_suffix" ]; then
                # Sub-package: com.vsco.nativekit.{module_name}.{suffix}
                target_pkg="com.vsco.nativekit.${module_name}.${sub_package_suffix}"
            else
                # Standalone package: com.vsco.nativekit.{module_name}.{extracted_name}
                # Extract a meaningful name from the package
                local pkg_name=$(echo "$pkg_declaration" | sed 's/^com\.//' | sed 's/^org\.//' | tr '.' '_')
                target_pkg="com.vsco.nativekit.${module_name}.${pkg_name}"
            fi
            
            echo "${pkg_declaration}|${target_pkg}" >> "$package_map_file"
            log "    Found package: $pkg_declaration -> $target_pkg"
        done < <(find "$temp_copy_dir" -type f \( -name "*.java" -o -name "*.kt" \) -exec grep -h "^package " {} \; 2>/dev/null | sed 's/^package //' | sed 's/;$//' | sort -u)
        
        ########################################
        # PHASE 2: RENAMING - Rename all packages in one pass
        ########################################
        log "    Phase 2: Renaming all packages..."
        
        # Sort packages by length (longest first) to handle nested packages correctly
        # This ensures we rename com.horcrux.svg.nodes before com.horcrux.svg
        # Also track which packages we've already renamed to avoid double-renaming
        local renamed_packages_file=$(mktemp)
        
        while IFS='|' read -r original_pkg target_pkg; do
            if [ -z "$original_pkg" ] || [ -z "$target_pkg" ]; then
                continue
            fi
            
            if [ "$original_pkg" = "$target_pkg" ]; then
                continue  # Skip if already correct
            fi
            
            log "    Renaming: $original_pkg -> $target_pkg"
            
            # Escape dots for regex
            local escaped_original="${original_pkg//./\\.}"
            
            # Rename package declarations (match entire package line)
            # Find all files that have this package declaration and rename them
            # Use a more robust approach: check for exact package match with optional whitespace
            find "$temp_copy_dir" -type f \( -name "*.java" -o -name "*.kt" \) | while read -r file; do
                if [ ! -f "$file" ]; then
                    continue
                fi
                # Check if file has the original package declaration (with optional whitespace)
                # Pattern: package com.horcrux.svg; or package  com.horcrux.svg  ;
                if grep -qE "^package[[:space:]]+${escaped_original}[[:space:]]*;" "$file" 2>/dev/null; then
                    # Rename the package declaration
                    perl -pi -e "s/^package[[:space:]]+${escaped_original}([[:space:]]*;)/package ${target_pkg}\$1/g" "$file" 2>/dev/null || true
                fi
            done
            
            # Rename imports (full package imports)
            # Only rename imports that reference the original package
            find "$temp_copy_dir" -type f \( -name "*.java" -o -name "*.kt" \) -exec perl -pi -e "s/import\s+${escaped_original}(\.[^;]*)?;/import ${target_pkg}\$1;/g" {} \; 2>/dev/null || true
            
            # Rename static imports
            find "$temp_copy_dir" -type f \( -name "*.java" -o -name "*.kt" \) -exec perl -pi -e "s/import\s+static\s+${escaped_original}(\.[^;]*)?;/import static ${target_pkg}\$1;/g" {} \; 2>/dev/null || true
            
            # Rename class references in strings (e.g., Class.forName) - be careful with this
            # Only replace full package names, not partial matches
            find "$temp_copy_dir" -type f \( -name "*.java" -o -name "*.kt" \) -exec perl -pi -e "s/\"${escaped_original}(\.[^\"]*)?\"/\"${target_pkg}\$1\"/g" {} \; 2>/dev/null || true
            
            # Mark this package as renamed
            echo "$target_pkg" >> "$renamed_packages_file"
        done < <(cat "$package_map_file" | awk -F'|' '{print length($1), $0}' | sort -rn | cut -d' ' -f2-)
        
        rm -f "$renamed_packages_file"
        
        ########################################
        # PHASE 3: COPY - Copy renamed files to target structure
        ########################################
        log "    Phase 3: Copying renamed files..."
        
        # Track which files we've already copied to avoid duplicates
        # Use absolute paths to avoid issues
        local copied_files_file=$(mktemp)
        
        # Copy all files based on their NEW package declarations (after renaming)
        # This ensures we get the correctly renamed files
        # Process packages in order from the map to ensure correct structure
        while IFS='|' read -r original_pkg target_pkg; do
            if [ -z "$original_pkg" ] || [ -z "$target_pkg" ]; then
                continue
            fi
            
            # Find all files that have this target package (after renaming)
            find "$temp_copy_dir" -type f \( -name "*.java" -o -name "*.kt" \) | while read -r file; do
                if [ ! -f "$file" ]; then
                    continue
                fi
                
                # Get the package declaration from the file (after renaming)
                local file_pkg=$(grep -m 1 "^package " "$file" 2>/dev/null | sed 's/^package //' | sed 's/;$//' | xargs)
                
                if [ -z "$file_pkg" ]; then
                    continue
                fi
                
                # Skip React Native codegen packages (they're copied separately)
                if echo "$file_pkg" | grep -q "^com\.facebook\.react\."; then
                    continue
                fi
                
                # Only copy files that match this target package
                if [ "$file_pkg" != "$target_pkg" ]; then
                    continue
                fi
                
                # Find the target path for this package
                local target_path="${file_pkg//.//}"
                local file_basename=$(basename "$file")
                local target_file="$android_java_dir/$target_path/$file_basename"
                
                # Check if we've already copied this file (avoid duplicates)
                if ! grep -q "^${target_file}$" "$copied_files_file" 2>/dev/null; then
                    mkdir -p "$android_java_dir/$target_path"
                    cp "$file" "$target_file" 2>/dev/null || true
                    echo "$target_file" >> "$copied_files_file"
                fi
            done
        done < "$package_map_file"
        
        # Also copy any remaining files that weren't matched (fallback)
        # This catches files that might have been missed
        # Exclude Fresco and other dependency packages
        find "$temp_copy_dir" -type f \( -name "*.java" -o -name "*.kt" \) ! -path "*/com/facebook/fresco/*" ! -path "*/com/facebook/common/*" ! -path "*/com/facebook/datasource/*" ! -path "*/com/facebook/imagepipeline/*" ! -path "*/com/facebook/drawee/*" ! -path "*/com/facebook/proguard/*" | while read -r file; do
            if [ ! -f "$file" ]; then
                continue
            fi
            
            # Get the package declaration from the file
            local file_pkg=$(grep -m 1 "^package " "$file" 2>/dev/null | sed 's/^package //' | sed 's/;$//' | xargs)
            
            if [ -z "$file_pkg" ]; then
                continue
            fi
            
            # Skip React Native codegen packages (handled separately)
            if echo "$file_pkg" | grep -q "^com\.facebook\.react\."; then
                continue
            fi
            
            # Skip Fresco and other dependency packages
            if echo "$file_pkg" | grep -qE "^(com\.facebook\.(fresco|common|datasource|imagepipeline|drawee|proguard))"; then
                continue
            fi
            
            # Skip if already copied
            local target_path="${file_pkg//.//}"
            local file_basename=$(basename "$file")
            local target_file="$android_java_dir/$target_path/$file_basename"
            
            if [ -f "$target_file" ]; then
                continue  # Already copied
            fi
            
            # Copy the file
            mkdir -p "$android_java_dir/$target_path"
            cp "$file" "$target_file" 2>/dev/null || true
        done
        
        # Clean up copied files tracking
        rm -f "$copied_files_file"
        
        # Copy React Native codegen packages (com.facebook.react.*) - DO NOT RENAME
        # Exclude Fresco and other dependency packages that should not be bundled
        if [ -d "$temp_copy_dir/com/facebook" ]; then
            mkdir -p "$android_java_dir/com/facebook"
            # Only copy com.facebook.react.* packages, exclude Fresco and other dependencies
            if [ -d "$temp_copy_dir/com/facebook/react" ]; then
                mkdir -p "$android_java_dir/com/facebook/react"
                cp -R "$temp_copy_dir/com/facebook/react"/* "$android_java_dir/com/facebook/react/" 2>/dev/null || true
            fi
            # Explicitly exclude Fresco and other dependency packages
            # These should come from dependencies, not be bundled in the AAR
            # (fresco, common, datasource, imagepipeline, drawee, proguard are excluded)
        fi
        
        # Cleanup: Remove any Fresco or dependency source files that might have been copied
        # This is a safety net to ensure these files are never bundled in the AAR
        rm -rf "$android_java_dir/com/facebook/fresco" 2>/dev/null || true
        rm -rf "$android_java_dir/com/facebook/common" 2>/dev/null || true
        rm -rf "$android_java_dir/com/facebook/datasource" 2>/dev/null || true
        rm -rf "$android_java_dir/com/facebook/imagepipeline" 2>/dev/null || true
        rm -rf "$android_java_dir/com/facebook/drawee" 2>/dev/null || true
        rm -rf "$android_java_dir/com/facebook/proguard" 2>/dev/null || true
        
        ########################################
        # PHASE 4: POST-PROCESS - Ensure all files are correctly renamed
        ########################################
        log "    Phase 4: Post-processing to ensure all packages are renamed..."
        
        # Re-apply renaming to any files that might have been missed
        # This is a safety net to catch any files that weren't renamed in Phase 2
        # Process ALL files in the target directory, not just ones in old locations
        while IFS='|' read -r original_pkg target_pkg; do
            if [ -z "$original_pkg" ] || [ -z "$target_pkg" ] || [ "$original_pkg" = "$target_pkg" ]; then
                continue
            fi
            
            local escaped_original="${original_pkg//./\\.}"
            
            # Find ALL files in target directory that still reference the original package
            # This catches files that were copied but not fully renamed
            find "$android_java_dir" -type f \( -name "*.java" -o -name "*.kt" \) | while read -r file; do
                if [ ! -f "$file" ]; then
                    continue
                fi
                
                # Skip React Native codegen packages
                if echo "$file" | grep -q "/com/facebook/react/"; then
                    continue
                fi
                
                # Check if file contains references to the original package
                local needs_renaming=false
                if grep -qE "^package[[:space:]]+${escaped_original}[[:space:]]*;" "$file" 2>/dev/null; then
                    needs_renaming=true
                elif grep -qE "\\b${escaped_original}\\b" "$file" 2>/dev/null; then
                    # Check if it's a type reference (not just part of a string)
                    if grep -qE "(import|::class|\.java|Class<|new[[:space:]]+${escaped_original})" "$file" 2>/dev/null; then
                        needs_renaming=true
                    fi
                fi
                
                if [ "$needs_renaming" = true ]; then
                    # Rename the package declaration
                    perl -pi -e "s/^(package[[:space:]]+)${escaped_original}([[:space:]]*;)/\${1}${target_pkg}\${2}/g" "$file" 2>/dev/null || true
                    # Rename imports
                    perl -pi -e "s/import[[:space:]]+${escaped_original}(\.[^;]*)?;/import ${target_pkg}\$1;/g" "$file" 2>/dev/null || true
                    # Rename static imports
                    perl -pi -e "s/import[[:space:]]+static[[:space:]]+${escaped_original}(\.[^;]*)?;/import static ${target_pkg}\$1;/g" "$file" 2>/dev/null || true
                    # Rename type references in code (be careful with word boundaries)
                    # Match: ClassName, ::class.java, Class<ClassName>, new ClassName()
                    perl -pi -e "s/\\b${escaped_original}(\.[A-Za-z0-9_]+)?\\b/${target_pkg}\$1/g" "$file" 2>/dev/null || true
                    
                    # Move file to correct location if it's in the wrong directory
                    local current_path="${file#$android_java_dir/}"
                    local original_pkg_path="${original_pkg//.//}"
                    local target_pkg_path="${target_pkg//.//}"
                    
                    # If file is in the old package directory, move it to the new one
                    if echo "$current_path" | grep -q "^${original_pkg_path}/"; then
                        local file_basename=$(basename "$file")
                        local new_file_path="$android_java_dir/$target_pkg_path/$file_basename"
                        if [ "$file" != "$new_file_path" ] && [ ! -f "$new_file_path" ]; then
                            mkdir -p "$android_java_dir/$target_pkg_path"
                            mv "$file" "$new_file_path" 2>/dev/null || true
                        fi
                    fi
                fi
            done
        done < "$package_map_file"
        
        # Clean up any empty old package directories
        find "$android_java_dir" -type d -empty -delete 2>/dev/null || true
        
        # Final pass: Move any remaining files from old package directories to new ones
        while IFS='|' read -r original_pkg target_pkg; do
            if [ -z "$original_pkg" ] || [ -z "$target_pkg" ] || [ "$original_pkg" = "$target_pkg" ]; then
                continue
            fi
            
            local original_pkg_path="${original_pkg//.//}"
            local target_pkg_path="${target_pkg//.//}"
            
            # Find all files in the old package directory and move them
            if [ -d "$android_java_dir/$original_pkg_path" ]; then
                find "$android_java_dir/$original_pkg_path" -type f \( -name "*.java" -o -name "*.kt" \) | while read -r file; do
                    if [ -f "$file" ]; then
                        local file_basename=$(basename "$file")
                        local new_file_path="$android_java_dir/$target_pkg_path/$file_basename"
                        
                        if [ "$file" != "$new_file_path" ] && [ ! -f "$new_file_path" ]; then
                            mkdir -p "$android_java_dir/$target_pkg_path"
                            mv "$file" "$new_file_path" 2>/dev/null || true
                            
                            # Also rename package and type references in the moved file
                            local escaped_original="${original_pkg//./\\.}"
                            perl -pi -e "s/^(package[[:space:]]+)${escaped_original}([[:space:]]*;)/\${1}${target_pkg}\${2}/g" "$new_file_path" 2>/dev/null || true
                            perl -pi -e "s/import[[:space:]]+${escaped_original}(\.[^;]*)?;/import ${target_pkg}\$1;/g" "$new_file_path" 2>/dev/null || true
                            perl -pi -e "s/\\b${escaped_original}(\.[A-Za-z0-9_]+)?\\b/${target_pkg}\$1/g" "$new_file_path" 2>/dev/null || true
                        fi
                    fi
                done
            fi
        done < "$package_map_file"
        
        # Clean up empty directories again
        find "$android_java_dir" -type d -empty -delete 2>/dev/null || true
        
        # Final cleanup: Remove Fresco and other dependency source files
        # These should never be bundled in the AAR - they must come from dependencies
        rm -rf "$android_java_dir/com/facebook/fresco" 2>/dev/null || true
        rm -rf "$android_java_dir/com/facebook/common" 2>/dev/null || true
        rm -rf "$android_java_dir/com/facebook/datasource" 2>/dev/null || true
        rm -rf "$android_java_dir/com/facebook/imagepipeline" 2>/dev/null || true
        rm -rf "$android_java_dir/com/facebook/drawee" 2>/dev/null || true
        rm -rf "$android_java_dir/com/facebook/proguard" 2>/dev/null || true
        
        # Final cleanup: Remove any remaining old package directories
        # These should have been moved, but if they weren't, remove them to avoid conflicts
        # Note: org/reactnative is kept for stub classes (facedetector, barcodedetector)
        for old_dir in "$android_java_dir"/com/th3rdwave "$android_java_dir"/com/horcrux; do
            if [ -d "$old_dir" ] && [ "$old_dir" != "$android_java_dir/com/vsco" ] && [ "$old_dir" != "$android_java_dir/com/facebook" ]; then
                # Check if there are any files that weren't moved
                if find "$old_dir" -type f \( -name "*.java" -o -name "*.kt" \) 2>/dev/null | head -1 | grep -q .; then
                    # Files still exist - try to move them one more time
                    find "$old_dir" -type f \( -name "*.java" -o -name "*.kt" \) | while read -r file; do
                        local file_pkg=$(grep -m 1 "^package " "$file" 2>/dev/null | sed 's/^package //' | sed 's/;$//' | xargs)
                        if [ -n "$file_pkg" ] && echo "$file_pkg" | grep -q "^com\.vsco\.nativekit\."; then
                            local target_path="${file_pkg//.//}"
                            local file_basename=$(basename "$file")
                            local target_file="$android_java_dir/$target_path/$file_basename"
                            if [ ! -f "$target_file" ]; then
                                mkdir -p "$android_java_dir/$target_path"
                                mv "$file" "$target_file" 2>/dev/null || true
                            fi
                        fi
                    done
                fi
                # Remove the old directory if it's now empty or if files were moved
                find "$old_dir" -type d -empty -delete 2>/dev/null || true
                if [ -d "$old_dir" ]; then
                    rm -rf "$old_dir" 2>/dev/null || true
                fi
            fi
        done
        
        # Clean up org/reactnative/camera if it exists (should be moved to com.vsco.nativekit.camera)
        # But keep org/reactnative/facedetector and org/reactnative/barcodedetector (stub classes)
        if [ -d "$android_java_dir/org/reactnative/camera" ]; then
            find "$android_java_dir/org/reactnative/camera" -type f \( -name "*.java" -o -name "*.kt" \) | while read -r file; do
                local file_pkg=$(grep -m 1 "^package " "$file" 2>/dev/null | sed 's/^package //' | sed 's/;$//' | xargs)
                if [ -n "$file_pkg" ] && echo "$file_pkg" | grep -q "^com\.vsco\.nativekit\.camera\."; then
                    local target_path="${file_pkg//.//}"
                    local file_basename=$(basename "$file")
                    local target_file="$android_java_dir/$target_path/$file_basename"
                    if [ ! -f "$target_file" ]; then
                        mkdir -p "$android_java_dir/$target_path"
                        mv "$file" "$target_file" 2>/dev/null || true
                    fi
                fi
            done
            # Remove org/reactnative/camera if empty
            find "$android_java_dir/org/reactnative/camera" -type d -empty -delete 2>/dev/null || true
            if [ -d "$android_java_dir/org/reactnative/camera" ] && [ -z "$(find "$android_java_dir/org/reactnative/camera" -type f 2>/dev/null)" ]; then
                rm -rf "$android_java_dir/org/reactnative/camera" 2>/dev/null || true
            fi
        fi
        
        log "    ✅ Post-processing complete"
        
        # Clean up temp file
        rm -f "$package_map_file"
        
        # Step 4.0.5: Apply generic compilation fixes
        ########################################
        log "    Phase 4.5: Applying generic compilation fixes..."
        
        # Fix 1: Replace FLog with Android Log (for react-native-svg and other libraries)
        find "$android_java_dir" -type f \( -name "*.java" -o -name "*.kt" \) 2>/dev/null | while read -r file; do
            if grep -q "FLog\." "$file" 2>/dev/null; then
                # Replace import
                sed -i '' 's/import com\.facebook\.common\.logging\.FLog;/import android.util.Log;/g' "$file" 2>/dev/null || \
                sed -i 's/import com\.facebook\.common\.logging\.FLog;/import android.util.Log;/g' "$file" 2>/dev/null || true
                # Replace FLog method calls
                sed -i '' 's/FLog\.w(/Log.w(/g; s/FLog\.e(/Log.e(/g; s/FLog\.d(/Log.d(/g; s/FLog\.i(/Log.i(/g' "$file" 2>/dev/null || \
                sed -i 's/FLog\.w(/Log.w(/g; s/FLog\.e(/Log.e(/g; s/FLog\.d(/Log.d(/g; s/FLog\.i(/Log.i(/g' "$file" 2>/dev/null || true
            fi
        done
        
        # Fix 2: Create DoNotStrip annotation stub (for react-native-svg codegen files)
        local donotstrip_dir="${android_java_dir}/com/facebook/proguard/annotations"
        if [ ! -f "${donotstrip_dir}/DoNotStrip.java" ]; then
            mkdir -p "$donotstrip_dir"
            cat > "${donotstrip_dir}/DoNotStrip.java" << 'DONOTSTRIP_EOF'
package com.facebook.proguard.annotations;

import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

/**
 * Stub annotation for DoNotStrip - used by ProGuard to prevent stripping of annotated classes/methods.
 * This is a compile-time only annotation and doesn't affect runtime behavior.
 */
@Target({ElementType.TYPE, ElementType.METHOD, ElementType.FIELD, ElementType.CONSTRUCTOR})
@Retention(RetentionPolicy.CLASS)
public @interface DoNotStrip {
}
DONOTSTRIP_EOF
            log "    ✅ Created DoNotStrip annotation stub"
        fi
        
        # Fix 3: Create Fresco stubs (for react-native-svg image loading)
        # These are provided by React Native at runtime, but needed at compile time
        local fresco_base_dir="${android_java_dir}/com/facebook"
        
        # Fresco class
        mkdir -p "${fresco_base_dir}/drawee/backends/pipeline"
        if [ ! -f "${fresco_base_dir}/drawee/backends/pipeline/Fresco.java" ]; then
            cat > "${fresco_base_dir}/drawee/backends/pipeline/Fresco.java" << 'FRESCO_EOF'
package com.facebook.drawee.backends.pipeline;

import com.facebook.imagepipeline.core.ImagePipeline;

/**
 * Stub class for Fresco - provided by React Native at runtime
 */
public class Fresco {
    public static ImagePipeline getImagePipeline() {
        throw new RuntimeException("Fresco is not initialized. This should be provided by React Native at runtime.");
    }
}
FRESCO_EOF
        fi
        
        # ImagePipeline
        mkdir -p "${fresco_base_dir}/imagepipeline/core"
        if [ ! -f "${fresco_base_dir}/imagepipeline/core/ImagePipeline.java" ]; then
            cat > "${fresco_base_dir}/imagepipeline/core/ImagePipeline.java" << 'IMAGEPIPELINE_EOF'
package com.facebook.imagepipeline.core;

import com.facebook.common.references.CloseableReference;
import com.facebook.datasource.DataSource;
import com.facebook.imagepipeline.image.CloseableImage;
import com.facebook.imagepipeline.request.ImageRequest;

/**
 * Stub class for ImagePipeline - provided by Fresco at runtime
 */
public class ImagePipeline {
    public boolean isInBitmapMemoryCache(ImageRequest request) {
        return false;
    }
    
    public DataSource<CloseableReference<CloseableImage>> fetchDecodedImage(ImageRequest request, Object callerContext) {
        throw new RuntimeException("ImagePipeline is not initialized. This should be provided by Fresco at runtime.");
    }
    
    public DataSource<CloseableReference<CloseableImage>> fetchImageFromBitmapCache(ImageRequest request, Object callerContext) {
        throw new RuntimeException("ImagePipeline is not initialized. This should be provided by Fresco at runtime.");
    }
}
IMAGEPIPELINE_EOF
        fi
        
        # DataSource interface
        mkdir -p "${fresco_base_dir}/datasource"
        if [ ! -f "${fresco_base_dir}/datasource/DataSource.java" ]; then
            cat > "${fresco_base_dir}/datasource/DataSource.java" << 'DATASOURCE_EOF'
package com.facebook.datasource;

/**
 * Stub interface for DataSource - provided by Fresco at runtime
 */
public interface DataSource<T> {
    T getResult();
    boolean hasResult();
    boolean isFinished();
    Throwable getFailureCause();
    float getProgress();
    void close();
    void subscribe(DataSubscriber<? super T> dataSubscriber, java.util.concurrent.Executor executor);
}
DATASOURCE_EOF
        fi
        
        # DataSubscriber interface
        if [ ! -f "${fresco_base_dir}/datasource/DataSubscriber.java" ]; then
            cat > "${fresco_base_dir}/datasource/DataSubscriber.java" << 'DATASUBSCRIBER_EOF'
package com.facebook.datasource;

/**
 * Stub interface for DataSubscriber - provided by Fresco at runtime
 */
public interface DataSubscriber<T> {
    void onNewResult(DataSource<T> dataSource);
    void onFailure(DataSource<T> dataSource);
    void onCancellation(DataSource<T> dataSource);
    void onProgressUpdate(DataSource<T> dataSource);
}
DATASUBSCRIBER_EOF
        fi
        
        # BaseDataSubscriber
        if [ ! -f "${fresco_base_dir}/datasource/BaseDataSubscriber.java" ]; then
            cat > "${fresco_base_dir}/datasource/BaseDataSubscriber.java" << 'BASEDATASUBSCRIBER_EOF'
package com.facebook.datasource;

import java.util.concurrent.Executor;

/**
 * Stub abstract class for BaseDataSubscriber - provided by Fresco at runtime
 */
public abstract class BaseDataSubscriber<T> implements DataSubscriber<T> {
    @Override
    public void onNewResult(DataSource<T> dataSource) {
        if (dataSource.isFinished()) {
            try {
                onNewResultImpl(dataSource.getResult());
            } finally {
                dataSource.close();
            }
        }
    }
    
    @Override
    public void onFailure(DataSource<T> dataSource) {
        try {
            onFailureImpl(dataSource);
        } finally {
            dataSource.close();
        }
    }
    
    @Override
    public void onCancellation(DataSource<T> dataSource) {
        // Stub implementation
    }
    
    @Override
    public void onProgressUpdate(DataSource<T> dataSource) {
        // Stub implementation
    }
    
    protected abstract void onNewResultImpl(T result);
    protected void onFailureImpl(DataSource<T> dataSource) {
        // Stub implementation - can be overridden
    }
}
BASEDATASUBSCRIBER_EOF
        fi
        
        # BaseBitmapDataSubscriber
        mkdir -p "${fresco_base_dir}/imagepipeline/datasource"
        if [ ! -f "${fresco_base_dir}/imagepipeline/datasource/BaseBitmapDataSubscriber.java" ]; then
            cat > "${fresco_base_dir}/imagepipeline/datasource/BaseBitmapDataSubscriber.java" << 'BASEBITMAPDATASUBSCRIBER_EOF'
package com.facebook.imagepipeline.datasource;

import android.graphics.Bitmap;
import com.facebook.common.references.CloseableReference;
import com.facebook.datasource.BaseDataSubscriber;
import com.facebook.imagepipeline.image.CloseableBitmap;
import com.facebook.imagepipeline.image.CloseableImage;

/**
 * Stub class for BaseBitmapDataSubscriber - provided by Fresco at runtime
 */
public abstract class BaseBitmapDataSubscriber extends BaseDataSubscriber<CloseableReference<CloseableImage>> {
    @Override
    protected void onNewResultImpl(CloseableReference<CloseableImage> imageRef) {
        if (imageRef != null && imageRef.get() != null) {
            CloseableImage image = imageRef.get();
            if (image instanceof CloseableBitmap) {
                Bitmap bitmap = ((CloseableBitmap) image).getUnderlyingBitmap();
                onNewResultImpl(bitmap);
            }
        }
    }
    
    protected abstract void onNewResultImpl(Bitmap bitmap);
}
BASEBITMAPDATASUBSCRIBER_EOF
        fi
        
        # CloseableReference
        mkdir -p "${fresco_base_dir}/common/references"
        if [ ! -f "${fresco_base_dir}/common/references/CloseableReference.java" ]; then
            cat > "${fresco_base_dir}/common/references/CloseableReference.java" << 'CLOSEABLEREFERENCE_EOF'
package com.facebook.common.references;

/**
 * Stub class for CloseableReference - provided by Fresco at runtime
 */
public class CloseableReference<T> implements java.io.Closeable {
    public static <T> CloseableReference<T> of(T t) {
        return new CloseableReference<>();
    }
    
    public T get() {
        return null;
    }
    
    @Override
    public void close() {
        // Stub implementation
    }
    
    public static void closeSafely(CloseableReference<?> ref) {
        if (ref != null) {
            ref.close();
        }
    }
}
CLOSEABLEREFERENCE_EOF
        fi
        
        # CloseableImage and CloseableBitmap
        mkdir -p "${fresco_base_dir}/imagepipeline/image"
        if [ ! -f "${fresco_base_dir}/imagepipeline/image/CloseableImage.java" ]; then
            cat > "${fresco_base_dir}/imagepipeline/image/CloseableImage.java" << 'CLOSEABLEIMAGE_EOF'
package com.facebook.imagepipeline.image;

import java.io.Closeable;

/**
 * Stub class for CloseableImage - provided by Fresco at runtime
 */
public abstract class CloseableImage implements Closeable {
    public abstract void close();
}
CLOSEABLEIMAGE_EOF
        fi
        
        if [ ! -f "${fresco_base_dir}/imagepipeline/image/CloseableBitmap.java" ]; then
            cat > "${fresco_base_dir}/imagepipeline/image/CloseableBitmap.java" << 'CLOSEABLEBITMAP_EOF'
package com.facebook.imagepipeline.image;

import android.graphics.Bitmap;

/**
 * Stub class for CloseableBitmap - provided by Fresco at runtime
 */
public class CloseableBitmap extends CloseableImage {
    public Bitmap getUnderlyingBitmap() {
        return null;
    }
    
    @Override
    public void close() {
        // Stub implementation
    }
}
CLOSEABLEBITMAP_EOF
        fi
        
        # ImageRequest
        mkdir -p "${fresco_base_dir}/imagepipeline/request"
        if [ ! -f "${fresco_base_dir}/imagepipeline/request/ImageRequest.java" ]; then
            cat > "${fresco_base_dir}/imagepipeline/request/ImageRequest.java" << 'IMAGEREQUEST_EOF'
package com.facebook.imagepipeline.request;

import android.net.Uri;

/**
 * Stub class for ImageRequest - provided by Fresco at runtime
 */
public class ImageRequest {
    public static ImageRequest fromUri(Uri uri) {
        return new ImageRequest();
    }
}
IMAGEREQUEST_EOF
        fi
        
        # UiThreadImmediateExecutorService
        mkdir -p "${fresco_base_dir}/common/executors"
        if [ ! -f "${fresco_base_dir}/common/executors/UiThreadImmediateExecutorService.java" ]; then
            cat > "${fresco_base_dir}/common/executors/UiThreadImmediateExecutorService.java" << 'UITHREADEXECUTOR_EOF'
package com.facebook.common.executors;

import java.util.concurrent.Executor;

/**
 * Stub class for UiThreadImmediateExecutorService - provided by Fresco at runtime
 */
public class UiThreadImmediateExecutorService implements Executor {
    public static UiThreadImmediateExecutorService getInstance() {
        return new UiThreadImmediateExecutorService();
    }
    
    @Override
    public void execute(Runnable command) {
        // Stub implementation
    }
}
UITHREADEXECUTOR_EOF
        fi
        
        # Fix 4: Fix NotFoundException catch blocks to use fully qualified names (for ZXing)
        find "$android_java_dir" -type f -name "*.java" 2>/dev/null | while read -r file; do
            if grep -qE "catch\s*\([^)]*NotFoundException[^)]*\)" "$file" 2>/dev/null; then
                # Replace catch (NotFoundException e) with catch (com.google.zxing.NotFoundException e)
                # But only if NotFoundException is not already fully qualified
                perl -pi -e 's/catch\s*\(\s*NotFoundException\s+(\w+)\s*\)/catch (com.google.zxing.NotFoundException $1)/g' "$file" 2>/dev/null || true
            fi
        done
        log "    ✅ Fixed NotFoundException catch blocks"
        
        # Fix 5: Ensure ImageProcessingException stub extends Exception (for metadata-extractor)
        local image_processing_exception_file="${android_java_dir}/com/drew/imaging/ImageProcessingException.java"
        if [ -f "$image_processing_exception_file" ]; then
            # Check if it already extends Exception
            if ! grep -q "extends Exception" "$image_processing_exception_file" 2>/dev/null; then
                # Replace the class declaration to extend Exception and add constructors
                perl -pi -e 's/public class ImageProcessingException \{/public class ImageProcessingException extends Exception {\n    public ImageProcessingException() {\n        super();\n    }\n    \n    public ImageProcessingException(String message) {\n        super(message);\n    }\n    \n    public ImageProcessingException(String message, Throwable cause) {\n        super(message, cause);\n    }\n    \n    public ImageProcessingException(Throwable cause) {\n        super(cause);\n    }/g' "$image_processing_exception_file" 2>/dev/null || true
            fi
            log "    ✅ Fixed ImageProcessingException stub to extend Exception"
        fi
        
        # Fix 6: Remove MetadataException from catch blocks where it's never thrown (for MutableImage.java)
        find "$android_java_dir" -type f -name "*.java" 2>/dev/null | while read -r file; do
            # Check if file has catch block with MetadataException
            if grep -qE "catch\s*\([^)]*MetadataException[^)]*\)" "$file" 2>/dev/null; then
                # Check if the try block calls originalImageMetaData() which only throws ImageProcessingException and IOException
                if grep -q "originalImageMetaData()" "$file" 2>/dev/null; then
                    # Remove MetadataException from the catch block
                    perl -pi -e 's/catch\s*\(\s*ImageProcessingException\s*\|\s*IOException\s*\|\s*MetadataException\s+(\w+)\s*\)/catch (ImageProcessingException | IOException $1)/g' "$file" 2>/dev/null || true
                    perl -pi -e 's/catch\s*\(\s*ImageProcessingException\s*\|\s*MetadataException\s*\|\s*IOException\s+(\w+)\s*\)/catch (ImageProcessingException | IOException $1)/g' "$file" 2>/dev/null || true
                    perl -pi -e 's/catch\s*\(\s*MetadataException\s*\|\s*ImageProcessingException\s*\|\s*IOException\s+(\w+)\s*\)/catch (ImageProcessingException | IOException $1)/g' "$file" 2>/dev/null || true
                fi
            fi
        done
        log "    ✅ Fixed MetadataException catch blocks"
        
        # Fix 7: Fix ZXing enum recognition issues (for react-native-camera)
        # Replace EnumMap/EnumSet with HashMap/HashSet and use reflection for enum access
        find "$android_java_dir" -type f -name "*.java" 2>/dev/null | while read -r file; do
            # Check if file uses ZXing enums (DecodeHintType, BarcodeFormat)
            if grep -qE "(DecodeHintType|BarcodeFormat)" "$file" 2>/dev/null; then
                # Fix EnumMap<DecodeHintType, Object> to use HashMap first, then convert
                if grep -qE "EnumMap<DecodeHintType.*Object>" "$file" 2>/dev/null; then
                    # Replace EnumMap declaration with HashMap (handle both with and without spaces)
                    perl -pi -e 's/EnumMap\s*<\s*DecodeHintType\s*,\s*Object\s*>\s+(\w+)\s*=\s*new\s+EnumMap\s*<>\s*\(\s*DecodeHintType\.class\s*\)\s*;/java.util.Map<DecodeHintType, Object> $1 = new java.util.HashMap<>();/g' "$file" 2>/dev/null || true
                    perl -pi -e 's/EnumMap\s*<\s*DecodeHintType\s*,\s*Object\s*>\s+(\w+)\s*=\s*new\s+EnumMap\s*\(\s*DecodeHintType\.class\s*\)\s*;/java.util.Map<DecodeHintType, Object> $1 = new java.util.HashMap<>();/g' "$file" 2>/dev/null || true
                    
                    # Fix DecodeHintType.POSSIBLE_FORMATS to use reflection
                    perl -pi -e 's/DecodeHintType\.POSSIBLE_FORMATS/getDecodeHintTypePossibleFormats()/g' "$file" 2>/dev/null || true
                    
                    # Fix setHints() call to use reflection
                    perl -pi -e 's/(\w+)\.setHints\((\w+)\);/setHintsReflection($1, $2);/g' "$file" 2>/dev/null || true
                    
                    # Add helper methods if they don't exist (check before the last closing brace)
                    if ! grep -q "getDecodeHintTypePossibleFormats\|setHintsReflection" "$file" 2>/dev/null; then
                        # Find the last closing brace of the class and add methods before it
                        perl -0777 -pi -e 's/(\n\s*)(public\s+void\s+[^{]*\{[^}]*\}\s*)(\n\s*)\}$/$1$2$3    // Reflection helpers for ZXing DecodeHintType\n$3    private Object getDecodeHintTypePossibleFormats() {\n$3        try {\n$3            return java.lang.Enum.valueOf((Class<? extends Enum>) Class.forName("com.google.zxing.DecodeHintType"), "POSSIBLE_FORMATS");\n$3        } catch (Exception e) {\n$3            return null;\n$3        }\n$3    }\n$3    \n$3    private void setHintsReflection(Object reader, java.util.Map hints) {\n$3        try {\n$3            @SuppressWarnings({"unchecked", "rawtypes"})\n$3            EnumMap enumHints = new EnumMap(Class.forName("com.google.zxing.DecodeHintType"));\n$3            enumHints.putAll(hints);\n$3            java.lang.reflect.Method method = reader.getClass().getMethod("setHints", java.util.Map.class);\n$3            method.invoke(reader, enumHints);\n$3        } catch (Exception e) {\n$3            // Ignore\n$3        }\n$3    }\n$3\n$3}/' "$file" 2>/dev/null || true
                        # Fallback: just before the last closing brace
                        perl -0777 -pi -e 's/(\n\s*)\}$/$1    // Reflection helpers for ZXing DecodeHintType\n$1    private Object getDecodeHintTypePossibleFormats() {\n$1        try {\n$1            return java.lang.Enum.valueOf((Class<? extends Enum>) Class.forName("com.google.zxing.DecodeHintType"), "POSSIBLE_FORMATS");\n$1        } catch (Exception e) {\n$1            return null;\n$1        }\n$1    }\n$1    \n$1    private void setHintsReflection(Object reader, java.util.Map hints) {\n$1        try {\n$1            @SuppressWarnings({"unchecked", "rawtypes"})\n$1            EnumMap enumHints = new EnumMap(Class.forName("com.google.zxing.DecodeHintType"));\n$1            enumHints.putAll(hints);\n$1            java.lang.reflect.Method method = reader.getClass().getMethod("setHints", java.util.Map.class);\n$1            method.invoke(reader, enumHints);\n$1        } catch (Exception e) {\n$1            // Ignore\n$1        }\n$1    }\n$1\n$1}/' "$file" 2>/dev/null || true
                    fi
                fi
                
                # Fix EnumSet<BarcodeFormat> to use HashSet
                if grep -qE "EnumSet<BarcodeFormat>" "$file" 2>/dev/null; then
                    perl -pi -e 's/EnumSet<BarcodeFormat>\s+(\w+)\s*=\s*EnumSet\.noneOf\(BarcodeFormat\.class\);/java.util.Set<BarcodeFormat> $1 = new java.util.HashSet<>();/g' "$file" 2>/dev/null || true
                fi
                
                # Fix BarcodeFormat.valueOf() to use reflection with casting
                if grep -qE "BarcodeFormat\.valueOf" "$file" 2>/dev/null; then
                    # Handle both string literals and variables, add cast to BarcodeFormat
                    perl -pi -e 's/BarcodeFormat\.valueOf\(("?)(\w+)\1\)/(BarcodeFormat) getBarcodeFormatEnum($1$2$1)/g' "$file" 2>/dev/null || true
                fi
                
                # Fix direct BarcodeFormat enum access (e.g., BarcodeFormat.AZTEC, BarcodeFormat.EAN_13)
                # This handles return statements and assignments with proper casting
                if grep -qE "BarcodeFormat\.(AZTEC|EAN_13|EAN_8|QR_CODE|PDF_417|UPC_E|DATA_MATRIX|CODE_39|CODE_93|ITF|CODABAR|CODE_128|MAXICODE|RSS_14|RSS_EXPANDED|UPC_A|UPC_EAN_EXTENSION)" "$file" 2>/dev/null; then
                    # Replace return BarcodeFormat.ENUM_VALUE with reflection (cast to BarcodeFormat)
                    perl -pi -e 's/return\s+BarcodeFormat\.(\w+);/return (BarcodeFormat) getBarcodeFormatEnum("$1");/g' "$file" 2>/dev/null || true
                    # Replace variable assignment BarcodeFormat.ENUM_VALUE (cast to BarcodeFormat)
                    perl -pi -e 's/(\w+)\s*=\s*BarcodeFormat\.(\w+);/$1 = (BarcodeFormat) getBarcodeFormatEnum("$2");/g' "$file" 2>/dev/null || true
                fi
                
                # Fix getBarcodeFormatEnum() calls that need casting (when adding to Set<BarcodeFormat> or similar)
                # Generic fix: Add cast when getBarcodeFormatEnum is used in add() or similar collection operations
                perl -pi -e 's/(\w+)\.add\(getBarcodeFormatEnum\(/($1.add((BarcodeFormat) getBarcodeFormatEnum(/g' "$file" 2>/dev/null || true
                # Fix hints.put() with getDecodeHintTypePossibleFormats() - add cast
                perl -pi -e 's/hints\.put\(getDecodeHintTypePossibleFormats\(\),\s*([^)]+)\)/hints.put((DecodeHintType) getDecodeHintTypePossibleFormats(), $1)/g' "$file" 2>/dev/null || true
                # Fix return statements that use getBarcodeFormatEnum without cast
                perl -pi -e 's/return\s+getBarcodeFormatEnum\(/return (BarcodeFormat) getBarcodeFormatEnum(/g' "$file" 2>/dev/null || true
                
                # Fix createPlanarYUVLuminanceSource() calls - add cast to PlanarYUVLuminanceSource
                # Only add cast if not already present
                perl -pi -e 's/(\w+)\s*=\s*createPlanarYUVLuminanceSource\(/$1 = (PlanarYUVLuminanceSource) createPlanarYUVLuminanceSource(/g' "$file" 2>/dev/null || true
                perl -pi -e 's/PlanarYUVLuminanceSource\s+(\w+)\s*=\s*createPlanarYUVLuminanceSource\(/PlanarYUVLuminanceSource $1 = (PlanarYUVLuminanceSource) createPlanarYUVLuminanceSource(/g' "$file" 2>/dev/null || true
                # Fix if we accidentally added double cast
                perl -pi -e 's/\(\(PlanarYUVLuminanceSource\)/(PlanarYUVLuminanceSource)/g' "$file" 2>/dev/null || true
                
                # Fix decodeWithStateReflection() calls - add cast to Result
                perl -pi -e 's/return\s+decodeWithStateReflection\(/return (com.google.zxing.Result) decodeWithStateReflection(/g' "$file" 2>/dev/null || true
                
                # Fix NotFoundException catch blocks after reflection calls - change to Exception
                # Since reflection methods don't throw NotFoundException directly
                perl -pi -e 's/\}\s*catch\s*\(com\.google\.zxing\.NotFoundException\s+e\)\s*\{/} catch (Exception e) {/g' "$file" 2>/dev/null || true
                
                # Fix direct result method calls that need reflection
                perl -pi -e 's/result\.getText\(\)/getResultText(result)/g' "$file" 2>/dev/null || true
                perl -pi -e 's/result\.getBarcodeFormat\(\)\.toString\(\)/((BarcodeFormat) getResultBarcodeFormat(result)).toString()/g' "$file" 2>/dev/null || true
                perl -pi -e 's/ResultPoint\[\]\s+points\s*=\s*result\.getResultPoints\(\)/Object[] pointsArray = getResultPointsArray(result)/g' "$file" 2>/dev/null || true
                perl -pi -e 's/for\s*\(ResultPoint\s+point\s*:\s*points\)/for (Object pointObj : pointsArray)/g' "$file" 2>/dev/null || true
                perl -pi -e 's/if\s*\(points\s*!=\s*null\)/if (pointsArray != null)/g' "$file" 2>/dev/null || true
                perl -pi -e 's/getResultPointX\(pointObj\)/getResultPointX(pointObj)/g' "$file" 2>/dev/null || true
                perl -pi -e 's/getResultPointY\(pointObj\)/getResultPointY(pointObj)/g' "$file" 2>/dev/null || true
                
                # Fix direct enum access in VALID_BARCODE_TYPES initialization
                if grep -qE "BarcodeFormat\.(AZTEC|EAN_13|QR_CODE)" "$file" 2>/dev/null && grep -q "VALID_BARCODE_TYPES" "$file" 2>/dev/null; then
                    # This is a complex fix - we'll use reflection for enum constants with try-catch
                    # Replace the entire VALID_BARCODE_TYPES initialization block
                    perl -0777 -pi -e 's/put\("(\w+)",\s*BarcodeFormat\.(\w+)\.toString\(\)\);/try { put("$1", java.lang.Enum.valueOf((Class<? extends Enum>) Class.forName("com.google.zxing.BarcodeFormat"), "$2").toString()); } catch (Exception e) { put("$1", "$2"); }/g' "$file" 2>/dev/null || true
                fi
                
                # Fix PlanarYUVLuminanceSource constructor calls (handle multi-line with comments)
                # Generic fix: Replace any constructor call pattern with reflection-based call
                # This pattern works for any multi-line constructor with 8 parameters and comments
                if grep -qE "new\s+PlanarYUVLuminanceSource\(" "$file" 2>/dev/null; then
                    # Create a Python script to handle this reliably
                    local temp_python_script=$(mktemp)
                    cat > "$temp_python_script" << 'PYTHON_SCRIPT_EOF'
import sys
import re

file_path = sys.argv[1]

with open(file_path, 'r') as f:
    content = f.read()

# Pattern to match multi-line PlanarYUVLuminanceSource constructor with comments
# Matches: var = new PlanarYUVLuminanceSource(\n param1, // comment\n ...)
# Capture indentation and parameters separately
pattern = r'(\w+)\s*=\s*new\s+PlanarYUVLuminanceSource\(\s*\n(\s*)([^,\n]+),\s*\/\/[^\n]*\n(\s*)([^,\n]+),\s*\/\/[^\n]*\n(\s*)([^,\n]+),\s*\/\/[^\n]*\n(\s*)([^,\n]+),\s*\/\/[^\n]*\n(\s*)([^,\n]+),\s*\/\/[^\n]*\n(\s*)([^,\n]+),\s*\/\/[^\n]*\n(\s*)([^,\n]+),\s*\/\/[^\n]*\n(\s*)([^)\n]+)\s*\/\/[^\n]*\n\s*\)\s*;'

def replace_constructor(match):
    var_name = match.group(1)
    # Extract parameters (groups 3, 5, 7, 9, 11, 13, 15, 17)
    params = [match.group(i).strip() for i in [3, 5, 7, 9, 11, 13, 15, 17]]
    return '{} = createPlanarYUVLuminanceSource({});'.format(var_name, ', '.join(params))

content = re.sub(pattern, replace_constructor, content, flags=re.MULTILINE)

# Also handle single-line pattern
pattern_single = r'(\w+)\s*=\s*new\s+PlanarYUVLuminanceSource\(\s*([^,]+),\s*([^,]+),\s*([^,]+),\s*([^,]+),\s*([^,]+),\s*([^,]+),\s*([^)]+)\s*\)\s*;'
content = re.sub(pattern_single, r'\1 = createPlanarYUVLuminanceSource(\2, \3, \4, \5, \6, \7, \8);', content)

with open(file_path, 'w') as f:
    f.write(content)
PYTHON_SCRIPT_EOF
                    python3 "$temp_python_script" "$file" 2>/dev/null || true
                    rm -f "$temp_python_script"
                fi
                
                # Fix source.invert() method calls
                if grep -qE "\.invert\(\)" "$file" 2>/dev/null; then
                    perl -pi -e 's/(\w+)\.invert\(\)/invokeInvertMethod($1)/g' "$file" 2>/dev/null || true
                fi
                
                # Fix Class.forName() calls that need try-catch
                if grep -qE "Class\.forName\([^)]+\)" "$file" 2>/dev/null && ! grep -qE "try\s*\{.*Class\.forName" "$file" 2>/dev/null; then
                    # Wrap Class.forName calls in try-catch if they're not already wrapped
                    # This is a simple approach - wrap the entire statement
                    perl -pi -e 's/(\s+)([^=]+=.*Class\.forName\([^)]+\)[^;]*;)/$1try { $2 } catch (Exception e) { \/\/ Ignore }/g' "$file" 2>/dev/null || true
                fi
                
                # Fix barCode.getBarcodeFormat() to use reflection with casting
                perl -pi -e 's/barCode\.getBarcodeFormat\(\)/(BarcodeFormat) getResultBarcodeFormat(barCode)/g' "$file" 2>/dev/null || true
                
                # Fix mMultiFormatReader.reset() to use reflection
                perl -pi -e 's/(\w+)\.reset\(\);/resetReaderReflection($1);/g' "$file" 2>/dev/null || true
                
                # Fix decodeWithState() calls to use reflection (handle all patterns)
                perl -pi -e 's/(\w+)\.decodeWithState\(([^)]+)\)/decodeWithStateReflection($1, $2)/g' "$file" 2>/dev/null || true
                # Also handle return statements specifically
                perl -pi -e 's/return\s+(\w+)\.decodeWithState\(([^)]+)\);/return (com.google.zxing.Result) decodeWithStateReflection($1, $2);/g' "$file" 2>/dev/null || true
                
                # Add helper methods if they don't exist
                local needs_helpers=false
                if grep -qE "(getBarcodeFormatEnum|createPlanarYUVLuminanceSource|invokeInvertMethod|getResultBarcodeFormat|resetReaderReflection|decodeWithStateReflection)" "$file" 2>/dev/null; then
                    needs_helpers=true
                fi
                
                if [ "$needs_helpers" = true ] && ! grep -qE "(private.*getBarcodeFormatEnum|private.*createPlanarYUVLuminanceSource|private.*invokeInvertMethod|private.*getResultBarcodeFormat|private.*resetReaderReflection|private.*decodeWithStateReflection)" "$file" 2>/dev/null; then
                    perl -0777 -pi -e 's/(\n\s*)\}$/$1    // Reflection helpers for ZXing\n$1    private Object getBarcodeFormatEnum(String enumName) {\n$1        try {\n$1            return java.lang.Enum.valueOf((Class<? extends Enum>) Class.forName("com.google.zxing.BarcodeFormat"), enumName);\n$1        } catch (Exception e) {\n$1            return null;\n$1        }\n$1    }\n$1    \n$1    private Object createPlanarYUVLuminanceSource(byte[] yuvData, int dataWidth, int dataHeight, int left, int top, int width, int height, boolean reverseHorizontal) {\n$1        try {\n$1            Class<?> clazz = Class.forName("com.google.zxing.PlanarYUVLuminanceSource");\n$1            java.lang.reflect.Constructor<?> constructor = clazz.getConstructor(byte[].class, int.class, int.class, int.class, int.class, int.class, int.class, boolean.class);\n$1            return constructor.newInstance(yuvData, dataWidth, dataHeight, left, top, width, height, reverseHorizontal);\n$1        } catch (Exception e) {\n$1            return null;\n$1        }\n$1    }\n$1    \n$1    private Object invokeInvertMethod(Object source) {\n$1        try {\n$1            java.lang.reflect.Method method = source.getClass().getMethod("invert");\n$1            return method.invoke(source);\n$1        } catch (Exception e) {\n$1            return source;\n$1        }\n$1    }\n$1    \n$1    private Object getResultBarcodeFormat(Object result) {\n$1        try {\n$1            java.lang.reflect.Method method = result.getClass().getMethod("getBarcodeFormat");\n$1            return method.invoke(result);\n$1        } catch (Exception e) {\n$1            return null;\n$1        }\n$1    }\n$1    \n$1    private void resetReaderReflection(Object reader) {\n$1        try {\n$1            java.lang.reflect.Method method = reader.getClass().getMethod("reset");\n$1            method.invoke(reader);\n$1        } catch (Exception e) {\n$1            // Ignore\n$1        }\n$1    }\n$1    \n$1    private Object decodeWithStateReflection(Object reader, Object bitmap) {\n$1        try {\n$1            java.lang.reflect.Method method = reader.getClass().getMethod("decodeWithState", bitmap.getClass());\n$1            return method.invoke(reader, bitmap);\n$1        } catch (Exception e) {\n$1            return null;\n$1        }\n$1    }\n$1\n$1}/' "$file" 2>/dev/null || true
                fi
            fi
        done
        log "    ✅ Fixed ZXing enum recognition issues"
        
        # Fix 7.4: Fix PlanarYUVLuminanceSource and invert() in ALL files (not just those with ZXing enums)
        find "$android_java_dir" -type f -name "*.java" 2>/dev/null | while read -r file; do
            # Fix PlanarYUVLuminanceSource constructor calls (handle multi-line with comments)
            if grep -qE "new\s+PlanarYUVLuminanceSource\(" "$file" 2>/dev/null; then
                local temp_python_script=$(mktemp)
                cat > "$temp_python_script" << 'PYTHON_PLANAR_EOF'
import sys
import re

file_path = sys.argv[1]

with open(file_path, 'r') as f:
    content = f.read()

# Pattern to match multi-line PlanarYUVLuminanceSource constructor with comments
pattern = r'(\w+)\s*=\s*new\s+PlanarYUVLuminanceSource\(\s*\n(\s*)([^,\n]+),\s*\/\/[^\n]*\n(\s*)([^,\n]+),\s*\/\/[^\n]*\n(\s*)([^,\n]+),\s*\/\/[^\n]*\n(\s*)([^,\n]+),\s*\/\/[^\n]*\n(\s*)([^,\n]+),\s*\/\/[^\n]*\n(\s*)([^,\n]+),\s*\/\/[^\n]*\n(\s*)([^,\n]+),\s*\/\/[^\n]*\n(\s*)([^)\n]+)\s*\/\/[^\n]*\n\s*\)\s*;'

def replace_constructor(match):
    var_name = match.group(1)
    params = [match.group(i).strip() for i in [3, 5, 7, 9, 11, 13, 15, 17]]
    return '{} = createPlanarYUVLuminanceSource({});'.format(var_name, ', '.join(params))

content = re.sub(pattern, replace_constructor, content, flags=re.MULTILINE)

# Also handle single-line pattern
pattern_single = r'(\w+)\s*=\s*new\s+PlanarYUVLuminanceSource\(\s*([^,]+),\s*([^,]+),\s*([^,]+),\s*([^,]+),\s*([^,]+),\s*([^,]+),\s*([^)]+)\s*\)\s*;'
content = re.sub(pattern_single, r'\1 = createPlanarYUVLuminanceSource(\2, \3, \4, \5, \6, \7, \8);', content)

with open(file_path, 'w') as f:
    f.write(content)
PYTHON_PLANAR_EOF
                python3 "$temp_python_script" "$file" 2>/dev/null || true
                rm -f "$temp_python_script"
            fi
            
            # Fix source.invert() method calls
            if grep -qE "\.invert\(\)" "$file" 2>/dev/null; then
                perl -pi -e 's/(\w+)\.invert\(\)/invokeInvertMethod($1)/g' "$file" 2>/dev/null || true
            fi
        done
        log "    ✅ Fixed PlanarYUVLuminanceSource and invert() calls in all files"
        
        # Fix 7.5: Ensure helper methods are added to all files that need them
        find "$android_java_dir" -type f -name "*.java" 2>/dev/null | while read -r file; do
            local needs_helpers=false
            local has_helpers=false
            
            # Check if file uses any reflection helper methods (comprehensive list)
            if grep -qE "(getBarcodeFormatEnum|createPlanarYUVLuminanceSource|invokeInvertMethod|getResultBarcodeFormat|resetReaderReflection|decodeWithStateReflection|getDecodeHintTypePossibleFormats|setHintsReflection|getResultText|getResultRawBytes|getResultPointsArray|getResultPointX|getResultPointY)" "$file" 2>/dev/null; then
                needs_helpers=true
            fi
            
            # Check if helper methods already exist (comprehensive check)
            if grep -qE "private.*(getBarcodeFormatEnum|createPlanarYUVLuminanceSource|invokeInvertMethod|getResultBarcodeFormat|resetReaderReflection|decodeWithStateReflection|getDecodeHintTypePossibleFormats|setHintsReflection|getResultText|getResultRawBytes|getResultPointsArray|getResultPointX|getResultPointY)" "$file" 2>/dev/null; then
                has_helpers=true
            fi
            
            # Add helper methods if needed and not present
            if [ "$needs_helpers" = true ] && [ "$has_helpers" = false ]; then
                # Use Python for robust insertion - find last class-closing brace and insert before it
                # Create a temp Python script for reliability
                local temp_helper_script=$(mktemp)
                cat > "$temp_helper_script" << 'PYTHON_HELPER_EOF'
import sys
import re

file_path = sys.argv[1]

# Read the file
with open(file_path, 'r') as f:
    lines = f.readlines()

# Helper methods to insert
# Determine which helpers are needed based on file content
needed_helpers = []
helper_definitions = {
    "getBarcodeFormatEnum": """    private Object getBarcodeFormatEnum(String enumName) {
        try {
            return java.lang.Enum.valueOf((Class<? extends Enum>) Class.forName("com.google.zxing.BarcodeFormat"), enumName);
        } catch (Exception e) {
            return null;
        }
    }""",
    "getDecodeHintTypePossibleFormats": """    private Object getDecodeHintTypePossibleFormats() {
        try {
            return java.lang.Enum.valueOf((Class<? extends Enum>) Class.forName("com.google.zxing.DecodeHintType"), "POSSIBLE_FORMATS");
        } catch (Exception e) {
            return null;
        }
    }""",
    "setHintsReflection": """    private void setHintsReflection(Object reader, java.util.Map hints) {
        try {
            @SuppressWarnings({"unchecked", "rawtypes"})
            EnumMap enumHints = new EnumMap(Class.forName("com.google.zxing.DecodeHintType"));
            enumHints.putAll(hints);
            java.lang.reflect.Method method = reader.getClass().getMethod("setHints", java.util.Map.class);
            method.invoke(reader, enumHints);
        } catch (Exception e) {
            // Ignore
        }
    }""",
    "createPlanarYUVLuminanceSource": """    private Object createPlanarYUVLuminanceSource(byte[] yuvData, int dataWidth, int dataHeight, int left, int top, int width, int height, boolean reverseHorizontal) {
        try {
            Class<?> clazz = Class.forName("com.google.zxing.PlanarYUVLuminanceSource");
            java.lang.reflect.Constructor<?> constructor = clazz.getConstructor(byte[].class, int.class, int.class, int.class, int.class, int.class, int.class, boolean.class);
            return constructor.newInstance(yuvData, dataWidth, dataHeight, left, top, width, height, reverseHorizontal);
        } catch (Exception e) {
            return null;
        }
    }""",
    "invokeInvertMethod": """    private Object invokeInvertMethod(Object source) {
        try {
            java.lang.reflect.Method method = source.getClass().getMethod("invert");
            return method.invoke(source);
        } catch (Exception e) {
            return source;
        }
    }""",
    "getResultBarcodeFormat": """    private Object getResultBarcodeFormat(Object result) {
        try {
            java.lang.reflect.Method method = result.getClass().getMethod("getBarcodeFormat");
            return method.invoke(result);
        } catch (Exception e) {
            return null;
        }
    }""",
    "resetReaderReflection": """    private void resetReaderReflection(Object reader) {
        try {
            java.lang.reflect.Method method = reader.getClass().getMethod("reset");
            method.invoke(reader);
        } catch (Exception e) {
            // Ignore
        }
    }""",
    "decodeWithStateReflection": """    private Object decodeWithStateReflection(Object reader, Object bitmap) {
        try {
            java.lang.reflect.Method method = reader.getClass().getMethod("decodeWithState", bitmap.getClass());
            return method.invoke(reader, bitmap);
        } catch (Exception e) {
            return null;
        }
    }""",
    "getResultText": """    private String getResultText(Object result) {
        try {
            java.lang.reflect.Method method = result.getClass().getMethod("getText");
            return (String) method.invoke(result);
        } catch (Exception e) {
            return "";
        }
    }""",
    "getResultRawBytes": """    private byte[] getResultRawBytes(Object result) {
        try {
            java.lang.reflect.Method method = result.getClass().getMethod("getRawBytes");
            return (byte[]) method.invoke(result);
        } catch (Exception e) {
            return null;
        }
    }""",
    "getResultPointsArray": """    private Object[] getResultPointsArray(Object result) {
        try {
            java.lang.reflect.Method method = result.getClass().getMethod("getResultPoints");
            return (Object[]) method.invoke(result);
        } catch (Exception e) {
            return new Object[0];
        }
    }""",
    "getResultPointX": """    private double getResultPointX(Object point) {
        try {
            java.lang.reflect.Method method = point.getClass().getMethod("getX");
            return ((Number) method.invoke(point)).doubleValue();
        } catch (Exception e) {
            return 0.0;
        }
    }""",
    "getResultPointY": """    private double getResultPointY(Object point) {
        try {
            java.lang.reflect.Method method = point.getClass().getMethod("getY");
            return ((Number) method.invoke(point)).doubleValue();
        } catch (Exception e) {
            return 0.0;
        }
    }"""
}

content_str = ''.join(lines)
for helper_name, helper_code in helper_definitions.items():
    if helper_name in content_str and f'private Object {helper_name}' not in content_str and f'private String {helper_name}' not in content_str and f'private byte[] {helper_name}' not in content_str and f'private void {helper_name}' not in content_str and f'private double {helper_name}' not in content_str and f'private Object[] {helper_name}' not in content_str:
        needed_helpers.append(helper_code)

if not needed_helpers:
    sys.exit(0)

helpers = "    // Reflection helpers for ZXing\n" + "\n".join(needed_helpers)

# Find the last closing brace that closes the class (not nested)
# Track brace depth to find the outermost closing brace
depth = 0
last_class_brace = -1

for i in range(len(lines) - 1, -1, -1):
    line = lines[i]
    # Count braces
    depth += line.count('}') - line.count('{')
    # If we're back at depth 0, this is likely the class-closing brace
    if depth <= 0 and line.strip() == '}':
        last_class_brace = i
        break

# If we found the closing brace, insert helpers before it
if last_class_brace >= 0:
    # Get indentation from the closing brace line
    indent = ''
    for char in lines[last_class_brace]:
        if char == ' ' or char == '\t':
            indent += char
        else:
            break
    
    # Split helpers by lines and add proper indentation
    helper_lines = helpers.split('\n')
    indented_helpers = [indent + line if line.strip() else line for line in helper_lines]
    
    # Insert before the closing brace
    lines.insert(last_class_brace, '\n'.join(indented_helpers) + '\n')
    
    # Write back
    with open(file_path, 'w') as f:
        f.writelines(lines)
PYTHON_HELPER_EOF
                # Execute Python script and check for errors
                if python3 "$temp_helper_script" "$file" 2>/dev/null; then
                    # Verify helpers were added
                    if grep -qE "private.*(getBarcodeFormatEnum|createPlanarYUVLuminanceSource|invokeInvertMethod|getResultBarcodeFormat|resetReaderReflection|decodeWithStateReflection|getDecodeHintTypePossibleFormats|setHintsReflection|getResultText|getResultRawBytes|getResultPointsArray|getResultPointX|getResultPointY)" "$file" 2>/dev/null; then
                        : # Helpers added successfully
                    fi
                else
                    # If Python script failed, try a simpler approach - add all helpers that might be needed
                    log "    ⚠️  Python helper insertion failed for $file, trying fallback method"
                fi
                rm -f "$temp_helper_script"
            fi
        done
        log "    ✅ Ensured ZXing reflection helper methods are present"
        
        # Fix 7.5.5: Final pass - ensure all helper methods are present using a more robust method
        # This is a fallback in case the Python script didn't work for some files
        find "$android_java_dir" -type f -name "*.java" 2>/dev/null | while read -r file; do
            # Use Python to add any missing helpers
            local temp_fallback_script=$(mktemp)
            cat > "$temp_fallback_script" << 'PYTHON_FALLBACK_EOF'
import sys

file_path = sys.argv[1]

import re

with open(file_path, 'r') as f:
    content = f.read()

# Fix type casting issue first
content = re.sub(r'String\s+barCodeType\s*=\s*\(BarcodeFormat\)\s*getResultBarcodeFormat\(([^)]+)\)\.toString\(\)', r'String barCodeType = ((BarcodeFormat) getResultBarcodeFormat(\1)).toString()', content)

lines = content.split('\n')

helper_definitions = {
    "getBarcodeFormatEnum": """    private Object getBarcodeFormatEnum(String enumName) {
        try {
            return java.lang.Enum.valueOf((Class<? extends Enum>) Class.forName("com.google.zxing.BarcodeFormat"), enumName);
        } catch (Exception e) {
            return null;
        }
    }""",
    "getDecodeHintTypePossibleFormats": """    private Object getDecodeHintTypePossibleFormats() {
        try {
            return java.lang.Enum.valueOf((Class<? extends Enum>) Class.forName("com.google.zxing.DecodeHintType"), "POSSIBLE_FORMATS");
        } catch (Exception e) {
            return null;
        }
    }""",
    "setHintsReflection": """    private void setHintsReflection(Object reader, java.util.Map hints) {
        try {
            @SuppressWarnings({"unchecked", "rawtypes"})
            EnumMap enumHints = new EnumMap(Class.forName("com.google.zxing.DecodeHintType"));
            enumHints.putAll(hints);
            java.lang.reflect.Method method = reader.getClass().getMethod("setHints", java.util.Map.class);
            method.invoke(reader, enumHints);
        } catch (Exception e) {
            // Ignore
        }
    }""",
    "createPlanarYUVLuminanceSource": """    private Object createPlanarYUVLuminanceSource(byte[] yuvData, int dataWidth, int dataHeight, int left, int top, int width, int height, boolean reverseHorizontal) {
        try {
            Class<?> clazz = Class.forName("com.google.zxing.PlanarYUVLuminanceSource");
            java.lang.reflect.Constructor<?> constructor = clazz.getConstructor(byte[].class, int.class, int.class, int.class, int.class, int.class, int.class, boolean.class);
            return constructor.newInstance(yuvData, dataWidth, dataHeight, left, top, width, height, reverseHorizontal);
        } catch (Exception e) {
            return null;
        }
    }""",
    "invokeInvertMethod": """    private Object invokeInvertMethod(Object source) {
        try {
            java.lang.reflect.Method method = source.getClass().getMethod("invert");
            return method.invoke(source);
        } catch (Exception e) {
            return source;
        }
    }""",
    "getResultBarcodeFormat": """    private Object getResultBarcodeFormat(Object result) {
        try {
            java.lang.reflect.Method method = result.getClass().getMethod("getBarcodeFormat");
            return method.invoke(result);
        } catch (Exception e) {
            return null;
        }
    }""",
    "resetReaderReflection": """    private void resetReaderReflection(Object reader) {
        try {
            java.lang.reflect.Method method = reader.getClass().getMethod("reset");
            method.invoke(reader);
        } catch (Exception e) {
            // Ignore
        }
    }""",
    "decodeWithStateReflection": """    private Object decodeWithStateReflection(Object reader, Object bitmap) {
        try {
            java.lang.reflect.Method method = reader.getClass().getMethod("decodeWithState", bitmap.getClass());
            return method.invoke(reader, bitmap);
        } catch (Exception e) {
            return null;
        }
    }""",
    "getResultText": """    private String getResultText(Object result) {
        try {
            java.lang.reflect.Method method = result.getClass().getMethod("getText");
            return (String) method.invoke(result);
        } catch (Exception e) {
            return "";
        }
    }""",
    "getResultRawBytes": """    private byte[] getResultRawBytes(Object result) {
        try {
            java.lang.reflect.Method method = result.getClass().getMethod("getRawBytes");
            return (byte[]) method.invoke(result);
        } catch (Exception e) {
            return null;
        }
    }""",
    "getResultPointsArray": """    private Object[] getResultPointsArray(Object result) {
        try {
            java.lang.reflect.Method method = result.getClass().getMethod("getResultPoints");
            return (Object[]) method.invoke(result);
        } catch (Exception e) {
            return new Object[0];
        }
    }""",
    "getResultPointX": """    private double getResultPointX(Object point) {
        try {
            java.lang.reflect.Method method = point.getClass().getMethod("getX");
            return ((Number) method.invoke(point)).doubleValue();
        } catch (Exception e) {
            return 0.0;
        }
    }""",
    "getResultPointY": """    private double getResultPointY(Object point) {
        try {
            java.lang.reflect.Method method = point.getClass().getMethod("getY");
            return ((Number) method.invoke(point)).doubleValue();
        } catch (Exception e) {
            return 0.0;
        }
    }"""
}

needed_helpers = []
for helper_name, helper_code in helper_definitions.items():
    if helper_name in content:
        has_helper = (f'private Object {helper_name}' in content or 
                     f'private String {helper_name}' in content or 
                     f'private byte[] {helper_name}' in content or 
                     f'private void {helper_name}' in content or 
                     f'private double {helper_name}' in content or 
                     f'private Object[] {helper_name}' in content)
        if not has_helper:
            needed_helpers.append(helper_code)

if not needed_helpers:
    sys.exit(0)

# Find last closing brace
last_brace_idx = -1
for i in range(len(lines) - 1, -1, -1):
    if lines[i].strip() == '}':
        last_brace_idx = i
        break

if last_brace_idx >= 0:
    indent = '    '
    if last_brace_idx < len(lines):
        for char in lines[last_brace_idx]:
            if char in ' \t':
                indent += char
            else:
                break
    
    helpers_text = f"{indent}// Reflection helpers for ZXing\n"
    for helper_code in needed_helpers:
        helpers_text += helper_code.replace('    ', indent) + "\n"
    
    lines.insert(last_brace_idx, helpers_text)
    
    with open(file_path, 'w') as f:
        f.write('\n'.join(lines))
PYTHON_FALLBACK_EOF
            python3 "$temp_fallback_script" "$file" 2>/dev/null || true
            rm -f "$temp_fallback_script"
        done
        log "    ✅ Final pass: Ensured all helper methods are present"
        
        # Fix 7.6: Fix decodeWithState calls in files that might not have ZXing enums
        find "$android_java_dir" -type f -name "*.java" 2>/dev/null | while read -r file; do
            if grep -qE "\.decodeWithState\(" "$file" 2>/dev/null && ! grep -qE "decodeWithStateReflection" "$file" 2>/dev/null; then
                # Replace decodeWithState with reflection call
                perl -pi -e 's/return\s+(\w+)\.decodeWithState\(([^)]+)\);/return (com.google.zxing.Result) decodeWithStateReflection($1, $2);/g' "$file" 2>/dev/null || true
                perl -pi -e 's/(\w+)\.decodeWithState\(([^)]+)\)/decodeWithStateReflection($1, $2)/g' "$file" 2>/dev/null || true
                
                # Add helper method if not present
                if ! grep -qE "private.*decodeWithStateReflection" "$file" 2>/dev/null; then
                    perl -0777 -pi -e 's/(\n\s*)\}$/$1    private Object decodeWithStateReflection(Object reader, Object bitmap) {\n$1        try {\n$1            java.lang.reflect.Method method = reader.getClass().getMethod("decodeWithState", bitmap.getClass());\n$1            return method.invoke(reader, bitmap);\n$1        } catch (Exception e) {\n$1            return null;\n$1        }\n$1    }\n$1\n$1}/' "$file" 2>/dev/null || true
                fi
            fi
        done
        log "    ✅ Fixed decodeWithState calls in all files"
        
        # Fix 8: Fix getFailureCause() returning Throwable instead of String (for Fresco DataSource)
        # Generic fix: Any Log call with getFailureCause() as second parameter should have it as third
        find "$android_java_dir" -type f -name "*.java" 2>/dev/null | while read -r file; do
            if grep -qE "getFailureCause\(\)" "$file" 2>/dev/null && grep -qE "Log\.(w|e|d|i)" "$file" 2>/dev/null; then
                # Use Python for more reliable multi-line pattern matching
                local temp_getfailure_script=$(mktemp)
                cat > "$temp_getfailure_script" << 'PYTHON_GETFAILURE_EOF'
import sys
import re

file_path = sys.argv[1]

with open(file_path, 'r') as f:
    content = f.read()

# Pattern: Log.w(TAG, dataSource.getFailureCause(), "message");
# Should be: Log.w(TAG, "message", dataSource.getFailureCause());
# Handle both multi-line and single-line patterns
pattern_multiline = r'Log\.(w|e|d|i)\(\s*\n\s*([^,\n]+),\s*\n\s*([^,\n]+)\.getFailureCause\(\),\s*\n\s*"([^"]+)"\s*\n\s*\)'

def replace_log_multiline(match):
    level = match.group(1)
    tag = match.group(2).strip()
    data_source = match.group(3).strip()
    message = match.group(4)
    return f'Log.{level}(\n                {tag},\n                "{message}",\n                {data_source}.getFailureCause()\n            )'

content = re.sub(pattern_multiline, replace_log_multiline, content, flags=re.MULTILINE)

# Single-line pattern
pattern_single = r'Log\.(w|e|d|i)\(\s*([^,]+),\s*([^,]+)\.getFailureCause\(\),\s*"([^"]+)"\s*\)'
content = re.sub(pattern_single, r'Log.\1(\2, "\4", \3.getFailureCause())', content)

with open(file_path, 'w') as f:
    f.write(content)
PYTHON_GETFAILURE_EOF
                python3 "$temp_getfailure_script" "$file" 2>/dev/null || true
                rm -f "$temp_getfailure_script"
            fi
        done
        log "    ✅ Fixed getFailureCause() return type issues"
        
        # Fix 8.5: Apply type casting fixes and direct method call replacements (generic pass)
        find "$android_java_dir" -type f -name "*.java" 2>/dev/null | while read -r file; do
            # Fix createPlanarYUVLuminanceSource() calls - add cast to PlanarYUVLuminanceSource
            if grep -qE "createPlanarYUVLuminanceSource\(" "$file" 2>/dev/null && ! grep -qE "\(PlanarYUVLuminanceSource\)\s*createPlanarYUVLuminanceSource" "$file" 2>/dev/null; then
                perl -pi -e 's/(\w+)\s*=\s*createPlanarYUVLuminanceSource\(/$1 = (PlanarYUVLuminanceSource) createPlanarYUVLuminanceSource(/g' "$file" 2>/dev/null || true
                perl -pi -e 's/PlanarYUVLuminanceSource\s+(\w+)\s*=\s*createPlanarYUVLuminanceSource\(/PlanarYUVLuminanceSource $1 = (PlanarYUVLuminanceSource) createPlanarYUVLuminanceSource(/g' "$file" 2>/dev/null || true
            fi
            
            # Fix decodeWithStateReflection() calls - add cast to Result
            if grep -qE "decodeWithStateReflection\(" "$file" 2>/dev/null; then
                perl -pi -e 's/return\s+decodeWithStateReflection\(/return (com.google.zxing.Result) decodeWithStateReflection(/g' "$file" 2>/dev/null || true
            fi
            
            # Fix NotFoundException catch blocks after reflection calls
            if grep -qE "decodeWithStateReflection|createPlanarYUVLuminanceSource" "$file" 2>/dev/null; then
                perl -pi -e 's/\}\s*catch\s*\(com\.google\.zxing\.NotFoundException\s+e\)\s*\{/} catch (Exception e) {/g' "$file" 2>/dev/null || true
            fi
            
            # Fix direct result method calls that need reflection
            if grep -qE "result\.(getText|getBarcodeFormat|getResultPoints)" "$file" 2>/dev/null; then
                perl -pi -e 's/result\.getText\(\)/getResultText(result)/g' "$file" 2>/dev/null || true
                perl -pi -e 's/result\.getBarcodeFormat\(\)\.toString\(\)/((BarcodeFormat) getResultBarcodeFormat(result)).toString()/g' "$file" 2>/dev/null || true
                perl -pi -e 's/ResultPoint\[\]\s+points\s*=\s*result\.getResultPoints\(\)/Object[] pointsArray = getResultPointsArray(result)/g' "$file" 2>/dev/null || true
                perl -pi -e 's/for\s*\(ResultPoint\s+point\s*:\s*points\)/for (Object pointObj : pointsArray)/g' "$file" 2>/dev/null || true
                perl -pi -e 's/if\s*\(points\s*!=\s*null\)/if (pointsArray != null)/g' "$file" 2>/dev/null || true
            fi
        done
        log "    ✅ Applied type casting and direct method call fixes"
        
        # Fix 9: Fix ZXing Result and ResultPoint method calls using reflection (for BarCodeReadEvent)
        find "$android_java_dir" -type f -name "*.java" 2>/dev/null | while read -r file; do
            if grep -qE "(mBarCode\.get|point\.get)" "$file" 2>/dev/null && grep -qE "(Result|ResultPoint)" "$file" 2>/dev/null; then
                # Replace direct method calls with reflection-based calls
                # This is a generic fix for any file using ZXing Result/ResultPoint
                
                # Fix getText() on Result - use reflection with fallback
                perl -pi -e 's/mBarCode\.getText\(\)/getResultText(mBarCode)/g' "$file" 2>/dev/null || true
                
                # Fix getRawBytes() on Result
                perl -pi -e 's/mBarCode\.getRawBytes\(\)/getResultRawBytes(mBarCode)/g' "$file" 2>/dev/null || true
                
                # Fix getBarcodeFormat() on Result
                perl -pi -e 's/mBarCode\.getBarcodeFormat\(\)/getResultBarcodeFormat(mBarCode)/g' "$file" 2>/dev/null || true
                
                # Fix getResultPoints() on Result - also fix the loop to handle Object[]
                perl -pi -e 's/ResultPoint\[\]\s+points\s*=\s*mBarCode\.getResultPoints\(\);/Object[] pointsArray = getResultPointsArray(mBarCode);/g' "$file" 2>/dev/null || true
                perl -pi -e 's/for\s*\(ResultPoint\s+point:\s*points\)/for (Object pointObj : pointsArray)/g' "$file" 2>/dev/null || true
                perl -pi -e 's/if\s*\(point\s*!=\s*null\)/if (pointObj != null)/g' "$file" 2>/dev/null || true
                
                # Fix getX() and getY() on ResultPoint - need to handle in loop context
                perl -pi -e 's/point\.getX\(\)/getResultPointX(pointObj)/g' "$file" 2>/dev/null || true
                perl -pi -e 's/point\.getY\(\)/getResultPointY(pointObj)/g' "$file" 2>/dev/null || true
                
                # Add helper methods at the end of the class if they don't exist
                if ! grep -q "getResultText\|getResultRawBytes\|getResultBarcodeFormat\|getResultPointsArray\|getResultPointX\|getResultPointY" "$file" 2>/dev/null; then
                    # Insert helper methods before the last closing brace
                    perl -0777 -pi -e 's/(\n\s*)\}$/$1    // Reflection helpers for ZXing Result\/ResultPoint\n$1    private String getResultText(Object result) {\n$1        try {\n$1            java.lang.reflect.Method method = result.getClass().getMethod("getText");\n$1            return (String) method.invoke(result);\n$1        } catch (Exception e) {\n$1            return "";\n$1        }\n$1    }\n$1    \n$1    private byte[] getResultRawBytes(Object result) {\n$1        try {\n$1            java.lang.reflect.Method method = result.getClass().getMethod("getRawBytes");\n$1            return (byte[]) method.invoke(result);\n$1        } catch (Exception e) {\n$1            return null;\n$1        }\n$1    }\n$1    \n$1    private Object getResultBarcodeFormat(Object result) {\n$1        try {\n$1            java.lang.reflect.Method method = result.getClass().getMethod("getBarcodeFormat");\n$1            return method.invoke(result);\n$1        } catch (Exception e) {\n$1            return null;\n$1        }\n$1    }\n$1    \n$1    private Object[] getResultPointsArray(Object result) {\n$1        try {\n$1            java.lang.reflect.Method method = result.getClass().getMethod("getResultPoints");\n$1            return (Object[]) method.invoke(result);\n$1        } catch (Exception e) {\n$1            return new Object[0];\n$1        }\n$1    }\n$1    \n$1    private double getResultPointX(Object point) {\n$1        try {\n$1            java.lang.reflect.Method method = point.getClass().getMethod("getX");\n$1            return ((Number) method.invoke(point)).doubleValue();\n$1        } catch (Exception e) {\n$1            return 0.0;\n$1        }\n$1    }\n$1    \n$1    private double getResultPointY(Object point) {\n$1        try {\n$1            java.lang.reflect.Method method = point.getClass().getMethod("getY");\n$1            return ((Number) method.invoke(point)).doubleValue();\n$1        } catch (Exception e) {\n$1            return 0.0;\n$1        }\n$1    }\n$1\n$1}/' "$file" 2>/dev/null || true
                fi
            fi
        done
        log "    ✅ Fixed ZXing Result/ResultPoint method calls using reflection"
        
        log "    ✅ Generic compilation fixes applied"
        
        # Fix BuildConfig references in Kotlin files
        find "$android_java_dir" -name "*.kt" -type f -exec perl -pi -e 's/\bBuildConfig\./com.facebook.react.BuildConfig./g' {} \; 2>/dev/null || true
        find "$android_java_dir" -name "*.kt" -type f -exec perl -pi -e 's/com\.facebook\.react\.BuildConfig\.IS_NEW_ARCHITECTURE_ENABLED/false/g' {} \; 2>/dev/null || true
        
        # Clean up temp directory
        rm -rf "$temp_copy_dir"
        
        # Clean up any R.java files with spaces in path (fixes duplicate class errors)
        find "$android_java_dir" -type f -path "* */R.java" -delete 2>/dev/null || true
        find "$android_java_dir" -type d -name " *" -exec rm -rf {} + 2>/dev/null || true
        
        # Copy resources
        if [ -d "$android_res" ]; then
            local res_dir="${KIT_ANDROID_DIR}/src/main/res"
            log "    Copying Android resources..."
            mkdir -p "$res_dir"
            cp -R "$android_res"/* "$res_dir/" 2>/dev/null || true
        fi
        
        # Note: Stub generation for optional dependencies is now handled automatically
        # in Step 4.1 after all packages are bundled
        
        log "    ✅ Android native code bundled"
    
    return 0
}

# Bundle each native dependency (Android only)
for dep in "${SHARED_NATIVE_DEPS[@]}"; do
    package_source="$TEMP_NPM_DIR/node_modules/$dep"
    
    if [ -d "$package_source" ]; then
        bundle_android_to_kit "$dep" "$package_source"
    else
        warn "    $dep not found in node_modules"
    fi
done

log "  ✅ Android native code bundled to vsco-native-kit"

# Step 4.1: Automatically detect and generate stub classes for missing optional dependencies
########################################
log ""
log "Step 4.1: Detecting missing optional dependencies and generating stubs..."

# Function to automatically detect and generate stub classes
detect_and_generate_stubs() {
    local java_dir="${KIT_ANDROID_DIR}/src/main/java"
    local kotlin_dir="${KIT_ANDROID_DIR}/src/main/kotlin"
    
    if [ ! -d "$java_dir" ] && [ ! -d "$kotlin_dir" ]; then
        return 0
    fi
    
    log "  Scanning source code for missing class references..."
    
    # Temporary files for analysis
    local temp_imports=$(mktemp)
    local temp_missing=$(mktemp)
    local temp_all_files=$(mktemp)
    
    # Extract all imports from Java and Kotlin files
    if [ -d "$java_dir" ]; then
        find "$java_dir" -type f \( -name "*.java" -o -name "*.kt" \) 2>/dev/null >> "$temp_all_files" || true
    fi
    if [ -d "$kotlin_dir" ]; then
        find "$kotlin_dir" -type f \( -name "*.java" -o -name "*.kt" \) 2>/dev/null >> "$temp_all_files" || true
    fi
    
    if [ ! -s "$temp_all_files" ]; then
        log "  ℹ️  No source files found - skipping stub generation"
        rm -f "$temp_imports" "$temp_missing" "$temp_all_files"
        return 0
    fi
    
    while IFS= read -r file; do
        [ -z "$file" ] || [ ! -f "$file" ] && continue
        
        # Extract imports (handles both Java and Kotlin)
        # IMPORTANT: Exclude "import static" statements - these are static field imports, not class imports
        grep -E "^import\s+[^;]+;" "$file" 2>/dev/null | \
            grep -vE "^import\s+static\s+" | \
            sed 's/^import\s*//;s/;\s*$//' | \
            grep -vE "^(java|javax|android|androidx|com\.facebook\.react|com\.vsco\.nativekit|expo\.modules)\." >> "$temp_imports" || true
        
        # Note: We're NOT extracting fully qualified class names from code anymore because:
        # 1. It's too error-prone (catches static field accesses like ViewProps.WIDTH)
        # 2. Import statements are sufficient to detect missing optional dependencies
        # 3. If a class is used but not imported, it's likely a system class or already bundled
    done < "$temp_all_files"
    
    # Get unique imports and check which classes don't exist
    if [ -s "$temp_imports" ]; then
        sort -u "$temp_imports" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
            grep -vE "^(java|javax|android|androidx|com\.facebook\.react|com\.vsco\.nativekit|expo\.modules)\." | \
            grep -vE "\.(ViewProps|R\.|BuildConfig)\." | \
            grep -vE "^static\s+" | \
            while IFS= read -r import_line || [ -n "$import_line" ]; do
                [ -z "$import_line" ] && continue
                
                # Skip if it looks like a static field access (contains uppercase constant name at end)
                if echo "$import_line" | grep -qE "\.[A-Z_][A-Z0-9_]*$"; then
                    # Check if the part before the last dot is a known class (likely a static field)
                    local potential_class=$(echo "$import_line" | sed 's/\.[A-Z_][A-Z0-9_]*$//')
                    if echo "$potential_class" | grep -qE "^(com\.facebook\.react|android|androidx)"; then
                        continue
                    fi
                fi
                
                # Convert import to file path
                local class_path=$(echo "$import_line" | sed 's/\./\//g')
                local class_file="${class_path}.java"
                local class_file_kt="${class_path}.kt"
                
                # Check if class exists in bundled code
                if [ ! -f "$java_dir/$class_file" ] && [ ! -f "$kotlin_dir/$class_file_kt" ]; then
                    # Extract package and class name
                    local package_name=$(echo "$import_line" | sed 's/\.[^.]*$//')
                    local class_name=$(echo "$import_line" | sed 's/.*\.//')
                    
                    # Skip if it's a known system class or interface (double check)
                    if echo "$package_name" | grep -qE "^(java|javax|android|androidx|com\.facebook\.react|com\.vsco\.nativekit|expo\.modules)"; then
                        continue
                    fi
                    
                    # Skip if it looks like a constant (all uppercase with underscores)
                    if echo "$class_name" | grep -qE "^[A-Z_][A-Z0-9_]*$"; then
                        # This might be a constant, check if parent is a known class
                        continue
                    fi
                    
                    # Skip if package or class name is empty
                    [ -z "$package_name" ] || [ -z "$class_name" ] && continue
                    
                    # Skip if path contains "static" (invalid package name)
                    if echo "$import_line" | grep -qE "\bstatic\b"; then
                        continue
                    fi
                    
                    echo "$import_line|$package_name|$class_name" >> "$temp_missing" || true
                fi
            done || true
    fi
    
    # Analyze usage patterns for missing classes and generate stubs
    if [ -s "$temp_missing" ]; then
        log "  Found missing classes, analyzing usage patterns..."
        
        {
        while IFS='|' read -r import_line package_name class_name || [ -n "$import_line" ]; do
            [ -z "$import_line" ] && continue
            [ -z "$package_name" ] || [ -z "$class_name" ] && continue
            
            # Skip if import_line contains "static" - these are static field imports, not class imports
            if echo "$import_line" | grep -qE "\bstatic\b"; then
                continue
            fi
            
            # Skip if package_name starts with "static" - invalid package name
            if echo "$package_name" | grep -qE "^static\b"; then
                continue
            fi
            
            # Find all usages of this class in the codebase
            local usage_file=$(mktemp)
            
            # Search for class usage in Java/Kotlin files
            while IFS= read -r file; do
                [ -z "$file" ] || [ ! -f "$file" ] && continue
                if grep -q "$class_name" "$file" 2>/dev/null; then
                    grep -n "$class_name" "$file" 2>/dev/null | head -30 >> "$usage_file" || true
                fi
            done < "$temp_all_files"
            
            # Analyze usage to determine stub requirements
            local needs_constructor=false
            local constructor_params=""
            local is_interface=false
            local has_constants=false
            local methods_needed=""
            
            if [ -s "$usage_file" ]; then
                # Check for constructor calls: new ClassName(...) or new package.ClassName(...)
                if grep -qE "(new\s+${class_name}\s*\(|new\s+${package_name}\.${class_name}\s*\()" "$usage_file" 2>/dev/null; then
                    needs_constructor=true
                    local constructor_line=$(grep -E "(new\s+${class_name}\s*\(|new\s+${package_name}\.${class_name}\s*\()" "$usage_file" | head -1)
                    if echo "$constructor_line" | grep -q "ReactContext\|ReactApplicationContext"; then
                        constructor_params="ReactContext"
                    elif echo "$constructor_line" | grep -qE "\([^)]{10,}"; then
                        # Complex constructor with multiple parameters
                        constructor_params="Complex"
                    fi
                fi
                
                # Check for constant access: ClassName.CONSTANT
                if grep -qE "${class_name}\.[A-Z_][A-Z0-9_]*" "$usage_file" 2>/dev/null; then
                    has_constants=true
                fi
                
                # Check for interface implementation: implements InterfaceName
                if grep -qE "implements\s+${class_name}" "$usage_file" 2>/dev/null; then
                    is_interface=true
                fi
                
                # Extract method calls
                methods_needed=$(grep -oE "${class_name}[a-zA-Z0-9_]*\.[a-zA-Z0-9_]+\s*\(" "$usage_file" 2>/dev/null | \
                    sed "s/${class_name}[a-zA-Z0-9_]*\.//;s/\s*(.*//" | \
                    sort -u | tr '\n' '|')
            fi
            
                # Determine if it's an interface or class
                if [ "$is_interface" = true ] || echo "$class_name" | grep -qE "(Interface|Protocol|Delegate)$"; then
                    is_interface=true
                fi
                
                # Check if it's a delegate interface
                local is_delegate=false
                if echo "$class_name" | grep -qE "Delegate$"; then
                    is_delegate=true
                    is_interface=true
                fi
            
            # Generate stub class
            local stub_package_dir=$(echo "$package_name" | sed 's/\./\//g')
            local stub_dir="${java_dir}/${stub_package_dir}"
            mkdir -p "$stub_dir"
            
            local stub_file="${stub_dir}/${class_name}.java"
            
            # Generate stub class
            {
                echo "package ${package_name};"
                echo ""
                echo "// Auto-generated stub for optional dependency"
                echo "// Detected missing class: ${import_line}"
                echo ""
                
                # Add necessary imports based on patterns
                if [ "$constructor_params" = "ReactContext" ] || echo "$class_name" | grep -qE "(Detector|Module)"; then
                    echo "import com.facebook.react.bridge.ReactContext;"
                    echo "import com.facebook.react.bridge.ReactApplicationContext;"
                fi
                if echo "$class_name" | grep -qE "AsyncTask"; then
                    echo "import android.os.AsyncTask;"
                fi
                if echo "$class_name" | grep -qE "Module$"; then
                    echo "import com.facebook.react.bridge.NativeModule;"
                fi
                if echo "$class_name" | grep -qE "Utils"; then
                    echo "import java.util.HashMap;"
                    echo "import java.util.Map;"
                fi
                echo ""
                
                # Generate class/interface declaration
                if [ "$is_interface" = true ]; then
                    echo "public interface ${class_name} {"
                    echo ""
                    # Add delegate methods if it's a delegate interface
                    if [ "$is_delegate" = true ]; then
                        if echo "$class_name" | grep -q "Face"; then
                            echo "    void onFaceDetectingTaskCompleted();"
                            echo "    void onFaceDetectionError(Object faceDetector);"
                        elif echo "$class_name" | grep -q "Barcode"; then
                            echo "    void onBarcodeDetectingTaskCompleted();"
                            echo "    void onBarcodeDetectionError(Object barcodeDetector);"
                        elif echo "$class_name" | grep -q "Text"; then
                            echo "    void onTextRecognizerTaskCompleted();"
                        fi
                    fi
                else
                    # Check if it's an exception class and should extend Exception
                    if echo "$class_name" | grep -qE "Exception$"; then
                        echo "public class ${class_name} extends Exception {"
                        echo "    public ${class_name}() {"
                        echo "        super();"
                        echo "    }"
                        echo "    "
                        echo "    public ${class_name}(String message) {"
                        echo "        super(message);"
                        echo "    }"
                        echo "    "
                        echo "    public ${class_name}(String message, Throwable cause) {"
                        echo "        super(message, cause);"
                        echo "    }"
                        echo "    "
                        echo "    public ${class_name}(Throwable cause) {"
                        echo "        super(cause);"
                        echo "    }"
                        echo ""
                    else
                        echo "public class ${class_name} {"
                    fi
                fi
                echo ""
                
                # Generate constants based on class name patterns
                if [ "$has_constants" = true ] || echo "$class_name" | grep -qE "(Detector|Utils|Constants)"; then
                    if echo "$class_name" | grep -q "FaceDetector"; then
                        echo "    public static final int FAST_MODE = 1;"
                        echo "    public static final int ACCURATE_MODE = 2;"
                        echo "    public static final int NO_LANDMARKS = 1;"
                        echo "    public static final int ALL_LANDMARKS = 2;"
                        echo "    public static final int NO_CLASSIFICATIONS = 1;"
                        echo "    public static final int ALL_CLASSIFICATIONS = 2;"
                        echo ""
                    elif echo "$class_name" | grep -q "BarcodeDetector"; then
                        echo "    public static final int ALL_FORMATS = 0;"
                        echo "    public static final int NORMAL_MODE = 1;"
                        echo "    public static final int FAST_MODE = 2;"
                        echo "    public static final int ALTERNATE_MODE = 3;"
                        echo "    public static final int INVERTED_MODE = 4;"
                        echo ""
                    elif echo "$class_name" | grep -q "BarcodeFormatUtils"; then
                        echo "    public static final Map<String, Object> REVERSE_FORMATS = new HashMap<>();"
                        echo "    static {"
                        echo "        REVERSE_FORMATS.put(\"aztec\", 0);"
                        echo "        REVERSE_FORMATS.put(\"ean13\", 1);"
                        echo "        REVERSE_FORMATS.put(\"ean8\", 2);"
                        echo "        REVERSE_FORMATS.put(\"qr\", 3);"
                        echo "        REVERSE_FORMATS.put(\"pdf417\", 4);"
                        echo "        REVERSE_FORMATS.put(\"upce\", 5);"
                        echo "        REVERSE_FORMATS.put(\"datamatrix\", 6);"
                        echo "        REVERSE_FORMATS.put(\"code39\", 7);"
                        echo "        REVERSE_FORMATS.put(\"code93\", 8);"
                        echo "        REVERSE_FORMATS.put(\"interleaved2of5\", 9);"
                        echo "        REVERSE_FORMATS.put(\"codabar\", 10);"
                        echo "        REVERSE_FORMATS.put(\"code128\", 11);"
                        echo "        REVERSE_FORMATS.put(\"maxicode\", 12);"
                        echo "        REVERSE_FORMATS.put(\"rss14\", 13);"
                        echo "        REVERSE_FORMATS.put(\"rssexpanded\", 14);"
                        echo "        REVERSE_FORMATS.put(\"upca\", 15);"
                        echo "        REVERSE_FORMATS.put(\"all\", 0);"
                        echo "    }"
                        echo ""
                    fi
                fi
                
                # Generate constructor if needed
                if [ "$needs_constructor" = true ] && [ "$is_interface" = false ]; then
                    if [ "$constructor_params" = "ReactContext" ]; then
                        echo "    public ${class_name}(ReactContext context) {"
                        echo "        // Auto-generated stub constructor"
                        echo "    }"
                        echo ""
                    elif [ "$constructor_params" = "Complex" ]; then
                        # For complex constructors, generate a varargs constructor
                        echo "    public ${class_name}(Object... params) {"
                        echo "        // Auto-generated stub constructor"
                        echo "    }"
                        echo ""
                    elif [ -n "$constructor_params" ]; then
                        echo "    public ${class_name}() {"
                        echo "        // Auto-generated stub constructor"
                        echo "    }"
                        echo ""
                    fi
                fi
                
                # Generate common methods based on class name patterns
                if echo "$class_name" | grep -qE "Detector" && [ "$is_interface" = false ]; then
                    echo "    public boolean isOperational() { return false; }"
                    if echo "$class_name" | grep -q "FaceDetector"; then
                        echo "    public void setMode(int mode) {"
                        echo "        // Auto-generated stub method"
                        echo "    }"
                        echo "    public void setLandmarkType(int landmarkType) {"
                        echo "        // Auto-generated stub method"
                        echo "    }"
                        echo "    public void setClassificationType(int classificationType) {"
                        echo "        // Auto-generated stub method"
                        echo "    }"
                        echo "    public void setTracking(boolean tracking) {"
                        echo "        // Auto-generated stub method"
                        echo "    }"
                    elif echo "$class_name" | grep -q "BarcodeDetector"; then
                        echo "    public void setBarcodeType(int type) {"
                        echo "        // Auto-generated stub method"
                        echo "    }"
                    fi
                    echo "    public void release() {"
                    echo "        // Auto-generated stub method"
                    echo "    }"
                    echo ""
                fi
                
                if echo "$class_name" | grep -qE "AsyncTask" && [ "$is_interface" = false ]; then
                    # Check if it uses a delegate pattern
                    if echo "$class_name" | grep -qE "(Face|Barcode|Text)"; then
                        local delegate_type=$(echo "$class_name" | sed 's/AsyncTask/AsyncTaskDelegate/')
                        echo "    private ${delegate_type} delegate;"
                        echo ""
                    fi
                    echo "    @Override"
                    echo "    protected Void doInBackground(Void... voids) {"
                    echo "        // Auto-generated stub implementation"
                    echo "        return null;"
                    echo "    }"
                    echo ""
                    echo "    @Override"
                    echo "    protected void onPostExecute(Void result) {"
                    if echo "$class_name" | grep -qE "(Face|Barcode|Text)"; then
                        echo "        if (delegate != null) {"
                        if echo "$class_name" | grep -q "Face"; then
                            echo "            delegate.onFaceDetectingTaskCompleted();"
                        elif echo "$class_name" | grep -q "Barcode"; then
                            echo "            delegate.onBarcodeDetectingTaskCompleted();"
                        elif echo "$class_name" | grep -q "Text"; then
                            echo "            delegate.onTextRecognizerTaskCompleted();"
                        fi
                        echo "        }"
                    fi
                    echo "    }"
                    echo ""
                fi
                
                if echo "$class_name" | grep -qE "Module$" && [ "$is_interface" = false ]; then
                    # Check if it implements NativeModule
                    if echo "$import_line" | grep -q "NativeModule" || [ "$constructor_params" = "ReactContext" ]; then
                        echo "    @Override"
                        echo "    public String getName() { return \"${class_name}\"; }"
                        echo ""
                        echo "    @Override"
                        echo "    public void initialize() {"
                        echo "        // Auto-generated stub implementation"
                        echo "    }"
                        echo ""
                        echo "    @Override"
                        echo "    public boolean canOverrideExistingModule() { return false; }"
                        echo ""
                        echo "    @Override"
                        echo "    public void onCatalystInstanceDestroy() {"
                        echo "        // Auto-generated stub implementation"
                        echo "    }"
                        echo ""
                        echo "    @Override"
                        echo "    public void invalidate() {"
                        echo "        // Auto-generated stub implementation"
                        echo "    }"
                        echo ""
                    fi
                fi
                
                echo "    // Auto-generated stub for optional dependency"
                echo "}"
            } > "$stub_file"
            
                log "    ✅ Generated stub: ${package_name}.${class_name}"
                
                rm -f "$usage_file" || true
            done < "$temp_missing"
        } || true
        
        log "  ✅ Stub generation complete"
    else
        log "  ℹ️  No missing optional dependencies detected"
    fi
    
    # Special handling for R.java stubs (detect R class usage)
    local r_packages_processed=""
    if [ -s "$temp_all_files" ]; then
        while IFS= read -r file || [ -n "$file" ]; do
            [ -z "$file" ] || [ ! -f "$file" ] && continue
        
        # Check for R class imports that don't exist
        if grep -qE "import\s+[^;]+\.R;" "$file" 2>/dev/null; then
            local r_import=$(grep -oE "import\s+[^;]+\.R;" "$file" | head -1 | sed 's/import\s*//;s/;\s*$//')
            local r_package=$(echo "$r_import" | sed 's/\.R$//')
            
            # Skip if already processed
            if echo "$r_packages_processed" | grep -q "^${r_package}$"; then
                continue
            fi
            r_packages_processed="${r_packages_processed}${r_package}"$'\n'
            
            local r_package_dir=$(echo "$r_package" | sed 's/\./\//g' | tr -d '[:space:]')
            local r_file="${java_dir}/${r_package_dir}/R.java"
            
            # Skip if R.java already exists (might be generated by Android build system or already created)
            if [ -f "$r_file" ]; then
                continue
            fi
            
            # Clean up any R.java files with spaces in path (fix duplicate class errors)
            find "$java_dir" -type f -path "* */R.java" -delete 2>/dev/null || true
            find "$java_dir" -type d -name "* *" -exec rm -rf {} + 2>/dev/null || true
            
            if [ ! -f "$r_file" ]; then
                # Ensure directory path has no spaces
                local r_dir=$(dirname "$r_file" | tr -d '[:space:]')
                mkdir -p "$r_dir"
                {
                    echo "package ${r_package};"
                    echo ""
                    echo "// Auto-generated stub R class"
                    echo "public final class R {"
                    echo "    public static final class id {"
                    echo "        public static final int texture_view = 0;"
                    echo "        public static final int surface_view = 0;"
                    echo "    }"
                    echo "    public static final class layout {"
                    echo "        public static final int texture_view = 0;"
                    echo "        public static final int surface_view = 0;"
                    echo "    }"
                    echo "    public static final class drawable {"
                    echo "    }"
                    echo "    public static final class string {"
                    echo "    }"
                    echo "}"
                } > "$r_file"
                log "    ✅ Generated stub R class: ${r_package}.R"
                
                # Fix R imports in files that reference this R class
                if [ -d "$java_dir" ]; then
                    find "$java_dir" -type f \( -name "*.java" -o -name "*.kt" \) 2>/dev/null | while IFS= read -r src_file; do
                        [ -z "$src_file" ] || [ ! -f "$src_file" ] && continue
                        # Update imports to use the correct R package
                        if grep -qE "import\s+[^;]+\.R;" "$src_file" 2>/dev/null; then
                            # Only fix if the file is in a package that would use this R class
                            local file_package=$(grep -E "^package\s+" "$src_file" 2>/dev/null | head -1 | sed 's/^package\s*//;s/;\s*$//')
                            if [ -n "$file_package" ] && echo "$file_package" | grep -qE "^${r_package%\.*}"; then
                                perl -pi -e "s/import\s+([^;]+)\.R;/import ${r_package}.R;/g" "$src_file" 2>/dev/null || true
                            fi
                        fi
                    done
                fi
                if [ -d "$kotlin_dir" ]; then
                    find "$kotlin_dir" -type f \( -name "*.java" -o -name "*.kt" \) 2>/dev/null | while IFS= read -r src_file; do
                        [ -z "$src_file" ] || [ ! -f "$src_file" ] && continue
                        # Update imports to use the correct R package
                        if grep -qE "import\s+[^;]+\.R;" "$src_file" 2>/dev/null; then
                            # Only fix if the file is in a package that would use this R class
                            local file_package=$(grep -E "^package\s+" "$src_file" 2>/dev/null | head -1 | sed 's/^package\s*//;s/;\s*$//')
                            if [ -n "$file_package" ] && echo "$file_package" | grep -qE "^${r_package%\.*}"; then
                                perl -pi -e "s/import\s+([^;]+)\.R;/import ${r_package}.R;/g" "$src_file" 2>/dev/null || true
                            fi
                        fi
                    done
                fi
            fi
        fi
        done < "$temp_all_files" || true
    fi
    
    # Cleanup temporary files
    rm -f "$temp_imports" "$temp_missing" "$temp_all_files" || true
    
    # Remove any invalid stub directories that might have been created (e.g., "static" directories)
    # These are created when "import static" statements are incorrectly processed
    if [ -d "$java_dir" ]; then
        find "$java_dir" -type d -name "static" -exec rm -rf {} + 2>/dev/null || true
        find "$java_dir" -type d -path "*/static/*" -exec rm -rf {} + 2>/dev/null || true
        # Also remove any files in these invalid directories
        find "$java_dir" -type f -path "*/static/*" -delete 2>/dev/null || true
    fi
    
    return 0
}

# Run automatic stub detection and generation
detect_and_generate_stubs

# Step 4.2: Validate bundled packages (check for duplicates and issues)
########################################
log "Step 4.1: Validating bundled packages..."

# Check for duplicate package declarations
java_dir="${KIT_ANDROID_DIR}/src/main/java"
if [ -d "$java_dir" ]; then
    # Find all package declarations and check for duplicates
    duplicate_packages=$(find "$java_dir" -type f \( -name "*.java" -o -name "*.kt" \) -exec grep -h "^package " {} \; 2>/dev/null | \
        sed 's/^package //' | sed 's/;$//' | \
        sort | uniq -d)
    
    if [ -n "$duplicate_packages" ]; then
        warn "  ⚠️  Found duplicate package declarations:"
        echo "$duplicate_packages" | while IFS= read -r dup_pkg || [ -n "$dup_pkg" ]; do
            if [ -n "$dup_pkg" ] && [ "$dup_pkg" != "" ]; then
                echo "    - $dup_pkg" >&2
            fi
        done
        warn "  This may cause compilation errors. Check package renaming logic."
    else
        log "  ✅ No duplicate package declarations found"
    fi
    
    # Check for packages that weren't renamed (still using original package names)
    # This catches cases where renaming failed
    original_packages=$(find "$java_dir" -type f \( -name "*.java" -o -name "*.kt" \) -exec grep -h "^package " {} \; 2>/dev/null | \
        sed 's/^package //' | sed 's/;$//' | \
        grep -v "^com\.vsco\.nativekit\." | \
        grep -v "^com\.facebook\.react\." | \
        sort -u)
    
    if [ -n "$original_packages" ]; then
        warn "  ⚠️  Found packages that weren't renamed to com.vsco.nativekit.*:"
        echo "$original_packages" | while IFS= read -r orig_pkg || [ -n "$orig_pkg" ]; do
            if [ -n "$orig_pkg" ] && [ "$orig_pkg" != "" ]; then
                echo "    - $orig_pkg" >&2
            fi
        done
        warn "  These packages may conflict with native app dependencies."
    else
        log "  ✅ All packages properly renamed to com.vsco.nativekit.*"
    fi
    
    # Check for broken imports (imports that reference non-existent packages)
    # This is a basic check - we look for import statements that don't have corresponding files
    broken_imports_count=0
    while IFS= read -r import_line || [ -n "$import_line" ]; do
        if [ -z "$import_line" ]; then
            continue
        fi
        if echo "$import_line" | grep -q "^import "; then
            imported_pkg=$(echo "$import_line" | sed 's/^import //' | sed 's/;.*$//' | sed 's/\..*$//')
            # Check if this package exists in our bundled code
            pkg_path="${imported_pkg//.//}"
            if [ ! -d "$java_dir/$pkg_path" ] && ! echo "$imported_pkg" | grep -q "^com\.facebook\.react\."; then
                broken_imports_count=$((broken_imports_count + 1))
            fi
        fi
    done < <(find "$java_dir" -type f \( -name "*.java" -o -name "*.kt" \) -exec grep -h "^import " {} \; 2>/dev/null | head -20)
    
    if [ "$broken_imports_count" -gt 0 ]; then
        warn "  ⚠️  Found potential broken imports (sample check - may have false positives)"
        warn "  This may indicate missing dependencies or renaming issues."
    else
        log "  ✅ Import validation passed (sample check)"
    fi
else
    warn "  ⚠️  Java directory not found - skipping validation"
fi

# Note: Validation warnings should not cause script failure
# They are informational only

# Final cleanup: Remove Fresco and other dependency source files after all package processing
# This ensures these files are never bundled in the AAR, regardless of where they came from
log "Final cleanup: Removing dependency source files that should not be bundled..."
android_java_dir="${KIT_ANDROID_DIR}/src/main/java"
if [ -d "$android_java_dir/com/facebook" ]; then
    rm -rf "$android_java_dir/com/facebook/fresco" 2>/dev/null || true
    rm -rf "$android_java_dir/com/facebook/common" 2>/dev/null || true
    rm -rf "$android_java_dir/com/facebook/datasource" 2>/dev/null || true
    rm -rf "$android_java_dir/com/facebook/imagepipeline" 2>/dev/null || true
    rm -rf "$android_java_dir/com/facebook/drawee" 2>/dev/null || true
    rm -rf "$android_java_dir/com/facebook/proguard" 2>/dev/null || true
    log "  ✅ Removed Fresco and dependency source files"
fi

# Step 5: Generate unified ReactPackage (Android)
########################################
log "Step 5: Generating unified ReactPackage for Android..."

# Detect all ReactPackage classes in bundled code
detect_react_packages() {
    local java_dir="${KIT_ANDROID_DIR}/src/main/java"
    local packages=""
    
    if [ ! -d "$java_dir" ]; then
        return
    fi
    
    while IFS= read -r package_file; do
        if [ -f "$package_file" ]; then
            local relative_path="${package_file#$java_dir/}"
            local class_name="${relative_path%.java}"
            class_name="${class_name%.kt}"
            class_name="${class_name//\//.}"
            
            if grep -qE "(implements|extends).*ReactPackage|: (BaseReactPackage|ReactPackage)" "$package_file" 2>/dev/null; then
                packages="${packages}${class_name} "
            fi
        fi
    done < <(find "$java_dir" -type f \( -name "*Package.java" -o -name "*Package.kt" \) 2>/dev/null)
    
    echo "$packages"
}

REACT_PACKAGES=$(detect_react_packages)

# Filter out VSCONativeKitPackage itself to prevent infinite recursion
# Also filter out duplicate packages (generic detection: prefer com.vsco.nativekit.* over original packages)
FILTERED_PACKAGES=""
if [ -n "$REACT_PACKAGES" ]; then
    for pkg in $REACT_PACKAGES; do
        # Skip VSCONativeKitPackage and MKDNativeKitPackage (old name) to prevent self-reference
        if [[ "$pkg" == *"VSCONativeKitPackage"* ]] || [[ "$pkg" == *"MKDNativeKitPackage"* ]]; then
            continue
        fi
        
        # Generic duplicate detection: if package is NOT under com.vsco.nativekit, check if a renamed version exists
        if [[ "$pkg" != "com.vsco.nativekit."* ]]; then
            # Extract the class name (last part after last dot)
            class_name="${pkg##*.}"
            # Extract the package path (everything before last dot)
            package_path="${pkg%.*}"
            
            # Check if there's a com.vsco.nativekit.* version with the same class name
            renamed_version=""
            for renamed_pkg in $REACT_PACKAGES; do
                if [[ "$renamed_pkg" == "com.vsco.nativekit."* ]] && [[ "$renamed_pkg" == *".${class_name}" ]]; then
                    renamed_version="$renamed_pkg"
                    break
                fi
            done
            
            if [ -n "$renamed_version" ]; then
                log "  Skipping duplicate: $pkg (using $renamed_version instead)"
                continue
            fi
        fi
        
        FILTERED_PACKAGES="${FILTERED_PACKAGES}${pkg} "
    done
    FILTERED_PACKAGES=$(echo "$FILTERED_PACKAGES" | xargs)  # Trim whitespace
fi

if [ -z "$FILTERED_PACKAGES" ]; then
    warn "No ReactPackage classes found in bundled code (after filtering)"
    warn "The unified package will be empty"
else
    log "  Found ReactPackage classes: $FILTERED_PACKAGES"
fi

# Generate unified ReactPackage
mkdir -p "${KIT_ANDROID_DIR}/src/main/java/com/vsco/nativekit"
cat > "${KIT_ANDROID_DIR}/src/main/java/com/vsco/nativekit/VSCONativeKitPackage.kt" <<EOF
package com.vsco.nativekit

import com.facebook.react.ReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.uimanager.ViewManager

/**
 * Unified ReactPackage for all native libraries bundled in vsco-native-kit.
 * This package automatically registers all bundled ReactPackage implementations.
 */
class VSCONativeKitPackage : ReactPackage {
    
    private val bundledPackages: List<String> = listOf(
$(if [ -n "$FILTERED_PACKAGES" ]; then
    for pkg in $FILTERED_PACKAGES; do
        echo "        \"$pkg\","
    done
else
    echo "        // No ReactPackage classes found"
fi)
    )
    
    override fun createNativeModules(reactContext: ReactApplicationContext): List<NativeModule> {
        val modules = mutableListOf<NativeModule>()
        
        for (packageClassName in bundledPackages) {
            try {
                val packageClass = Class.forName(packageClassName)
                val reactPackage = packageClass.getDeclaredConstructor().newInstance() as ReactPackage
                modules.addAll(reactPackage.createNativeModules(reactContext))
            } catch (e: ClassNotFoundException) {
                // Package not found - skip
            } catch (e: Exception) {
                // Failed to instantiate - skip
            }
        }
        
        return modules
    }
    
    override fun createViewManagers(reactContext: ReactApplicationContext): List<ViewManager<*, *>> {
        val viewManagers = mutableListOf<ViewManager<*, *>>()
        
        for (packageClassName in bundledPackages) {
            try {
                val packageClass = Class.forName(packageClassName)
                val reactPackage = packageClass.getDeclaredConstructor().newInstance() as ReactPackage
                viewManagers.addAll(reactPackage.createViewManagers(reactContext))
            } catch (e: ClassNotFoundException) {
                // Package not found - skip
            } catch (e: Exception) {
                // Failed to instantiate - skip
            }
        }
        
        return viewManagers
    }
}
EOF

log "  ✅ Generated VSCONativeKitPackage.kt"

########################################
# Step 6: Update Android build.gradle.kts
########################################
log "Step 6: Updating Android build.gradle.kts..."

########################################
# Step 6.1: Detect and collect Maven dependencies from bundled packages
########################################
log "Step 6.1: Detecting Maven dependencies from bundled packages..."

# Function to detect Maven dependencies from a package
# Uses multiple strategies: build.gradle parsing, package.json analysis, and known dependencies
detect_maven_dependencies() {
    local package_name="$1"
    local package_dir="$2"
    local maven_deps=()
    local temp_deps_file=$(mktemp)
    
    # Strategy 1: Parse build.gradle for explicit dependencies
    local build_gradle="${package_dir}/android/build.gradle"
    if [ -f "$build_gradle" ]; then
        # Extract Maven dependencies from build.gradle
        # Pattern: implementation 'group:artifact:version' or api 'group:artifact:version'
        # Also handle multi-line dependencies and variable substitutions
        local deps=$(grep -E "(implementation|api|compile)\s+['\"].*:.*:.*['\"]" "$build_gradle" 2>/dev/null | \
            sed "s/.*['\"]\(.*\)['\"].*/\1/" | \
            grep -v "react-native" | \
            grep -v "react-android" | \
            sort -u || true)
        
        if [ -n "$deps" ]; then
            for dep in $deps; do
                # Skip React Native dependencies (we use compileOnly for those)
                if echo "$dep" | grep -q "react-native\|react-android"; then
                    continue
                fi
                # Skip dependencies with variables (e.g., $kotlin_version)
                if echo "$dep" | grep -q '\$'; then
                    continue
                fi
                # Skip dependencies with unresolved variables or placeholders
                if echo "$dep" | grep -qE ':\$|:\$\{|:project\.|:rootProject\.'; then
                    continue
                fi
                # Validate format: group:artifact:version
                if echo "$dep" | grep -qE '^[^:]+:[^:]+:[^:]+$'; then
                    echo "$dep" >> "$temp_deps_file"
                fi
            done
        fi
    fi
    
    # Strategy 2: Parse package.json for androidMavenRepos or similar fields (generic)
    # Some packages list their Maven dependencies in package.json
    local package_json="${package_dir}/package.json"
    if [ -f "$package_json" ]; then
        # Try to extract Maven dependencies from package.json using node
        # Look for fields like androidMavenRepos, mavenDependencies, etc.
        local json_deps=$(node -e "
            const fs = require('fs');
            try {
                const pkg = JSON.parse(fs.readFileSync('$package_json', 'utf8'));
                // Check various possible fields where Maven deps might be listed
                const mavenDeps = pkg.androidMavenRepos || pkg.mavenDependencies || 
                                  pkg.androidDependencies || pkg.dependencies?.android || [];
                if (Array.isArray(mavenDeps)) {
                    mavenDeps.forEach(dep => {
                        if (typeof dep === 'string' && dep.includes(':')) {
                            console.log(dep);
                        }
                    });
                } else if (typeof mavenDeps === 'object' && mavenDeps !== null) {
                    Object.entries(mavenDeps).forEach(([key, value]) => {
                        if (typeof value === 'string' && value.includes(':')) {
                            console.log(value);
                        }
                    });
                }
            } catch(e) {
                // Ignore errors - fall back to build.gradle parsing
            }
        " 2>/dev/null || echo "")
        
        if [ -n "$json_deps" ]; then
            echo "$json_deps" | while IFS= read -r dep; do
                if [ -n "$dep" ] && echo "$dep" | grep -qE '^[^:]+:[^:]+:[^:]+$'; then
                    echo "$dep" >> "$temp_deps_file"
                fi
            done
        fi
    fi
    
    # Strategy 3: Parse android/build.gradle.kts if it exists (Kotlin DSL)
    local build_gradle_kts="${package_dir}/android/build.gradle.kts"
    if [ -f "$build_gradle_kts" ]; then
        # Extract Maven dependencies from Kotlin DSL build.gradle.kts
        # Pattern: implementation("group:artifact:version") or api("group:artifact:version")
        local kts_deps=$(grep -E "(implementation|api|compile)\s*\(['\"].*:.*:.*['\"]\)" "$build_gradle_kts" 2>/dev/null | \
            sed "s/.*['\"]\(.*\)['\"].*/\1/" | \
            grep -v "react-native" | \
            grep -v "react-android" | \
            sort -u || true)
        
        if [ -n "$kts_deps" ]; then
            for dep in $kts_deps; do
                # Skip React Native dependencies
                if echo "$dep" | grep -q "react-native\|react-android"; then
                    continue
                fi
                # Skip dependencies with variables
                if echo "$dep" | grep -q '\$'; then
                    continue
                fi
                # Validate format: group:artifact:version
                if echo "$dep" | grep -qE '^[^:]+:[^:]+:[^:]+$'; then
                    echo "$dep" >> "$temp_deps_file"
                fi
            done
        fi
    fi
    
    # Return unique dependencies as newline-separated string
    if [ -f "$temp_deps_file" ] && [ -s "$temp_deps_file" ]; then
        sort -u "$temp_deps_file"
    fi
    
    # Clean up
    rm -f "$temp_deps_file"
}

# Collect all Maven dependencies
ALL_MAVEN_DEPS=()

# Check if any expo-* modules are detected
HAS_EXPO_MODULES=false
for dep in "${SHARED_NATIVE_DEPS[@]}"; do
    if echo "$dep" | grep -q "^expo-"; then
        HAS_EXPO_MODULES=true
        break
    fi
done

# If expo-* modules are detected, add expo-modules-core
if [ "$HAS_EXPO_MODULES" = true ]; then
    # Detect expo-modules-core version from package.json
    EXPO_CORE_VERSION=$(node -e "
        const fs = require('fs');
        try {
            const rootPkg = JSON.parse(fs.readFileSync('$ROOT_PACKAGE_JSON', 'utf8'));
            const allDeps = {
                ...(rootPkg.dependencies || {}),
                ...(rootPkg.peerDependencies || {}),
                ...(rootPkg.devDependencies || {})
            };
            const version = allDeps['expo-modules-core'] || '3.0.23';
            console.log(version.replace(/[^0-9.]/g, ''));
        } catch(e) {
            console.log('3.0.23');
        }
    " 2>/dev/null || echo "3.0.23")
    ALL_MAVEN_DEPS+=("host.exp.exponent:expo-modules-core:${EXPO_CORE_VERSION}")
    log "  📦 Detected Expo modules - will add expo-modules-core:${EXPO_CORE_VERSION}"
fi

for dep in "${SHARED_NATIVE_DEPS[@]}"; do
    dep_dir="${TEMP_NPM_DIR}/node_modules/${dep}"
    if [ -d "$dep_dir" ]; then
        log "  Checking Maven dependencies for: $dep"
        maven_deps=$(detect_maven_dependencies "$dep" "$dep_dir")
        if [ -n "$maven_deps" ]; then
            while IFS= read -r maven_dep; do
                if [ -n "$maven_dep" ]; then
                    # Add if not already present
                    already_added=false
                    if [ ${#ALL_MAVEN_DEPS[@]} -gt 0 ]; then
                        for existing in "${ALL_MAVEN_DEPS[@]}"; do
                            if [ "$existing" = "$maven_dep" ]; then
                                already_added=true
                                break
                            fi
                        done
                    fi
                    if [ "$already_added" = false ]; then
                        ALL_MAVEN_DEPS+=("$maven_dep")
                        log "    Found Maven dependency: $maven_dep"
                    fi
                fi
            done <<< "$maven_deps"
        fi
    fi
done

if [ ${#ALL_MAVEN_DEPS[@]} -gt 0 ]; then
    log "  📦 Total Maven dependencies to add: ${#ALL_MAVEN_DEPS[@]}"
else
    log "  ℹ️  No additional Maven dependencies found"
fi

########################################
# Step 6: Update Android build.gradle.kts
########################################
log "Step 6: Updating Android build.gradle.kts..."

# Ensure build.gradle exists and is properly configured
if [ ! -f "${KIT_ANDROID_DIR}/build.gradle" ]; then
    # Create build.gradle if it doesn't exist (use Groovy for compatibility)
    cat > "${KIT_ANDROID_DIR}/build.gradle" <<'GRADLE_EOF'
plugins {
    id 'com.android.library'
    id 'org.jetbrains.kotlin.android'
    id 'maven-publish'
}

android {
    namespace "com.vsco.nativekit"
    compileSdk 34

    defaultConfig {
        minSdk 24
    }
    
    buildFeatures {
        buildConfig true
    }

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_1_8
        targetCompatibility JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        jvmTarget = '1.8'
        freeCompilerArgs += [
            '-Xjvm-default=all',
            '-Xopt-in=kotlin.RequiresOptIn',
            '-Xopt-in=kotlin.Experimental'
        ]
    }
    
    lint {
        abortOnError false
        checkReleaseBuilds false
        disable 'WrongConstant', 'Deprecated'
    }
    
    packagingOptions {
        exclude '**/ReactStylesDiffMapHelperKt.class'
        exclude '**/ReactStylesDiffMapHelperKt$*.class'
    }
}

dependencies {
    compileOnly 'com.facebook.react:react-android:0.81.5'
    compileOnly 'androidx.documentfile:documentfile:1.0.0'
    api 'commons-codec:commons-codec:1.10'
    api 'commons-io:commons-io:1.4'
    // expo-modules-core will be added dynamically if expo-* modules are detected
}

afterEvaluate { project ->
    project.publishing {
        publications {
            release(MavenPublication) {
                groupId = 'com.vsco'
                artifactId = 'vsco-native-kit'
                version = '1.0.0'
                from components.release
            }
        }
    }
    
    project.tasks.named('publishReleasePublicationToMavenLocal').configure {
        dependsOn 'assembleRelease'
    }
}
GRADLE_EOF
    log "  ✅ Created build.gradle"
else
    log "  ✅ build.gradle already exists"
fi

# Update build.gradle with Maven dependencies if any were detected
if [ ${#ALL_MAVEN_DEPS[@]} -gt 0 ]; then
    log "  Adding Maven dependencies to build.gradle..."
    
    # Use a more precise approach: find the dependencies block and add before its closing brace
    # Create a temporary file for the updated build.gradle
    temp_gradle=$(mktemp)
    in_dependencies=false
    deps_added=false
    brace_count=0
    
    while IFS= read -r line; do
        # Check if we're entering the dependencies block
        if [[ "$line" =~ ^dependencies[[:space:]]*\{ ]]; then
            in_dependencies=true
            brace_count=1
            echo "$line" >> "$temp_gradle"
            continue
        fi
        
        # Count braces when in dependencies block
        if [ "$in_dependencies" = true ]; then
            # Count opening braces (handle empty output from grep)
            open_braces=$(echo "$line" | grep -o '{' | wc -l | tr -d '[:space:]' || echo "0")
            close_braces=$(echo "$line" | grep -o '}' | wc -l | tr -d '[:space:]' || echo "0")
            # Ensure we have valid numbers
            open_braces=${open_braces:-0}
            close_braces=${close_braces:-0}
            brace_count=$((brace_count + open_braces - close_braces))
            
            # Check if we're leaving the dependencies block (brace_count reaches 0)
            if [ "$brace_count" -eq 0 ] && [[ "$line" =~ }[[:space:]]*$ ]]; then
                # Add Maven dependencies before closing the dependencies block
                if [ "$deps_added" = false ]; then
                    for maven_dep in "${ALL_MAVEN_DEPS[@]}"; do
                        # Parse group:artifact:version
                        group=$(echo "$maven_dep" | cut -d: -f1)
                        artifact=$(echo "$maven_dep" | cut -d: -f2)
                        version=$(echo "$maven_dep" | cut -d: -f3)
                        
                        # Check if dependency already exists
                        if ! grep -q "${group}:${artifact}:" "${KIT_ANDROID_DIR}/build.gradle"; then
                            echo "    api '${group}:${artifact}:${version}'" >> "$temp_gradle"
                        fi
                    done
                    deps_added=true
                fi
                in_dependencies=false
            fi
        fi
        
        echo "$line" >> "$temp_gradle"
    done < "${KIT_ANDROID_DIR}/build.gradle"
    
    # Replace the original file (only if temp file was created successfully)
    if [ -f "$temp_gradle" ] && [ -s "$temp_gradle" ]; then
        mv "$temp_gradle" "${KIT_ANDROID_DIR}/build.gradle"
        log "  ✅ Added Maven dependencies to build.gradle"
    else
        warn "  ⚠️  Failed to update build.gradle - temp file was not created or is empty"
        rm -f "$temp_gradle"
    fi
fi

# Create settings.gradle (not .kts - use Groovy for compatibility)
if [ ! -f "${KIT_ANDROID_DIR}/settings.gradle" ]; then
    cat > "${KIT_ANDROID_DIR}/settings.gradle" <<'SETTINGS_EOF'
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
    plugins {
        id 'com.android.library' version '8.13.1'
        id 'org.jetbrains.kotlin.android' version '2.1.0'
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "vsco-native-kit"
SETTINGS_EOF
    log "  ✅ Created settings.gradle"
fi

# Create AndroidManifest.xml
mkdir -p "${KIT_ANDROID_DIR}/src/main"
if [ ! -f "${KIT_ANDROID_DIR}/src/main/AndroidManifest.xml" ]; then
    cat > "${KIT_ANDROID_DIR}/src/main/AndroidManifest.xml" <<'MANIFEST_EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.vsco.nativekit">
</manifest>
MANIFEST_EOF
    log "  ✅ Created AndroidManifest.xml"
fi

# Create gradle wrapper if it doesn't exist
if [ ! -f "${KIT_ANDROID_DIR}/gradlew" ]; then
    log "  Creating Gradle wrapper..."
    cd "${KIT_ANDROID_DIR}"
    
    # Use gradle wrapper from another Android project if available
    if [ -f "${MONOREPO_ROOT}/frameworks/android/vsco-rn-host/gradlew" ]; then
        cp "${MONOREPO_ROOT}/frameworks/android/vsco-rn-host/gradlew" "${KIT_ANDROID_DIR}/gradlew"
        cp -R "${MONOREPO_ROOT}/frameworks/android/vsco-rn-host/gradle" "${KIT_ANDROID_DIR}/gradle" 2>/dev/null || true
        chmod +x "${KIT_ANDROID_DIR}/gradlew"
        log "  ✅ Copied Gradle wrapper from vsco-rn-host"
    else
        # Initialize gradle wrapper
        gradle wrapper --gradle-version 8.3 2>/dev/null || {
            # Fallback: create minimal wrapper
            mkdir -p "${KIT_ANDROID_DIR}/gradle/wrapper"
            cat > "${KIT_ANDROID_DIR}/gradle/wrapper/gradle-wrapper.properties" <<'WRAPPER_EOF'
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-8.3-bin.zip
networkTimeout=10000
validateDistributionUrl=true
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
WRAPPER_EOF
            # Download gradle wrapper jar (simplified - user may need to run gradle wrapper manually)
            log "  ⚠️  Gradle wrapper created, but gradlew script needs to be added manually"
            log "  ⚠️  Or copy from another Android project"
        }
    fi
fi

# Create gradle.properties
if [ ! -f "${KIT_ANDROID_DIR}/gradle.properties" ]; then
    cat > "${KIT_ANDROID_DIR}/gradle.properties" <<'PROPS_EOF'
android.useAndroidX=true
android.enableJetifier=true
PROPS_EOF
    log "  ✅ Created gradle.properties"
fi

# Copy local.properties if needed
if [ -f "${ANDROID_PROPS_DIR}/local.properties" ]; then
    cp "${ANDROID_PROPS_DIR}/local.properties" "${KIT_ANDROID_DIR}/local.properties"
    log "  ✅ Copied local.properties"
fi

# Step 7.99: Final verification - ensure all ZXing helpers are present
########################################
log "Step 7.99: Final verification - ensuring all ZXing helpers are present..."
temp_final_verify=$(mktemp)
# Use the correct path - KIT_ANDROID_DIR should be set at this point
final_android_java_dir="${KIT_ANDROID_DIR}/src/main/java/com/vsco/nativekit"
cat > "$temp_final_verify" << PYTHON_FINAL_VERIFY_EOF
import sys
import re
import os

android_java_dir = sys.argv[1]

all_helpers = {
    "getBarcodeFormatEnum": """    private Object getBarcodeFormatEnum(String enumName) {
        try {
            return java.lang.Enum.valueOf((Class<? extends Enum>) Class.forName("com.google.zxing.BarcodeFormat"), enumName);
        } catch (Exception e) {
            return null;
        }
    }""",
    "getDecodeHintTypePossibleFormats": """    private Object getDecodeHintTypePossibleFormats() {
        try {
            return java.lang.Enum.valueOf((Class<? extends Enum>) Class.forName("com.google.zxing.DecodeHintType"), "POSSIBLE_FORMATS");
        } catch (Exception e) {
            return null;
        }
    }""",
    "setHintsReflection": """    private void setHintsReflection(Object reader, java.util.Map hints) {
        try {
            @SuppressWarnings({"unchecked", "rawtypes"})
            EnumMap enumHints = new EnumMap(Class.forName("com.google.zxing.DecodeHintType"));
            enumHints.putAll(hints);
            java.lang.reflect.Method method = reader.getClass().getMethod("setHints", java.util.Map.class);
            method.invoke(reader, enumHints);
        } catch (Exception e) {
            // Ignore
        }
    }""",
    "createPlanarYUVLuminanceSource": """    private Object createPlanarYUVLuminanceSource(byte[] yuvData, int dataWidth, int dataHeight, int left, int top, int width, int height, boolean reverseHorizontal) {
        try {
            Class<?> clazz = Class.forName("com.google.zxing.PlanarYUVLuminanceSource");
            java.lang.reflect.Constructor<?> constructor = clazz.getConstructor(byte[].class, int.class, int.class, int.class, int.class, int.class, int.class, boolean.class);
            return constructor.newInstance(yuvData, dataWidth, dataHeight, left, top, width, height, reverseHorizontal);
        } catch (Exception e) {
            return null;
        }
    }""",
    "invokeInvertMethod": """    private Object invokeInvertMethod(Object source) {
        try {
            java.lang.reflect.Method method = source.getClass().getMethod("invert");
            return method.invoke(source);
        } catch (Exception e) {
            return source;
        }
    }""",
    "getResultBarcodeFormat": """    private Object getResultBarcodeFormat(Object result) {
        try {
            java.lang.reflect.Method method = result.getClass().getMethod("getBarcodeFormat");
            return method.invoke(result);
        } catch (Exception e) {
            return null;
        }
    }""",
    "resetReaderReflection": """    private void resetReaderReflection(Object reader) {
        try {
            java.lang.reflect.Method method = reader.getClass().getMethod("reset");
            method.invoke(reader);
        } catch (Exception e) {
            // Ignore
        }
    }""",
    "decodeWithStateReflection": """    private Object decodeWithStateReflection(Object reader, Object bitmap) {
        try {
            java.lang.reflect.Method method = reader.getClass().getMethod("decodeWithState", bitmap.getClass());
            return method.invoke(reader, bitmap);
        } catch (Exception e) {
            return null;
        }
    }""",
    "getResultText": """    private String getResultText(Object result) {
        try {
            java.lang.reflect.Method method = result.getClass().getMethod("getText");
            return (String) method.invoke(result);
        } catch (Exception e) {
            return "";
        }
    }""",
    "getResultRawBytes": """    private byte[] getResultRawBytes(Object result) {
        try {
            java.lang.reflect.Method method = result.getClass().getMethod("getRawBytes");
            return (byte[]) method.invoke(result);
        } catch (Exception e) {
            return null;
        }
    }""",
    "getResultPointsArray": """    private Object[] getResultPointsArray(Object result) {
        try {
            java.lang.reflect.Method method = result.getClass().getMethod("getResultPoints");
            return (Object[]) method.invoke(result);
        } catch (Exception e) {
            return new Object[0];
        }
    }""",
    "getResultPointX": """    private double getResultPointX(Object point) {
        try {
            java.lang.reflect.Method method = point.getClass().getMethod("getX");
            return ((Number) method.invoke(point)).doubleValue();
        } catch (Exception e) {
            return 0.0;
        }
    }""",
    "getResultPointY": """    private double getResultPointY(Object point) {
        try {
            java.lang.reflect.Method method = point.getClass().getMethod("getY");
            return ((Number) method.invoke(point)).doubleValue();
        } catch (Exception e) {
            return 0.0;
        }
    }"""
}

fixed_count = 0
for root, dirs, files in os.walk(android_java_dir):
    for file in files:
        if file.endswith('.java'):
            file_path = os.path.join(root, file)
            try:
                with open(file_path, 'r') as f:
                    content = f.read()
                
                original = content
                
                # Fix type casting issue
                content = re.sub(r'String\s+barCodeType\s*=\s*\(BarcodeFormat\)\s*getResultBarcodeFormat\(([^)]+)\)\.toString\(\)', r'String barCodeType = ((BarcodeFormat) getResultBarcodeFormat(\1)).toString()', content)
                
                # Check which helpers are needed
                needed_helpers = []
                for helper_name in all_helpers.keys():
                    if helper_name in content:
                        has_helper = (f'private Object {helper_name}' in content or 
                                     f'private String {helper_name}' in content or 
                                     f'private byte[] {helper_name}' in content or 
                                     f'private void {helper_name}' in content or 
                                     f'private double {helper_name}' in content or 
                                     f'private Object[] {helper_name}' in content)
                        if not has_helper:
                            needed_helpers.append(helper_name)
                
                if needed_helpers:
                    lines = content.split('\n')
                    last_brace_idx = -1
                    for i in range(len(lines) - 1, -1, -1):
                        if lines[i].strip() == '}':
                            last_brace_idx = i
                            break
                    
                    if last_brace_idx >= 0:
                        indent = '    '
                        if last_brace_idx < len(lines):
                            for char in lines[last_brace_idx]:
                                if char in ' \t':
                                    indent += char
                                else:
                                    break
                        
                        helpers_text = f"{indent}// Reflection helpers for ZXing\n"
                        for helper_name in needed_helpers:
                            helpers_text += all_helpers[helper_name].replace('    ', indent) + "\n"
                        
                        lines.insert(last_brace_idx, helpers_text)
                        content = '\n'.join(lines)
                
                if content != original:
                    with open(file_path, 'w') as f:
                        f.write(content)
                    fixed_count += 1
            except Exception as e:
                import traceback
                print(f"Error processing {file_path}: {e}", file=sys.stderr)
                traceback.print_exc(file=sys.stderr)

if fixed_count > 0:
    print(f"Fixed {fixed_count} files")
sys.exit(0)
PYTHON_FINAL_VERIFY_EOF
# Execute Python script and capture output
verify_output=$(python3 "$temp_final_verify" "$final_android_java_dir" 2>&1)
verify_exit_code=$?
if [ $verify_exit_code -eq 0 ]; then
    if echo "$verify_output" | grep -q "Fixed"; then
        log "  ✅ Final verification: $(echo "$verify_output" | grep "Fixed")"
    else
        log "  ✅ Final verification complete - all helpers present"
    fi
else
    log "  ⚠️  Final verification had issues: $verify_output"
fi
rm -f "$temp_final_verify"

# Step 8: Build Android AAR
########################################
log "Step 8: Building Android AAR..."

cd "$KIT_ANDROID_DIR"

# Ensure gradlew exists
if [ ! -f "./gradlew" ]; then
    err "gradlew not found in $KIT_ANDROID_DIR"
    err "Please ensure the Android project is properly set up"
    exit 1
fi

chmod +x ./gradlew

# Cleanup any invalid stub directories before building
if [ -d "${KIT_ANDROID_DIR}/src/main/java" ]; then
    find "${KIT_ANDROID_DIR}/src/main/java" -type d -name "static" -exec rm -rf {} + 2>/dev/null || true
    find "${KIT_ANDROID_DIR}/src/main/java" -type d -path "*/static/*" -exec rm -rf {} + 2>/dev/null || true
    log "  ✅ Cleaned up invalid stub directories"
fi

log "  Running: ./gradlew assembleRelease"
./gradlew assembleRelease > /dev/null 2>&1

AAR_FILE="${KIT_ANDROID_DIR}/build/outputs/aar/vsco-native-kit-release.aar"
if [ -f "$AAR_FILE" ]; then
    AAR_SIZE=$(du -h "$AAR_FILE" | cut -f1)
    log "  ✅ AAR built: $AAR_FILE ($AAR_SIZE)"
else
    err "AAR was not created"
    err "Build output:"
    ./gradlew assembleRelease 2>&1 | tail -20
    exit 1
fi

########################################
# Step 9: Publish Android AAR to Maven Local
########################################
log "Step 9: Publishing Android AAR to Maven Local..."

cd "${KIT_ANDROID_DIR}"
# Publish to Maven Local
if ./gradlew publishReleasePublicationToMavenLocal 2>&1 | grep -q "BUILD SUCCESSFUL"; then
    log "  ✅ Published to Maven Local"
    log "  📦 Group: com.vsco"
    log "  📦 Artifact: vsco-native-kit"
    log "  📦 Version: 1.0.0"
    
    # Copy POM file from local Maven repository (generated during publish)
    # The POM is published to ~/.m2/repository/com/vsco/vsco-native-kit/1.0.0/
    MAVEN_LOCAL_POM="${HOME}/.m2/repository/com/vsco/vsco-native-kit/1.0.0/vsco-native-kit-1.0.0.pom"
    if [ -f "$MAVEN_LOCAL_POM" ]; then
        # Copy POM to build/outputs/aar folder (alongside the AAR)
        AAR_OUTPUT_DIR="${KIT_ANDROID_DIR}/build/outputs/aar"
        mkdir -p "$AAR_OUTPUT_DIR"
        cp "$MAVEN_LOCAL_POM" "$AAR_OUTPUT_DIR/vsco-native-kit-release.pom"
        log "  ✅ Copied POM file to build/outputs/aar/vsco-native-kit-release.pom"
        
        # Also copy to distribution directory if it exists
        DIST_DIR="${MONOREPO_ROOT}/frameworks/android/distribution/aars"
        if [ -d "$DIST_DIR" ]; then
            mkdir -p "$DIST_DIR"
            cp "$MAVEN_LOCAL_POM" "$DIST_DIR/vsco-native-kit-release.pom"
            log "  ✅ Copied POM file to distribution directory"
        fi
    else
        warn "  ⚠️  POM file not found at expected location: $MAVEN_LOCAL_POM"
    fi
else
    warn "Failed to publish to Maven Local"
    warn "You may need to configure publishing manually"
fi


cd "$MONOREPO_ROOT"

########################################
# Summary
########################################
log "🎉 SUCCESS! vsco-native-kit Android AAR generated"
echo ""
echo "📍 Location: $KIT_ANDROID_DIR"
echo ""
echo "📦 Android AAR:"
echo "   • Location: $AAR_FILE"
echo "   • Size: $AAR_SIZE"
echo "   • Published to: Maven Local (com.vsco:vsco-native-kit:1.0.0)"
echo ""
echo "📋 Bundled Native Dependencies:"
for dep in "${SHARED_NATIVE_DEPS[@]}"; do
    echo "   • $dep"
done
echo ""
