#!/usr/bin/env bash
set -eo pipefail
# Note: 'u' flag removed to allow unbound variables in some edge cases
# We'll handle unbound variables explicitly where needed

########################################
# Native Kit Generator
#
# Generates vsco-native-kit AAR (Android) and SPM (iOS) from native dependencies
# detected in modules published to Verdaccio.
#
# Usage:
#   ./scripts/generate-native-kit.sh
#
# Workflow:
#   1. Install all modules from Verdaccio
#   2. Detect shared native dependencies from all modules
#   3. Install native packages from npm registry
#   4. Bundle native code into vsco-native-kit
#   5. Generate unified ReactPackage (Android) and SPM structure (iOS)
#   6. Build Android AAR and iOS SPM
#   7. Publish Android AAR to Maven Local
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

# Ensure kit directory exists
mkdir -p "$KIT_DIR"
mkdir -p "$KIT_ANDROID_DIR"
mkdir -p "$KIT_IOS_PACKAGE_DIR"

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
# Step 4: Bundle native code to vsco-native-kit
########################################
log "Step 4: Bundling native code to vsco-native-kit..."

# Function to bundle native dependency (reused from generate-module-framework-aar.sh)
bundle_native_to_kit() {
    local package_name="$1"
    local package_source="$2"
    
    log "  Bundling $package_name..."
    
    # Verify native code exists
    local has_android=false
    local has_ios=false
    
    if [ -d "${package_source}/android/src/main/java" ] || \
       [ -d "${package_source}/android/src/main/kotlin" ] || \
       [ -d "${package_source}/android/src/paper/java" ]; then
        has_android=true
    fi
    
    if [ -d "${package_source}/ios" ] || [ -d "${package_source}/apple" ]; then
        has_ios=true
    fi
    
    if [ "$has_android" = false ] && [ "$has_ios" = false ]; then
        warn "    $package_name has no native code - skipping"
        return 1
    fi
    
    # Bundle Android native code
    if [ "$has_android" = true ]; then
        local android_java_dir="${KIT_ANDROID_DIR}/src/main/java"
        local android_src="${package_source}/android/src/main/java"
        local android_kotlin="${package_source}/android/src/main/kotlin"
        local android_paper="${package_source}/android/src/paper/java"
        local android_res="${package_source}/android/src/main/res"
        
        # Create temp directory for processing
        local temp_copy_dir=$(mktemp -d)
        mkdir -p "$temp_copy_dir"
        
        # Copy ALL Java/Kotlin source to temp (including all packages like com.lwansbrough.*)
        if [ -d "$android_src" ]; then
            cp -R "$android_src"/* "$temp_copy_dir/" 2>/dev/null || true
        fi
        
        # Copy Kotlin source to temp
        if [ -d "$android_kotlin" ]; then
            cp -R "$android_kotlin"/* "$temp_copy_dir/" 2>/dev/null || true
        fi
        
        # Copy paper source (codegen types) to temp
        if [ -d "$android_paper" ]; then
            cp -R "$android_paper"/* "$temp_copy_dir/" 2>/dev/null || true
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
        find "$temp_copy_dir" -type f \( -name "*.java" -o -name "*.kt" \) | while read -r file; do
            if [ ! -f "$file" ]; then
                continue
            fi
            
            # Get the package declaration from the file
            local file_pkg=$(grep -m 1 "^package " "$file" 2>/dev/null | sed 's/^package //' | sed 's/;$//' | xargs)
            
            if [ -z "$file_pkg" ]; then
                continue
            fi
            
            # Skip React Native codegen packages
            if echo "$file_pkg" | grep -q "^com\.facebook\.react\."; then
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
        if [ -d "$temp_copy_dir/com/facebook" ]; then
            mkdir -p "$android_java_dir/com/facebook"
            cp -R "$temp_copy_dir/com/facebook"/* "$android_java_dir/com/facebook/" 2>/dev/null || true
        fi
        
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
        
        # Fix BuildConfig references in Kotlin files
        find "$android_java_dir" -name "*.kt" -type f -exec perl -pi -e 's/\bBuildConfig\./com.facebook.react.BuildConfig./g' {} \; 2>/dev/null || true
        find "$android_java_dir" -name "*.kt" -type f -exec perl -pi -e 's/com\.facebook\.react\.BuildConfig\.IS_NEW_ARCHITECTURE_ENABLED/false/g' {} \; 2>/dev/null || true
        
        # Clean up temp directory
        rm -rf "$temp_copy_dir"
        
        # Copy resources
        if [ -d "$android_res" ]; then
            local res_dir="${KIT_ANDROID_DIR}/src/main/res"
            log "    Copying Android resources..."
            mkdir -p "$res_dir"
            cp -R "$android_res"/* "$res_dir/" 2>/dev/null || true
        fi
        
        # Create stub classes for optional dependencies (react-native-camera)
        if [ "$package_name" = "react-native-camera" ]; then
            log "    Creating stub classes for optional dependencies..."
            
            # Create stub for face detector
            mkdir -p "${KIT_ANDROID_DIR}/src/main/java/org/reactnative/facedetector"
            cat > "${KIT_ANDROID_DIR}/src/main/java/org/reactnative/facedetector/RNFaceDetector.java" <<'STUB_EOF'
package org.reactnative.facedetector;

import com.facebook.react.bridge.ReactContext;

public class RNFaceDetector {
    public static final int FAST_MODE = 1;
    public static final int ACCURATE_MODE = 2;
    public static final int NO_LANDMARKS = 1;
    public static final int ALL_LANDMARKS = 2;
    public static final int NO_CLASSIFICATIONS = 1;
    public static final int ALL_CLASSIFICATIONS = 2;
    
    public RNFaceDetector(ReactContext context) {
        // Stub constructor
    }
    
    public boolean isOperational() { return false; }
    public void setMode(int mode) {
        // Stub implementation
    }
    public void setLandmarkType(int landmarkType) {
        // Stub implementation
    }
    public void setClassificationType(int classificationType) {
        // Stub implementation
    }
    public void setTracking(boolean tracking) {
        // Stub implementation
    }
    public void release() {
        // Stub implementation
    }
    // Stub for optional face detector dependency
}
STUB_EOF
            
            cat > "${KIT_ANDROID_DIR}/src/main/java/org/reactnative/facedetector/FaceDetectorModule.java" <<'STUB_EOF'
package org.reactnative.facedetector;

import com.facebook.react.bridge.NativeModule;
import com.facebook.react.bridge.ReactApplicationContext;

public class FaceDetectorModule implements NativeModule {
    public FaceDetectorModule(ReactApplicationContext reactContext) {
        // Stub constructor
    }
    
    @Override
    public String getName() { return "FaceDetectorModule"; }
    
    @Override
    public void initialize() {
        // Stub implementation
    }
    
    @Override
    public boolean canOverrideExistingModule() { return false; }
    
    @Override
    public void onCatalystInstanceDestroy() {
        // Stub implementation
    }
    
    @Override
    public void invalidate() {
        // Stub implementation
    }
    
    // Stub for optional face detector module
}
STUB_EOF
            
            # Create stub for barcode detector
            mkdir -p "${KIT_ANDROID_DIR}/src/main/java/org/reactnative/barcodedetector"
            cat > "${KIT_ANDROID_DIR}/src/main/java/org/reactnative/barcodedetector/RNBarcodeDetector.java" <<'STUB_EOF'
package org.reactnative.barcodedetector;

import com.facebook.react.bridge.ReactContext;

public class RNBarcodeDetector {
    public static final int ALL_FORMATS = 0;
    public static final int NORMAL_MODE = 1;
    public static final int FAST_MODE = 2;
    public static final int ALTERNATE_MODE = 3;
    public static final int INVERTED_MODE = 4;
    
    public RNBarcodeDetector(ReactContext context) {
        // Stub constructor
    }
    
    public boolean isOperational() { return false; }
    public void setBarcodeType(int type) {
        // Stub implementation
    }
    public void release() {
        // Stub implementation
    }
    // Stub for optional barcode detector dependency
}
STUB_EOF
            
            cat > "${KIT_ANDROID_DIR}/src/main/java/org/reactnative/barcodedetector/BarcodeFormatUtils.java" <<'STUB_EOF'
package org.reactnative.barcodedetector;

import java.util.HashMap;
import java.util.Map;

public class BarcodeFormatUtils {
    public static final Map<String, Object> REVERSE_FORMATS = new HashMap<>();
    static {
        REVERSE_FORMATS.put("aztec", 0);
        REVERSE_FORMATS.put("ean13", 1);
        REVERSE_FORMATS.put("ean8", 2);
        REVERSE_FORMATS.put("qr", 3);
        REVERSE_FORMATS.put("pdf417", 4);
        REVERSE_FORMATS.put("upce", 5);
        REVERSE_FORMATS.put("datamatrix", 6);
        REVERSE_FORMATS.put("code39", 7);
        REVERSE_FORMATS.put("code93", 8);
        REVERSE_FORMATS.put("interleaved2of5", 9);
        REVERSE_FORMATS.put("codabar", 10);
        REVERSE_FORMATS.put("code128", 11);
        REVERSE_FORMATS.put("maxicode", 12);
        REVERSE_FORMATS.put("rss14", 13);
        REVERSE_FORMATS.put("rssexpanded", 14);
        REVERSE_FORMATS.put("upca", 15);
        REVERSE_FORMATS.put("all", 0);
    }
    // Stub for optional barcode detector utilities
}
STUB_EOF
            
            # Create R.java stub for camera resources
            mkdir -p "${KIT_ANDROID_DIR}/src/main/java/com/vsco/nativekit/camera"
            cat > "${KIT_ANDROID_DIR}/src/main/java/com/vsco/nativekit/camera/R.java" <<'STUB_EOF'
package com.vsco.nativekit.camera;

// Stub R class for react-native-camera resources
public final class R {
    public static final class id {
        public static final int texture_view = 0;
        public static final int surface_view = 0;
    }
    public static final class layout {
        public static final int texture_view = 0;
        public static final int surface_view = 0;
    }
}
STUB_EOF
            
            # Fix R imports in camera files
            find "${KIT_ANDROID_DIR}/src/main/java/com/vsco/nativekit/camera" -name "*.java" -exec perl -pi -e 's/import\s+([^;]+)\.R;/import com.vsco.nativekit.camera.R;/g' {} \; 2>/dev/null || true
            
            # Create stub AsyncTask classes for optional features
            mkdir -p "${KIT_ANDROID_DIR}/src/main/java/com/vsco/nativekit/camera/tasks"
            cat > "${KIT_ANDROID_DIR}/src/main/java/com/vsco/nativekit/camera/tasks/FaceDetectorAsyncTask.java" <<'STUB_EOF'
package com.vsco.nativekit.camera.tasks;

import android.os.AsyncTask;
import org.reactnative.facedetector.RNFaceDetector;

public class FaceDetectorAsyncTask extends AsyncTask<Void, Void, Void> {
    private FaceDetectorAsyncTaskDelegate delegate;
    private RNFaceDetector faceDetector;
    private byte[] data;
    private int width, height, correctRotation;
    private float density;
    private int facing, viewWidth, viewHeight, paddingX, paddingY;
    
    public FaceDetectorAsyncTask(FaceDetectorAsyncTaskDelegate delegate, RNFaceDetector faceDetector,
                                 byte[] data, int width, int height, int correctRotation,
                                 float density, int facing, int viewWidth, int viewHeight,
                                 int paddingX, int paddingY) {
        this.delegate = delegate;
        this.faceDetector = faceDetector;
        this.data = data;
        this.width = width;
        this.height = height;
        this.correctRotation = correctRotation;
        this.density = density;
        this.facing = facing;
        this.viewWidth = viewWidth;
        this.viewHeight = viewHeight;
        this.paddingX = paddingX;
        this.paddingY = paddingY;
    }
    
    @Override
    protected Void doInBackground(Void... voids) {
        // Stub implementation - optional feature
        return null;
    }
    
    @Override
    protected void onPostExecute(Void result) {
        if (delegate != null) {
            delegate.onFaceDetectingTaskCompleted();
        }
    }
}
STUB_EOF
            
            cat > "${KIT_ANDROID_DIR}/src/main/java/com/vsco/nativekit/camera/tasks/BarcodeDetectorAsyncTask.java" <<'STUB_EOF'
package com.vsco.nativekit.camera.tasks;

import android.os.AsyncTask;
import org.reactnative.barcodedetector.RNBarcodeDetector;

public class BarcodeDetectorAsyncTask extends AsyncTask<Void, Void, Void> {
    private BarcodeDetectorAsyncTaskDelegate delegate;
    private RNBarcodeDetector barcodeDetector;
    private byte[] data;
    private int width, height, correctRotation;
    private float density;
    private int facing, viewWidth, viewHeight, paddingX, paddingY;
    
    public BarcodeDetectorAsyncTask(BarcodeDetectorAsyncTaskDelegate delegate, RNBarcodeDetector barcodeDetector,
                                   byte[] data, int width, int height, int correctRotation,
                                   float density, int facing, int viewWidth, int viewHeight,
                                   int paddingX, int paddingY) {
        this.delegate = delegate;
        this.barcodeDetector = barcodeDetector;
        this.data = data;
        this.width = width;
        this.height = height;
        this.correctRotation = correctRotation;
        this.density = density;
        this.facing = facing;
        this.viewWidth = viewWidth;
        this.viewHeight = viewHeight;
        this.paddingX = paddingX;
        this.paddingY = paddingY;
    }
    
    @Override
    protected Void doInBackground(Void... voids) {
        // Stub implementation - optional feature
        return null;
    }
    
    @Override
    protected void onPostExecute(Void result) {
        if (delegate != null) {
            delegate.onBarcodeDetectingTaskCompleted();
        }
    }
}
STUB_EOF
            
            # Create stub for TextRecognizerAsyncTask
            cat > "${KIT_ANDROID_DIR}/src/main/java/com/vsco/nativekit/camera/tasks/TextRecognizerAsyncTask.java" <<'STUB_EOF'
package com.vsco.nativekit.camera.tasks;

import android.os.AsyncTask;
import com.facebook.react.bridge.ReactContext;

public class TextRecognizerAsyncTask extends AsyncTask<Void, Void, Void> {
    private TextRecognizerAsyncTaskDelegate delegate;
    private ReactContext context;
    private byte[] data;
    private int width, height, correctRotation;
    private float density;
    private int facing, viewWidth, viewHeight, paddingX, paddingY;
    
    public TextRecognizerAsyncTask(TextRecognizerAsyncTaskDelegate delegate, ReactContext context,
                                  byte[] data, int width, int height, int correctRotation,
                                  float density, int facing, int viewWidth, int viewHeight,
                                  int paddingX, int paddingY) {
        this.delegate = delegate;
        this.context = context;
        this.data = data;
        this.width = width;
        this.height = height;
        this.correctRotation = correctRotation;
        this.density = density;
        this.facing = facing;
        this.viewWidth = viewWidth;
        this.viewHeight = viewHeight;
        this.paddingX = paddingX;
        this.paddingY = paddingY;
    }
    
    @Override
    protected Void doInBackground(Void... voids) {
        // Stub implementation - optional feature
        return null;
    }
    
    @Override
    protected void onPostExecute(Void result) {
        if (delegate != null) {
            delegate.onTextRecognizerTaskCompleted();
        }
    }
}
STUB_EOF
            
            log "    ✅ Created stub classes for optional dependencies"
        fi
        
        log "    ✅ Android native code bundled"
    fi
    
    # Bundle iOS native code
    if [ "$has_ios" = true ]; then
        local ios_source_dir=""
        if [ -d "${package_source}/apple" ]; then
            ios_source_dir="${package_source}/apple"
        elif [ -d "${package_source}/ios" ]; then
            ios_source_dir="${package_source}/ios"
        fi
        
        if [ -n "$ios_source_dir" ]; then
            # Create module directory in iOS Sources
            # Convert package name to module name (e.g., react-native-svg -> VSCOSvg)
            # react-native-safe-area-context -> VSCOSafeAreaContext
            local module_name=$(node -e "
                const pkg = '$package_name';
                let name = pkg.replace(/^(react-native-|expo-)/, '');
                // Convert kebab-case to PascalCase
                name = name.split('-').map(word => 
                    word.charAt(0).toUpperCase() + word.slice(1)
                ).join('');
                console.log('VSCO' + name);
            " 2>/dev/null)
            
            if [ -z "$module_name" ]; then
                # Fallback if node fails
                module_name="VSCO$(echo "$package_name" | sed 's/react-native-//' | sed 's/expo-//' | sed 's/-\([a-z]\)/\U\1/g' | sed 's/^./\U&/')"
            fi
            
            local ios_target_dir="${KIT_IOS_PACKAGE_DIR}/Sources/${module_name}"
            log "    Copying iOS native code to ${module_name}..."
            mkdir -p "$ios_target_dir"
            cp -R "$ios_source_dir"/* "$ios_target_dir/" 2>/dev/null || true
            log "    ✅ iOS native code bundled"
        fi
    fi
    
    return 0
}

# Bundle each native dependency
for dep in "${SHARED_NATIVE_DEPS[@]}"; do
    package_source="$TEMP_NPM_DIR/node_modules/$dep"
    
    if [ -d "$package_source" ]; then
        bundle_native_to_kit "$dep" "$package_source"
    else
        warn "    $dep not found in node_modules"
    fi
done

log "  ✅ Native code bundled to vsco-native-kit"

########################################
# Step 4.1: Validate bundled packages (check for duplicates and issues)
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

########################################
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
    
    # Strategy 2: Check package.json for known Maven dependencies
    # Some packages list their Maven dependencies in package.json
    local package_json="${package_dir}/package.json"
    if [ -f "$package_json" ]; then
        # Extract androidMavenRepos or similar fields if they exist
        # This is package-specific, so we handle known cases
        case "$package_name" in
            react-native-camera)
                # react-native-camera has specific Maven dependencies
                echo "androidx.exifinterface:exifinterface:1.3.7" >> "$temp_deps_file"
                echo "com.drewnoakes:metadata-extractor:2.18.0" >> "$temp_deps_file"
                echo "com.google.zxing:core:3.5.2" >> "$temp_deps_file"
                ;;
        esac
    fi
    
    # Strategy 3: Known Maven dependencies for common packages (fallback)
    case "$package_name" in
        react-native-camera)
            # Additional dependencies that might be needed
            echo "androidx.annotation:annotation:1.7.1" >> "$temp_deps_file"
            echo "androidx.legacy:legacy-support-v4:1.0.0" >> "$temp_deps_file"
            ;;
        react-native-svg)
            # react-native-svg typically doesn't need additional Maven deps
            ;;
        react-native-safe-area-context)
            # react-native-safe-area-context typically doesn't need additional Maven deps
            ;;
        expo-file-system)
            # expo-file-system dependencies are handled by expo-modules-core
            ;;
    esac
    
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

########################################
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
        
        echo "        .target("
        echo "            name: \"$module\","
        echo "            dependencies: ["
        echo "                .product(name: \"React\", package: \"VSCOReactNativeRuntime\")"
        echo "            ],"
        echo "            path: \"Sources/$module\","
        
        # Exclude Fabric if it exists (generic for any module)
        if [ "$has_fabric" = true ]; then
            echo "            exclude: [\"Fabric\"],  // Exclude Fabric (New Architecture) files - we use Legacy Architecture"
        fi
        
        # Add header search paths if module has subdirectories (generic)
        if [ "$needs_header_paths" = true ] && [ ${#subdirs[@]} -gt 0 ]; then
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
        else
            echo "            publicHeadersPath: \".\""
        fi
        
        echo "        ),"
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
        if grep -qE '^[[:space:]]*React;[^[:space:]]|^[[:space:]]+React;[[:space:]]*$| React;[^@[:space:]]' "$file" 2>/dev/null; then
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
                    # Pass 1: Fix standalone lines with whitespace (entire line is " React;" or "  React;")
                    s/^\s+React;\s*$/@import React;/g;
                    
                    # Pass 2: Fix " React;" or "React;" at start of line followed by non-whitespace (e.g., " React;@implementation")
                    s/^\s*React;([^\s])/@import React;\n$1/g;
                    
                    # Pass 3: Fix " React;" followed by non-whitespace in the middle of a line (not @)
                    s/ React;([^@\s])/\n@import React;\n$1/g;
                ' "$file" 2>/dev/null || true
            else
                # Header .h and C++ .mm files: use #import <React/RCTConvert.h>
                perl -pi -e '
                    # Pass 1: Fix " React.Base.RCTConvert;" -> "@import React.Base.RCTConvert;"
                    s/ React\.Base\.RCTConvert;/@import React.Base.RCTConvert;/g;
                    s/^ React\.Base\.RCTConvert;/@import React.Base.RCTConvert;/g;
                    
                    # Pass 2: Fix standalone lines with whitespace (entire line is " React;" or "  React;")
                    s/^\s+React;\s*$/#import <React\/RCTConvert.h>/g;
                    
                    # Pass 3: Fix " React;" or "React;" at start of line followed by non-whitespace (e.g., " React;@implementation")
                    s/^\s*React;([^\s])/#import <React\/RCTConvert.h>\n$1/g;
                    
                    # Pass 4: Fix " React;" followed by non-whitespace in the middle of a line (not @)
                    s/ React;([^@\s])/\n#import <React\/RCTConvert.h>\n$1/g;
                ' "$file" 2>/dev/null || true
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

# Create VSCONativeKit.m source file (required for SPM compilation)
log "  Creating VSCONativeKit.m source file..."
mkdir -p "${KIT_IOS_PACKAGE_DIR}/Sources/VSCONativeKit"
cat > "${KIT_IOS_PACKAGE_DIR}/Sources/VSCONativeKit/VSCONativeKit.m" <<'M_EOF'
/**
 * VSCONativeKit - Unified Native Kit
 * 
 * This is a wrapper target that aggregates VSCOSafeAreaContext and VSCOSvg.
 * The actual implementations are in those targets.
 */

#import "VSCONativeKit.h"

// This file ensures the target compiles correctly.
// The actual functionality comes from VSCOSafeAreaContext and VSCOSvg dependencies.
M_EOF

# Ensure VSCONativeKit.h exists
if [ ! -f "${KIT_IOS_PACKAGE_DIR}/Sources/VSCONativeKit/VSCONativeKit.h" ]; then
    cat > "${KIT_IOS_PACKAGE_DIR}/Sources/VSCONativeKit/VSCONativeKit.h" <<'H_EOF'
// VSCONativeKit - Unified Native Kit Header
// This file aggregates all native kit modules
H_EOF
fi

log "  ✅ Created VSCONativeKit source files"

########################################
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
./gradlew publishReleasePublicationToMavenLocal > /dev/null 2>&1

if [ $? -eq 0 ]; then
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
# Note: Cleanup is handled by trap on exit
log "🎉 SUCCESS! vsco-native-kit generated"
echo ""
echo "📍 Location: $KIT_DIR"
echo ""
echo "📦 Android AAR:"
echo "   • Location: $AAR_FILE"
echo "   • Size: $AAR_SIZE"
echo "   • Published to: Maven Local (com.vsco:vsco-native-kit:1.0.0)"
echo ""
echo "📦 iOS SPM:"
echo "   • Location: $KIT_IOS_PACKAGE_DIR"
echo "   • Modules: ${IOS_MODULES[*]:-none}"
echo ""
echo "📋 Bundled Native Dependencies:"
for dep in "${SHARED_NATIVE_DEPS[@]}"; do
    echo "   • $dep"
done
echo ""
echo "📝 Next steps:"
echo "   1. Update module AAR generation scripts to depend on vsco-native-kit"
echo "   2. Update module SPM generation scripts to depend on VSCONativeKit"
echo "   3. Test integration in native apps"
echo ""

