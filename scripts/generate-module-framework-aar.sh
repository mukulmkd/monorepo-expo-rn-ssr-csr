#!/usr/bin/env bash
set -euo pipefail

########################################
# Module Framework AAR Generator
#
# Generates Android AAR files for React Native modules
# that are published to Verdaccio.
#
# Usage:
#   ./scripts/generate-module-framework-aar.sh <module-name>
#   Example: ./scripts/generate-module-framework-aar.sh products
#
# Module names: products, cart, pdp
#
# Workflow:
#   1. Fetch latest module from Verdaccio
#   2. Create JavaScript bundle for Android
#   3. Create Android Library project structure
#   4. Create Kotlin wrapper class
#   5. Build AAR file using Gradle
#
########################################

MONOREPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANDROID_PROPS_DIR="${MONOREPO_ROOT}/android-props"

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
# Convert module name to lowercase (bash 3.2 compatible)
MODULE_NAME_LOWER=$(echo "$MODULE_NAME" | tr '[:upper:]' '[:lower:]')

# Folder naming: vsco-rn-module-XXXX (e.g., vsco-rn-module-products)
FRAMEWORK_DIR_NAME="vsco-rn-module-${MODULE_NAME_LOWER}"
FRAMEWORK_DIR="${MONOREPO_ROOT}/frameworks/android/${FRAMEWORK_DIR_NAME}"

# Framework name for Gradle project and Kotlin class (keep descriptive for code)
FRAMEWORK_NAME="${MODULE_COMPONENT}Framework"  # ModuleProductsFramework, ModuleCartFramework, etc.

BUILD_DIR="${FRAMEWORK_DIR}/build"
DIST_DIR="${FRAMEWORK_DIR}/dist"
SOURCES_DIR="${FRAMEWORK_DIR}/src/main"
ASSETS_DIR="${SOURCES_DIR}/assets"

# AAR naming: vsco-rn-module-XXXX-release.aar
AAR_NAME="vsco-rn-module-${MODULE_NAME_LOWER}-release.aar"
JAVA_DIR="${SOURCES_DIR}/java/com/vscorp/${MODULE_NAME_LOWER}"
BUNDLE_FILE="${ASSETS_DIR}/module-${MODULE_NAME}.bundle"

# Temporary npm environment for bundling (only used if module not in monorepo)
TEMP_NPM_DIR="${BUILD_DIR}/npm-env"

# Verdaccio configuration - This will be jfrog in production so need to parametrize it
VERDACCIO_URL="http://localhost:4873"

# Package name for Java/Kotlin (lowercase, no hyphens)
PACKAGE_NAME="com.vscorp.${MODULE_NAME_LOWER}"

########################################
# Helpers
########################################
log(){ echo -e "\n==> $*\n"; }
err(){ echo -e "\n‼️ ERROR: $*\n" >&2; }
warn(){ echo -e "\n⚠️  WARNING: $*\n"; }

########################################
# Native Dependency Detection and Bundling
########################################

# Function to detect native dependencies by scanning source files
# Scans .tsx/.ts/.js/.jsx files for react-native-* and expo-* imports
# Checks module package.json first, then root package.json
# Only includes packages that have actual native code
detect_native_dependencies() {
    local module_dir="$1"
    local module_package_json="$2"
    local root_package_json="${MONOREPO_ROOT}/package.json"
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

# Generic function to bundle native dependencies into module AAR
# Usage: bundle_native_dependency <package_name> <framework_dir>
# Note: We already know the package is a dependency (detected earlier), so we just need to find and copy it
bundle_native_dependency() {
    local package_name="$1"
    local framework_dir="$2"
    local sources_dir="${framework_dir}/src/main"
    local java_dir="${sources_dir}/java"
    
    log "  Bundling $package_name native code..."
    
    # Find package in node_modules (check multiple locations)
    # Priority: 1. Installed package's node_modules, 2. Temp npm env, 3. Monorepo node_modules
    local package_source=""
    if [ -d "${MODULE_DIR}/node_modules/${package_name}" ]; then
        package_source="${MODULE_DIR}/node_modules/${package_name}"
    elif [ -d "${TEMP_NPM_DIR}/node_modules/${package_name}" ]; then
        package_source="${TEMP_NPM_DIR}/node_modules/${package_name}"
    elif [ -d "${MONOREPO_ROOT}/node_modules/${package_name}" ]; then
        package_source="${MONOREPO_ROOT}/node_modules/${package_name}"
    else
        warn "    $package_name not found in node_modules"
        warn "    Searched: ${MODULE_DIR}/node_modules, ${TEMP_NPM_DIR}/node_modules, ${MONOREPO_ROOT}/node_modules"
        return 1
    fi
    
    log "    Found $package_name at: $package_source"
    
    # Verify that this package actually has native code
    # Only bundle if android/ios/apple folders exist
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
        log "    ⚠️  $package_name has no native code (no android/ios folders) - skipping"
        log "    ℹ️  This is a JS-only library, no bundling needed"
        return 1
    fi
    
    # Copy Android native code (if present)
    local android_src="${package_source}/android/src/main/java"
    local android_paper="${package_source}/android/src/paper/java"
    local android_res="${package_source}/android/src/main/res"
    local android_kotlin="${package_source}/android/src/main/kotlin"
    
    local bundled_anything=false
    
    # Copy main Java source
    if [ -d "$android_src" ]; then
        log "    Copying Android native code from: $android_src"
        mkdir -p "$java_dir"
        cp -R "$android_src"/* "$java_dir/" 2>/dev/null || true
        # Fix BuildConfig references in Kotlin files (common issue when bundling)
        # Some packages have .kt files in the java directory
        find "$java_dir" -name "*.kt" -type f -exec perl -pi -e 's/\bBuildConfig\./com.facebook.react.BuildConfig./g' {} \; 2>/dev/null || true
        # Fix IS_NEW_ARCHITECTURE_ENABLED - React Native BuildConfig doesn't have this field
        # Use false as default (new architecture disabled when bundling native code)
        find "$java_dir" -name "*.kt" -type f -exec perl -pi -e 's/com\.facebook\.react\.BuildConfig\.IS_NEW_ARCHITECTURE_ENABLED/false/g' {} \; 2>/dev/null || true
        log "    ✅ Copied Android native code"
        bundled_anything=true
    fi
    
    # Copy Kotlin source (if any)
    if [ -d "$android_kotlin" ]; then
        log "    Copying Android Kotlin code..."
        mkdir -p "$java_dir"
        cp -R "$android_kotlin"/* "$java_dir/" 2>/dev/null || true
        # Fix BuildConfig references in Kotlin files (common issue when bundling)
        # Use perl for cross-platform compatibility (works on both macOS and Linux)
        find "$java_dir" -name "*.kt" -type f -exec perl -pi -e 's/\bBuildConfig\./com.facebook.react.BuildConfig./g' {} \; 2>/dev/null || true
        log "    ✅ Copied Android Kotlin code (fixed BuildConfig references)"
        bundled_anything=true
    fi
    
    # Copy Android paper source (codegen types)
    if [ -d "$android_paper" ]; then
        log "    Copying Android paper source (codegen types)..."
        mkdir -p "$java_dir"
        cp -R "$android_paper"/* "$java_dir/" 2>/dev/null || true
        log "    ✅ Copied Android paper source"
        bundled_anything=true
    fi
    
    # Copy Android resources if any
    if [ -d "$android_res" ]; then
        local res_dir="${sources_dir}/res"
        log "    Copying Android resources..."
        mkdir -p "$res_dir"
        cp -R "$android_res"/* "$res_dir/" 2>/dev/null || true
        log "    ✅ Copied Android resources"
        bundled_anything=true
    fi
    
    if [ "$bundled_anything" = true ]; then
        log "  ✅ $package_name native code bundled"
        return 0
    else
        log "  ⚠️  $package_name has no Android native code to bundle"
        return 1
    fi
}

# Function to detect ReactPackage classes in bundled code
# Returns list of fully qualified class names that implement ReactPackage
detect_react_packages() {
    local framework_dir="$1"
    local java_dir="${framework_dir}/src/main/java"
    local packages=""
    
    if [ ! -d "$java_dir" ]; then
        return
    fi
    
    # Find all *Package.java and *Package.kt files and extract their class names
    # Look for files that contain "ReactPackage" or "BaseReactPackage"
    while IFS= read -r package_file; do
        if [ -f "$package_file" ]; then
            # Extract package name from file path
            # Example: java/com/horcrux/svg/SvgPackage.java -> com.horcrux.svg.SvgPackage
            # Example: java/com/th3rdwave/safeareacontext/SafeAreaContextPackage.kt -> com.th3rdwave.safeareacontext.SafeAreaContextPackage
            local relative_path="${package_file#$java_dir/}"
            local class_name="${relative_path%.java}"
            class_name="${class_name%.kt}"
            class_name="${class_name//\//.}"
            
            # Verify it's actually a ReactPackage by checking the file content
            # Check for Java: "implements ReactPackage" or "extends BaseReactPackage"
            # Check for Kotlin: ": BaseReactPackage()" or ": ReactPackage"
            if grep -qE "(implements|extends).*ReactPackage|: (BaseReactPackage|ReactPackage)" "$package_file" 2>/dev/null; then
                packages="${packages}${class_name} "
            fi
        fi
    done < <(find "$java_dir" -type f \( -name "*Package.java" -o -name "*Package.kt" \) 2>/dev/null)
    
    echo "$packages"
}

########################################
# Validate environment
########################################
log "Validating environment..."

# Check Verdaccio is running
log "  Checking Verdaccio..."
if ! curl -s "$VERDACCIO_URL" > /dev/null; then
  err "Verdaccio is not running on $VERDACCIO_URL"
  echo "   Please start Verdaccio: npm run verdaccio:start"
  exit 1
fi
log "✅ Verdaccio is accessible"

# Check module exists in Verdaccio
log "  Checking module in Verdaccio..."
if ! npm view "$MODULE_PACKAGE" --registry "$VERDACCIO_URL" > /dev/null 2>&1; then
  err "Module $MODULE_PACKAGE not found in Verdaccio"
  echo "   Please publish the module: npm run verdaccio:publish-all"
  exit 1
fi
log "✅ Module $MODULE_PACKAGE found in Verdaccio"

# Check required tools
if ! command -v npx &> /dev/null; then
  err "npx not found. Please install Node.js."
  exit 1
fi

# Check for Android SDK (Gradle will check more thoroughly)
if [ -z "${ANDROID_HOME:-}" ] && [ -z "${ANDROID_SDK_ROOT:-}" ]; then
  warn "ANDROID_HOME or ANDROID_SDK_ROOT not set. Gradle may fail if Android SDK is not found."
  warn "   Set ANDROID_HOME to your Android SDK path, or ensure it's in your PATH."
fi

########################################
# Ensure directory structure
########################################
log "Setting up directory structure..."

# Ensure frameworks/android exists
FRAMEWORKS_DIR="${MONOREPO_ROOT}/frameworks"
FRAMEWORKS_ANDROID_DIR="${MONOREPO_ROOT}/frameworks/android"

if [ ! -d "$FRAMEWORKS_DIR" ]; then
  log "Creating frameworks directory..."
  mkdir -p "$FRAMEWORKS_DIR"
fi

if [ ! -d "$FRAMEWORKS_ANDROID_DIR" ]; then
  log "Creating frameworks/android directory..."
  mkdir -p "$FRAMEWORKS_ANDROID_DIR"
fi

# Create framework directory structure
mkdir -p "$FRAMEWORK_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$DIST_DIR"
mkdir -p "$ASSETS_DIR"
mkdir -p "$JAVA_DIR"

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

# Ensure Assets directory exists
mkdir -p "$ASSETS_DIR"

# Bundle JavaScript
log "  Bundling JavaScript for Android..."

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
log "  Assets destination: $ASSETS_DIR"

# Bundle with optimizations:
# - No --reset-cache: Uses Metro cache (much faster on subsequent runs)
# - Uses monorepo's node_modules for faster resolution
log "  Bundling (this may take a minute, Metro cache will speed up subsequent runs)..."

# Run bundle command and capture both stdout and stderr
# Temporarily disable exit on error to capture exit code and output
set +e  # Temporarily disable exit on error to capture exit code
BUNDLE_OUTPUT=$($REACT_NATIVE_CLI bundle \
  --platform android \
  --entry-file "$MODULE_ENTRY" \
  --bundle-output "$BUNDLE_FILE" \
  --assets-dest "$ASSETS_DIR" \
  --dev false \
  --minify false \
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

########################################
# Step 1.5: Native Dependencies Detection (for vsco-native-kit)
########################################
log "Step 1.5: Detecting native dependencies..."

# Detect native dependencies from the module installed from Verdaccio
# This determines if we need to add vsco-native-kit dependency
NATIVE_DEPS_DETECTED=""
if [ -d "$MODULE_DIR" ] && [ -f "${MODULE_DIR}/package.json" ]; then
    log "  Scanning module for native dependencies..."
    # Pass TEMP_NPM_DIR so detection can scan transitive dependencies like @pkg/ui
    NATIVE_DEPS_DETECTED=$(detect_native_dependencies "$MODULE_DIR" "${MODULE_DIR}/package.json" "$TEMP_NPM_DIR")
    
    if [ -n "$NATIVE_DEPS_DETECTED" ]; then
        log "  ✅ Found native dependencies: $NATIVE_DEPS_DETECTED"
        log "  ℹ️  These will be provided by vsco-native-kit AAR dependency"
    else
        log "  ℹ️  No native dependencies detected in this module"
        log "  ℹ️  vsco-native-kit dependency will not be added"
    fi
else
    warn "  Module directory or package.json not found - cannot detect native dependencies"
    warn "  Will not add vsco-native-kit dependency"
fi

# No native bundling needed - vsco-native-kit provides all native dependencies (if any)
export DETECTED_REACT_PACKAGES=""

########################################
# Step 2: Create Android Library Structure
########################################
log "Step 2: Creating Android Library structure..."

# Create AndroidManifest.xml
cat > "${SOURCES_DIR}/AndroidManifest.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="${PACKAGE_NAME}">
    
    <uses-sdk android:minSdkVersion="23" android:targetSdkVersion="34" />
    
    <!-- This is a library module, no application-level configuration needed -->
</manifest>
EOF

log "  ✅ Created AndroidManifest.xml"

# Create build.gradle
# Note: Module frameworks use Maven dependencies (com.facebook.react:react-android)
# No local ReactNativeRuntime AARs needed - dependencies resolved from Maven Central
cat > "${FRAMEWORK_DIR}/build.gradle" <<EOF
plugins {
    id 'com.android.library'
    id 'org.jetbrains.kotlin.android'
    id 'maven-publish'
}

android {
    namespace '${PACKAGE_NAME}'
    compileSdk 34

    defaultConfig {
        minSdk 23
        targetSdk 34
        versionName project.findProperty("publish_version") ?: "1.0.0"
        
        consumerProguardFiles "consumer-rules.pro"
    }
    
    lint {
        // Don't fail build on lint errors in bundled native code
        // Bundled code (e.g., react-native-svg) may have lint warnings/errors
        abortOnError = false
        checkReleaseBuilds = false
        // Ignore lint errors in bundled native dependencies
        disable.addAll(['WrongConstant', 'Deprecated'])
    }

    buildTypes {
        release {
            minifyEnabled false
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
        }
    }
    
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_1_8
        targetCompatibility JavaVersion.VERSION_1_8
    }
    
    kotlinOptions {
        jvmTarget = '1.8'
    }
}

// Note: Repositories are defined in settings.gradle
// (repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS) requires this)

dependencies {
    // React Native dependencies - using standard Maven dependencies
    // Consumers must add React Native to their app's dependencies
    compileOnly 'com.facebook.react:react-android:0.81.5'
    compileOnly 'com.facebook.react:hermes-android:0.81.5'
    
    // Kotlin standard library
    implementation 'org.jetbrains.kotlin:kotlin-stdlib:1.9.0'
$(if [ -n "$NATIVE_DEPS_DETECTED" ]; then
    echo "    // Native dependencies are provided by vsco-native-kit"
    echo "    // Detected native dependencies: $NATIVE_DEPS_DETECTED"
    echo "    implementation 'com.vsco:vsco-native-kit:1.0.0'"
else
    echo "    // No native dependencies detected - vsco-native-kit not needed"
fi)
}

// Publishing configuration
afterEvaluate {
    publishing {
        publications {
            release(MavenPublication) {
                groupId = "com.vscorp"
                artifactId = "vsco-rn-module-${MODULE_NAME_LOWER}"
                version = "1.0.0"
                
                // Publish AAR using Android component
                // This automatically:
                //   - Includes the AAR file
                //   - Generates POM with all dependencies
                //   - Makes transitive dependencies available to consuming apps
                from components.release
            }
        }
    }
    
    // Ensure publish task depends on assembleRelease
    tasks.named("publishReleasePublicationToMavenLocal").configure {
        dependsOn("assembleRelease")
    }
}
EOF

# Replace MODULE_NAME_LOWER placeholder in build.gradle
perl -i -pe "s/\\\$\{MODULE_NAME_LOWER\}/${MODULE_NAME_LOWER}/g" "${FRAMEWORK_DIR}/build.gradle"

log "  ✅ Created build.gradle"

# Create settings.gradle (self-contained, inside framework directory like runtime)
# Must include pluginManagement for Android Gradle Plugin
# flatDir repository must be in settings.gradle (not build.gradle) when repositoriesMode is FAIL_ON_PROJECT_REPOS
cat > "${FRAMEWORK_DIR}/settings.gradle" <<EOF
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
        maven { url 'https://www.jitpack.io' }
        mavenLocal()  // For vsco-native-kit AAR
        // React Native dependencies come from Maven Central (no local AARs needed)
        
        // Note: Artifactory repository is only needed for publishing, not dependency resolution
        // All dependencies come from Maven Central, so Artifactory is configured in build.gradle publishing block only
    }
}

rootProject.name = '${FRAMEWORK_NAME}'
EOF
log "  ✅ Created settings.gradle (self-contained with plugin management)"

# Create gradle.properties (self-contained, inside framework directory like runtime)
cat > "${FRAMEWORK_DIR}/gradle.properties" <<EOF
# Project-wide Gradle settings.
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
android.useAndroidX=true
android.enableJetifier=true
kotlin.code.style=official
EOF
log "  ✅ Created gradle.properties (self-contained)"

# Create local.properties from central android-props folder
LOCAL_PROPERTIES="${FRAMEWORK_DIR}/local.properties"
if [ -f "${ANDROID_PROPS_DIR}/local.properties" ]; then
  cp "${ANDROID_PROPS_DIR}/local.properties" "$LOCAL_PROPERTIES"
  log "  ✅ Copied local.properties from android-props"
else
  # Fallback to ANDROID_HOME if android-props/local.properties doesn't exist
  ANDROID_SDK_PATH=""
  if [ -n "${ANDROID_HOME:-}" ]; then
    ANDROID_SDK_PATH="$ANDROID_HOME"
  elif [ -n "${ANDROID_SDK_ROOT:-}" ]; then
    ANDROID_SDK_PATH="$ANDROID_SDK_ROOT"
  elif [ -d "$HOME/Library/Android/sdk" ]; then
    ANDROID_SDK_PATH="$HOME/Library/Android/sdk"
  fi

  if [ -n "$ANDROID_SDK_PATH" ] && [ -d "$ANDROID_SDK_PATH" ]; then
    cat > "$LOCAL_PROPERTIES" <<EOF
sdk.dir=$ANDROID_SDK_PATH
EOF
    log "  ✅ Created local.properties with SDK path: $ANDROID_SDK_PATH"
  else
    warn "local.properties not found in android-props and ANDROID_HOME not set"
    warn "   Create android-props/local.properties with: sdk.dir=/path/to/android/sdk"
  fi
fi

# Create proguard-rules.pro
cat > "${FRAMEWORK_DIR}/proguard-rules.pro" <<EOF
# Add project specific ProGuard rules here.
# You can control the set of applied configuration files using the
# proguardFiles setting in build.gradle.

# Keep React Native classes
-keep class com.facebook.react.** { *; }
-keep class com.facebook.hermes.** { *; }
-keep class com.facebook.jni.** { *; }

# Keep our framework classes
-keep class ${PACKAGE_NAME}.** { *; }
EOF

log "  ✅ Created proguard-rules.pro"

# Create consumer-rules.pro
cat > "${FRAMEWORK_DIR}/consumer-rules.pro" <<EOF
# ProGuard rules that will be applied to the consuming app
# This file is merged with the app's ProGuard rules

# Keep React Native classes
-keep class com.facebook.react.** { *; }
-keep class com.facebook.hermes.** { *; }
EOF

log "  ✅ Created consumer-rules.pro"

########################################
# Step 3: Create Kotlin Wrapper
########################################
log "Step 3: Creating Kotlin wrapper class..."

# Prepare ReactPackage list for Kotlin code generation
# Native dependencies are now provided by vsco-native-kit
# No need to generate ReactPackage list - VSCONativeKitPackage handles everything
REACT_PACKAGES_LIST="            // Native dependencies provided by vsco-native-kit"

# Build the native kit registration code conditionally
NATIVE_KIT_REGISTRATION_CODE=""
if [ -n "$NATIVE_DEPS_DETECTED" ]; then
    NATIVE_KIT_REGISTRATION_CODE="        // Register vsco-native-kit package (provides all native dependencies)
        // Detected native dependencies: $NATIVE_DEPS_DETECTED
        try {
            val nativeKitPackage = com.vsco.nativekit.VSCONativeKitPackage()
            builder.addPackage(nativeKitPackage)
            Log.d(TAG, \"   ✅ Registered VSCONativeKitPackage (provides all native dependencies)\")
        } catch (e: ClassNotFoundException) {
            Log.w(TAG, \"   ⚠️  VSCONativeKitPackage not found - ensure vsco-native-kit AAR is included as dependency\")
            Log.w(TAG, \"   Native dependencies may not be available\")
        } catch (e: Exception) {
            Log.w(TAG, \"   ⚠️  Failed to register VSCONativeKitPackage: \${e.message}\")
        }"
else
    NATIVE_KIT_REGISTRATION_CODE="        // No native dependencies detected - vsco-native-kit not needed"
fi

# Check if module has Expo dependencies (expo-* packages)
# If it does, we need to register ModuleRegistryAdapter in the module framework's ReactInstanceManager
HAS_EXPO_DEPS=false
if echo "$NATIVE_DEPS_DETECTED" | grep -qE "expo-"; then
    HAS_EXPO_DEPS=true
fi

# Generate Expo modules registration code if Expo dependencies are detected
if [ "$HAS_EXPO_DEPS" = true ]; then
    EXPO_MODULES_REGISTRATION_CODE="        // Register Expo modules bridge (required for expo-* modules)
        // Detected Expo dependencies in module
        try {
            val expoModulesAdapter = expo.modules.adapters.react.ModuleRegistryAdapter(
                expo.modules.ExpoModulesPackageList.getPackageList()
            )
            builder.addPackage(expoModulesAdapter)
            Log.d(TAG, \"   ✅ Registered ModuleRegistryAdapter (Expo Modules bridge)\")
        } catch (e: ClassNotFoundException) {
            Log.w(TAG, \"   ⚠️  Expo modules classes not found - ensure expo-modules-core and vsco-native-kit are included\")
            Log.w(TAG, \"   Expo modules may not be available: \${e.message}\")
        } catch (e: Exception) {
            Log.w(TAG, \"   ⚠️  Failed to register Expo modules: \${e.message}\")
        }"
else
    EXPO_MODULES_REGISTRATION_CODE="        // No Expo dependencies detected - Expo modules registration not needed"
fi

# Generate Expo imports if needed
EXPO_IMPORTS=""
if [ "$HAS_EXPO_DEPS" = true ]; then
    EXPO_IMPORTS="import expo.modules.ExpoModulesPackageList
import expo.modules.adapters.react.ModuleRegistryAdapter"
fi

cat > "${JAVA_DIR}/${FRAMEWORK_NAME}.kt" <<'KOTLIN_EOF'
package ${PACKAGE_NAME}

import android.content.Context
import android.util.Log
import com.facebook.react.ReactInstanceManager
import com.facebook.react.ReactInstanceManagerBuilder
import com.facebook.react.ReactRootView
import com.facebook.react.bridge.JSBundleLoader
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.common.LifecycleState
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
${EXPO_IMPORTS_PLACEHOLDER}

/**
 * ${FRAMEWORK_NAME}
 * 
 * Android framework wrapper for ${MODULE_COMPONENT} React Native module.
 * 
 * This class provides a simple API to load and render the ${MODULE_COMPONENT} module
 * in any Android Activity or Fragment.
 * 
 * Usage:
 * ```kotlin
 * val framework = ${FRAMEWORK_NAME}.getInstance()
 * val bundlePath = framework.getBundlePath(context)
 * val moduleName = framework.getModuleName()
 * 
 * val rootView = ReactRootView(context)
 * rootView.startReactApplication(reactInstanceManager, moduleName, null)
 * ```
 */
class ${FRAMEWORK_NAME} private constructor() {
    
    companion object {
        private const val TAG = "${FRAMEWORK_NAME}"
        private const val BUNDLE_NAME = "module-${MODULE_NAME}.bundle"
        private const val MODULE_NAME = "${MODULE_COMPONENT}"
        
        @Volatile
        private var INSTANCE: ${FRAMEWORK_NAME}? = null
        
        /**
         * Get the singleton instance of ${FRAMEWORK_NAME}
         */
        fun getInstance(): ${FRAMEWORK_NAME} {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: ${FRAMEWORK_NAME}().also { INSTANCE = it }
            }
        }
    }
    
    /**
     * Gets the bundle file path for the ${MODULE_COMPONENT} module
     * 
     * @param context Android context
     * @return The absolute path to the module-${MODULE_NAME}.bundle file, or null if not found
     */
    fun getBundlePath(context: Context): String? {
        Log.d(TAG, "🔍 Looking for bundle: $BUNDLE_NAME")
        
        // Method 1: Try to find in assets directory (standard Android library location)
        try {
            val assets = context.assets
            assets.open(BUNDLE_NAME).use {
                // Bundle exists in assets
                val bundlePath = "file:///android_asset/$BUNDLE_NAME"
                Log.d(TAG, "✅ Found bundle in assets: $bundlePath")
                return bundlePath
            }
        } catch (e: Exception) {
            Log.d(TAG, "   Bundle not found in assets, trying other methods...")
        }
        
        // Method 2: Try to find in application's assets
        try {
            val appContext = context.applicationContext
            val assets = appContext.assets
            assets.open(BUNDLE_NAME).use {
                val bundlePath = "file:///android_asset/$BUNDLE_NAME"
                Log.d(TAG, "✅ Found bundle in application assets: $bundlePath")
                return bundlePath
            }
        } catch (e: Exception) {
            Log.d(TAG, "   Bundle not found in application assets")
        }
        
        // Method 3: Try to find in files directory (if copied there)
        val filesDir = context.filesDir
        val bundleFile = File(filesDir, BUNDLE_NAME)
        if (bundleFile.exists()) {
            val bundlePath = bundleFile.absolutePath
            Log.d(TAG, "✅ Found bundle in files directory: $bundlePath")
            return bundlePath
        }
        
        // Method 4: Try to find in external files directory
        val externalFilesDir = context.getExternalFilesDir(null)
        if (externalFilesDir != null) {
            val bundleFile = File(externalFilesDir, BUNDLE_NAME)
            if (bundleFile.exists()) {
                val bundlePath = bundleFile.absolutePath
                Log.d(TAG, "✅ Found bundle in external files directory: $bundlePath")
                return bundlePath
            }
        }
        
        Log.e(TAG, "❌ Bundle not found in any location")
        Log.e(TAG, "   Searched:")
        Log.e(TAG, "     - Assets: $BUNDLE_NAME")
        Log.e(TAG, "     - Files dir: ${filesDir.absolutePath}")
        if (externalFilesDir != null) {
            Log.e(TAG, "     - External files dir: ${externalFilesDir.absolutePath}")
        }
        
        return null
    }
    
    /**
     * Gets the module name for the ${MODULE_COMPONENT} module
     * 
     * @return The registered module name ("${MODULE_COMPONENT}")
     */
    fun getModuleName(): String {
        return MODULE_NAME
    }
    
    /**
     * Creates a React Native root view for the module
     * 
     * @param context Android context
     * @param reactInstanceManager The ReactInstanceManager from the consuming app
     * @param initialProperties Optional initial properties to pass to the module
     * @return A configured ReactRootView ready to be added to a view hierarchy, or null if bundle not found
     */
    /**
     * Creates a ReactInstanceManager specifically for this module with its own bundle loader.
     * Each module has its own ReactInstanceManager to load its own bundle from AAR assets.
     * This allows multiple modules to coexist, each with their own bundle.
     */
    private fun createModuleReactInstanceManager(context: Context): ReactInstanceManager {
        val application = context.applicationContext as? android.app.Application
            ?: throw IllegalStateException("Context must be an Application context")
        
        val reactApplication = application as? com.facebook.react.ReactApplication
            ?: throw IllegalStateException("Application must implement ReactApplication")
        
        val reactNativeHost = reactApplication.reactNativeHost
        
        // Create a JSBundleLoader that loads the module's bundle from AAR assets
        // The bundle is merged into the app's assets at build time
        // Note: createAssetLoader takes (context, assetUrl, loadSynchronously)
        // assetUrl should be just the filename, not a full path
        // IMPORTANT: Use application context to access assets, not the passed context
        Log.d(TAG, "🔧 Creating module-specific ReactInstanceManager")
        Log.d(TAG, "   Bundle name: '$BUNDLE_NAME' (length: ${BUNDLE_NAME.length})")
        Log.d(TAG, "   Module: $MODULE_NAME")
        
        // Copy bundle from assets to internal storage and load from file
        // React Native's jniLoadScriptFromAssets has issues loading from AAR assets
        // So we copy to internal storage and use createFileLoader instead
        val appContext = application.applicationContext
        val bundleFile = File(appContext.filesDir, BUNDLE_NAME)
        
        // Check if bundle needs to be copied/updated from assets to internal storage
        var needsCopy = true
        if (bundleFile.exists() && bundleFile.length() > 0) {
            // Bundle exists - check if it needs updating by comparing sizes
            // This is a simple check; for production, consider using bundle hash/version
            try {
                val assets = appContext.assets
                assets.open(BUNDLE_NAME).use { assetStream ->
                    val assetSize = assetStream.available().toLong() // Convert Int to Long
                    val fileSize = bundleFile.length()
                    
                    if (assetSize == fileSize) {
                        // Sizes match - assume bundle is up to date
                        // Note: This is a simple heuristic. For production apps,
                        // consider embedding a bundle hash/version in the AAR and comparing that
                        needsCopy = false
                        Log.d(TAG, "   ✅ Bundle already in internal storage: ${bundleFile.absolutePath} (size: $fileSize bytes)")
                    } else {
                        // Size mismatch - AAR bundle was updated, need to recopy
                        Log.d(TAG, "   🔄 Bundle size mismatch (asset: $assetSize, file: $fileSize) - updating...")
                        needsCopy = true
                    }
                }
            } catch (e: Exception) {
                // If we can't read assets, assume we need to copy
                Log.w(TAG, "   ⚠️ Could not verify bundle from assets, will attempt copy: ${e.message}")
                needsCopy = true
            }
        }
        
        if (needsCopy) {
            try {
                // Copy bundle from assets to internal storage
                val assets = appContext.assets
                assets.open(BUNDLE_NAME).use { input ->
                    bundleFile.outputStream().use { output ->
                        input.copyTo(output)
                    }
                }
                val size = bundleFile.length()
                Log.d(TAG, "   ✅ Bundle copied to internal storage: ${bundleFile.absolutePath} (size: $size bytes)")
            } catch (e: Exception) {
                Log.e(TAG, "   ❌ Failed to copy bundle from assets: $BUNDLE_NAME", e)
                throw IllegalStateException("Failed to copy bundle $BUNDLE_NAME from assets to internal storage", e)
            }
        }
        
        // Load bundle from file path instead of assets
        // This avoids React Native's jniLoadScriptFromAssets issues with AAR assets
        val bundleLoader = JSBundleLoader.createFileLoader(
            bundleFile.absolutePath // Load from file path instead of assets
        )
        
        Log.d(TAG, "   ✅ JSBundleLoader created from file: ${bundleFile.absolutePath}")
        
        // Build a ReactInstanceManager specifically for this module
        // This allows each module to have its own bundle while sharing the same React Native runtime
        // We don't access reactNativeHost.reactInstanceManager to avoid triggering its creation
        // since the main ReactNativeHost may not be fully configured
        val builder = ReactInstanceManagerBuilder()
            .setApplication(application)
            .setBundleAssetName(null) // Don't use default bundle - use our custom loader
            .setJSBundleLoader(bundleLoader) // Use module's bundle from AAR assets
            .setUseDeveloperSupport(reactNativeHost.useDeveloperSupport)
            .setInitialLifecycleState(LifecycleState.BEFORE_CREATE)
        
        // Add core React Native package - required for ReactInstanceManager to work
        builder.addPackage(com.facebook.react.shell.MainReactPackage())
        
${NATIVE_KIT_REGISTRATION_CODE}

${EXPO_MODULES_REGISTRATION_CODE}
        
        return builder.build()
    }
    
    /**
     * Creates a React Native root view for the module
     * 
     * @param context Android context
     * @param reactInstanceManager Optional ReactInstanceManager. If null, creates a module-specific one.
     * @param initialProperties Optional initial properties to pass to the module
     * @return A configured ReactRootView ready to be added to a view hierarchy, or null if bundle not found
     */
    fun createView(
        context: Context,
        reactInstanceManager: ReactInstanceManager? = null,
        initialProperties: android.os.Bundle? = null
    ): ReactRootView? {
        val bundlePath = getBundlePath(context)
        if (bundlePath == null) {
            Log.e(TAG, "❌ Cannot create view: Bundle not found")
            return null
        }
        
        Log.d(TAG, "📦 Creating ReactRootView")
        Log.d(TAG, "   Bundle path: $bundlePath")
        Log.d(TAG, "   Module name: $MODULE_NAME")
        
        // Use provided ReactInstanceManager or create a module-specific one
        // Each module gets its own ReactInstanceManager to load its own bundle from AAR assets
        val moduleReactInstanceManager = reactInstanceManager 
            ?: createModuleReactInstanceManager(context)
        
        // Create ReactRootView
        val rootView = ReactRootView(context)
        
        // Start React application with the module-specific ReactInstanceManager
        // This ensures the module's bundle is loaded from AAR assets
        rootView.startReactApplication(moduleReactInstanceManager, MODULE_NAME, initialProperties)
        
        return rootView
    }
}
KOTLIN_EOF

# Replace variables in the Kotlin file
# Use perl for cross-platform compatibility (works on both macOS BSD sed and Linux GNU sed)
# Replace all placeholders in a single pass for better reliability

# REACT_PACKAGES_LIST is no longer used - we use NATIVE_KIT_REGISTRATION_CODE instead
# This section is kept for backward compatibility but should not be needed

# Replace NATIVE_KIT_REGISTRATION_CODE placeholder
if [ -n "$NATIVE_KIT_REGISTRATION_CODE" ]; then
  # Use perl to replace the placeholder (handles newlines correctly)
  # The pattern in the file is ${NATIVE_KIT_REGISTRATION_CODE}
  perl -i -pe "s|\\\$\{NATIVE_KIT_REGISTRATION_CODE\}|$NATIVE_KIT_REGISTRATION_CODE|g" "${JAVA_DIR}/${FRAMEWORK_NAME}.kt"
else
  # Remove the placeholder line if no native dependencies detected
  perl -i -pe "s/.*\\\$\{NATIVE_KIT_REGISTRATION_CODE\}.*//g" "${JAVA_DIR}/${FRAMEWORK_NAME}.kt"
fi

# Replace EXPO_IMPORTS_PLACEHOLDER with actual imports if Expo dependencies are detected
if [ "$HAS_EXPO_DEPS" = true ]; then
  # Replace placeholder with actual Expo imports
  perl -i -pe "s|\\\$\{EXPO_IMPORTS_PLACEHOLDER\}|import expo.modules.ExpoModulesPackageList\nimport expo.modules.adapters.react.ModuleRegistryAdapter|g" "${JAVA_DIR}/${FRAMEWORK_NAME}.kt"
else
  # Remove the placeholder line if no Expo dependencies
  perl -i -pe "s/.*\\\$\{EXPO_IMPORTS_PLACEHOLDER\}.*//g" "${JAVA_DIR}/${FRAMEWORK_NAME}.kt"
fi

# Replace EXPO_MODULES_REGISTRATION_CODE placeholder
if [ -n "$EXPO_MODULES_REGISTRATION_CODE" ]; then
  perl -i -pe "s|\\\$\{EXPO_MODULES_REGISTRATION_CODE\}|$EXPO_MODULES_REGISTRATION_CODE|g" "${JAVA_DIR}/${FRAMEWORK_NAME}.kt"
else
  perl -i -pe "s/.*\\\$\{EXPO_MODULES_REGISTRATION_CODE\}.*//g" "${JAVA_DIR}/${FRAMEWORK_NAME}.kt"
fi

# Replace other placeholders
# The pattern in the file is ${VAR} (no backslash since we're using single-quoted heredoc)
# Use single quotes for perl to avoid bash expansion issues
perl -i -pe "s/\\\$\{PACKAGE_NAME\}/${PACKAGE_NAME}/g" "${JAVA_DIR}/${FRAMEWORK_NAME}.kt"
perl -i -pe "s/\\\$\{FRAMEWORK_NAME\}/${FRAMEWORK_NAME}/g" "${JAVA_DIR}/${FRAMEWORK_NAME}.kt"
perl -i -pe "s/\\\$\{MODULE_COMPONENT\}/${MODULE_COMPONENT}/g" "${JAVA_DIR}/${FRAMEWORK_NAME}.kt"
perl -i -pe "s/\\\$\{MODULE_NAME\}/${MODULE_NAME}/g" "${JAVA_DIR}/${FRAMEWORK_NAME}.kt"

log "  ✅ Created Kotlin wrapper: ${FRAMEWORK_NAME}.kt"

########################################
# Step 4: Generate Gradle Wrapper and Build AAR
########################################
log "Step 4: Generating Gradle wrapper and building AAR file..."

# Note: Module frameworks now use standard Maven dependencies (com.facebook.react:react-android:0.81.5)
# No need to check for ReactNativeRuntime AARs - they're resolved from Maven Central
log "  Using standard React Native Maven dependencies (no local AARs required)"

# Build AAR using Gradle
cd "$FRAMEWORK_DIR"

# Create AARs directory (similar to ReactNativeRuntime structure)
AARS_DIR="${FRAMEWORK_DIR}/aars"
mkdir -p "$AARS_DIR"

# Generate Gradle wrapper if it doesn't exist
if [ ! -f "${FRAMEWORK_DIR}/gradlew" ]; then
  log "  Generating Gradle wrapper..."
  
  # Try to find Gradle wrapper from various sources
  GRADLEW_SOURCE=""
  
  # 1. Try vsco-rn-host (preferred, same structure)
  VSCO_RN_HOST_GRADLEW="${FRAMEWORKS_ANDROID_DIR}/vsco-rn-host/gradlew"
  if [ -f "$VSCO_RN_HOST_GRADLEW" ]; then
    GRADLEW_SOURCE="$VSCO_RN_HOST_GRADLEW"
    log "  Found Gradle wrapper in vsco-rn-host"
  # 2. Try rn-runtime-source (if it exists)
  elif [ -f "${MONOREPO_ROOT}/rn-runtime-source/RnRuntimeSource/android/gradlew" ]; then
    GRADLEW_SOURCE="${MONOREPO_ROOT}/rn-runtime-source/RnRuntimeSource/android/gradlew"
    log "  Found Gradle wrapper in rn-runtime-source"
  # 3. Try common Android project locations (relative to home directory)
  elif [ -f "${HOME}/Desktop/native-android-app-new/gradlew" ]; then
    GRADLEW_SOURCE="${HOME}/Desktop/native-android-app-new/gradlew"
    log "  Found Gradle wrapper in native-android-app-new (Gradle 8.14.3)"
  fi
  
  if [ -n "$GRADLEW_SOURCE" ]; then
    log "  Copying Gradle wrapper from $(dirname "$GRADLEW_SOURCE")..."
    cp "$GRADLEW_SOURCE" "${FRAMEWORK_DIR}/gradlew"
    chmod +x "${FRAMEWORK_DIR}/gradlew"
    
    # Copy gradle directory
    GRADLE_DIR=$(dirname "$GRADLEW_SOURCE")/gradle
    if [ -d "$GRADLE_DIR" ]; then
      cp -r "$GRADLE_DIR" "${FRAMEWORK_DIR}/"
      log "  ✅ Copied Gradle wrapper and gradle directory"
    else
      warn "Gradle wrapper directory not found, wrapper may not work"
    fi
  elif command -v gradle &> /dev/null; then
    log "  Generating Gradle wrapper using system Gradle..."
    gradle wrapper --gradle-version 8.14.3 --distribution-type bin || {
      err "Failed to generate Gradle wrapper"
      err "Please install Gradle or ensure ReactNativeRuntime has gradlew"
      exit 1
    }
  else
    # Create minimal Gradle wrapper manually
    log "  Creating Gradle wrapper manually..."
    mkdir -p "${FRAMEWORK_DIR}/gradle/wrapper"
    
    # Create gradle-wrapper.properties
    cat > "${FRAMEWORK_DIR}/gradle/wrapper/gradle-wrapper.properties" <<EOF
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-8.14.3-bin.zip
networkTimeout=10000
validateDistributionUrl=true
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
EOF
    
    # Create gradlew script (simplified version)
    cat > "${FRAMEWORK_DIR}/gradlew" <<'GRADLEW_EOF'
#!/bin/sh
# Gradle wrapper script
GRADLE_USER_HOME="${GRADLE_USER_HOME:-${HOME}/.gradle}"
GRADLE_VERSION="8.14.3"
GRADLE_HOME="${GRADLE_USER_HOME}/wrapper/dists/gradle-${GRADLE_VERSION}-bin/*/gradle-${GRADLE_VERSION}"

if [ -d "$GRADLE_HOME" ]; then
    exec "$GRADLE_HOME/bin/gradle" "$@"
else
    echo "Error: Gradle wrapper not initialized. Please run: gradle wrapper"
    exit 1
fi
GRADLEW_EOF
    chmod +x "${FRAMEWORK_DIR}/gradlew"
    
    warn "Gradle wrapper created, but Gradle needs to be downloaded on first run"
    warn "   Run: cd $FRAMEWORK_DIR && ./gradlew --version (this will download Gradle)"
  fi
fi

# Build AAR using Gradle wrapper
log "  Building AAR with Gradle..."
if [ -f "${FRAMEWORK_DIR}/gradlew" ]; then
  # First run will download Gradle if needed
  "${FRAMEWORK_DIR}/gradlew" --version > /dev/null 2>&1 || true
  
  log "  Running: ./gradlew clean assembleRelease"
  BUILD_LOG="${BUILD_DIR}/gradle-build.log"
  mkdir -p "$BUILD_DIR"
  
  if "${FRAMEWORK_DIR}/gradlew" clean assembleRelease --no-daemon --console=plain > "$BUILD_LOG" 2>&1; then
    log "  ✅ Gradle build completed successfully"
  else
    BUILD_EXIT_CODE=$?
    err "Gradle build failed with exit code: $BUILD_EXIT_CODE"
    
    if [ -f "$BUILD_LOG" ]; then
      err "Build log saved to: $BUILD_LOG"
      err "Last 30 lines of build log:"
      tail -30 "$BUILD_LOG" | sed 's/^/  /' >&2
    else
      err "Build log file not created. Running build again to capture output:"
      "${FRAMEWORK_DIR}/gradlew" clean assembleRelease --no-daemon --console=plain 2>&1 | tail -30 | sed 's/^/  /' >&2
    fi
    
    err ""
    err "Common issues:"
    err "  1. Android SDK not configured - set ANDROID_HOME or ANDROID_SDK_ROOT"
    err "  2. Gradle dependencies not resolved - check settings.gradle repositories"
    err "  3. Maven dependencies not accessible - ensure internet connection for Maven Central"
    
    exit 1
  fi
elif command -v gradle &> /dev/null; then
  log "  Building with system Gradle..."
  BUILD_LOG="${BUILD_DIR}/gradle-build.log"
  mkdir -p "$BUILD_DIR"
  
  if gradle clean assembleRelease --no-daemon --console=plain > "$BUILD_LOG" 2>&1; then
    log "  ✅ Gradle build completed successfully"
  else
    BUILD_EXIT_CODE=$?
    err "Gradle build failed with exit code: $BUILD_EXIT_CODE"
    
    if [ -f "$BUILD_LOG" ]; then
      err "Build log saved to: $BUILD_LOG"
      err "Last 30 lines of build log:"
      tail -30 "$BUILD_LOG" | sed 's/^/  /' >&2
    else
      err "Build log file not created. Running build again to capture output:"
      gradle clean assembleRelease --no-daemon --console=plain 2>&1 | tail -30 | sed 's/^/  /' >&2
    fi
    
    err ""
    err "Common issues:"
    err "  1. Android SDK not configured - set ANDROID_HOME or ANDROID_SDK_ROOT"
    err "  2. Gradle dependencies not resolved - check settings.gradle repositories"
    err "  3. Maven dependencies not accessible - ensure internet connection for Maven Central"
    
    exit 1
  fi
else
  err "Gradle not found and wrapper generation failed."
  err "   Please install Gradle or ensure a Gradle wrapper exists"
  exit 1
fi

# Check if AAR was created
BUILD_AAR_FILE="${FRAMEWORK_DIR}/build/outputs/aar/${FRAMEWORK_NAME}-release.aar"
if [ -f "$BUILD_AAR_FILE" ]; then
  AAR_SIZE=$(du -h "$BUILD_AAR_FILE" | cut -f1)
  log "  ✅ AAR created: $BUILD_AAR_FILE ($AAR_SIZE)"
  
  # Publish to Maven Local to generate POM file (needed for Maven Central publishing)
  log "  Publishing to Maven Local to generate POM file..."
  cd "$FRAMEWORK_DIR"
  "${FRAMEWORK_DIR}/gradlew" publishReleasePublicationToMavenLocal > /dev/null 2>&1 || true
  
  # Copy to aars directory with new naming: vsco-rn-module-XXXX-release.aar
  cp "$BUILD_AAR_FILE" "${AARS_DIR}/${AAR_NAME}"
  log "  ✅ AAR copied to: ${AARS_DIR}/${AAR_NAME}"
  
  # Also copy to dist directory with new naming
  mkdir -p "$DIST_DIR"
  cp "$BUILD_AAR_FILE" "${DIST_DIR}/${AAR_NAME}"
  log "  ✅ AAR copied to: ${DIST_DIR}/${AAR_NAME}"
  
  # Copy to central distribution directory
  CENTRAL_DIST_DIR="${MONOREPO_ROOT}/frameworks/android/distribution/aars"
  mkdir -p "$CENTRAL_DIST_DIR"
  cp "$BUILD_AAR_FILE" "${CENTRAL_DIST_DIR}/${AAR_NAME}"
  log "  ✅ AAR copied to central distribution: ${CENTRAL_DIST_DIR}/${AAR_NAME}"
  
  # Copy POM file from local Maven repository (generated during publish)
  # The POM is published to ~/.m2/repository/com/vscorp/vsco-rn-module-XXXX/1.0.0/
  MAVEN_LOCAL_POM="${HOME}/.m2/repository/com/vscorp/vsco-rn-module-${MODULE_NAME_LOWER}/1.0.0/vsco-rn-module-${MODULE_NAME_LOWER}-1.0.0.pom"
  if [ -f "$MAVEN_LOCAL_POM" ]; then
    # Copy POM to build/outputs/aar folder (alongside the AAR)
    AAR_OUTPUT_DIR="${FRAMEWORK_DIR}/build/outputs/aar"
    mkdir -p "$AAR_OUTPUT_DIR"
    cp "$MAVEN_LOCAL_POM" "$AAR_OUTPUT_DIR/${AAR_NAME%.aar}.pom"
    log "  ✅ POM file copied to build/outputs/aar/${AAR_NAME%.aar}.pom"
    
    # Also copy to distribution directories
    cp "$MAVEN_LOCAL_POM" "${AARS_DIR}/${AAR_NAME%.aar}.pom"
    cp "$MAVEN_LOCAL_POM" "${DIST_DIR}/${AAR_NAME%.aar}.pom"
    cp "$MAVEN_LOCAL_POM" "${CENTRAL_DIST_DIR}/${AAR_NAME%.aar}.pom"
    log "  ✅ POM file copied to all distribution directories"
  else
    warn "POM file not found in Maven Local repository"
    warn "  Expected: $MAVEN_LOCAL_POM"
    warn "  POM file is required for Maven Central publishing"
  fi
else
  err "AAR file not found after build!"
  err "   Expected location: $BUILD_AAR_FILE"
  err "   Build may have failed. Check: ${BUILD_DIR}/gradle-build.log"
  exit 1
fi

########################################
# Cleanup: Remove temporary directories
########################################
log "Cleaning up temporary directories..."

# Cleanup temp npm environment if used
if [ -d "$TEMP_NPM_DIR" ]; then
  log "  Removing temporary npm environment: $TEMP_NPM_DIR"
  rm -rf "$TEMP_NPM_DIR"
  log "  ✅ Cleaned up temporary npm environment"
fi

# Note: BUILD_DIR is kept for debugging purposes, but can be cleaned with: ./gradlew clean

########################################
# Step 5: Create README
########################################
log "Step 5: Creating README.md..."

cat > "${FRAMEWORK_DIR}/README.md" <<EOF
# ${FRAMEWORK_NAME}

Android AAR framework for ${MODULE_COMPONENT} React Native module.

## Overview

This framework contains:
- Pre-bundled JavaScript code (module-${MODULE_NAME}.bundle)
- Kotlin wrapper API for easy integration
- No Verdaccio or npm required at runtime

## Prerequisites

- **vsco-rn-host SDK must be added to the consuming app first** (provides React Native runtime)
- Android minSdkVersion: 23
- Android targetSdkVersion: 34
- Kotlin support

## Usage

### 1. Add vsco-rn-host SDK First (Required)

**Important:** The vsco-rn-host SDK must be added before this framework.

1. Publish vsco-rn-host to local Maven:
   \`\`\`bash
   npm run framework:android:aar:host:publish:local
   \`\`\`

2. Add to your app's \`build.gradle\`:
   \`\`\`gradle
   dependencies {
       implementation 'com.vscorp:vsco-rn-host-sdk:1.0.0'
   }
   \`\`\`

2. Add to your app's \`build.gradle\`:
   \`\`\`gradle
   repositories {
       flatDir {
           dirs 'libs'
       }
   }
   
   dependencies {
       implementation(name: 'react-android-0.81.5-release', ext: 'aar')
       implementation(name: 'hermes-android-0.81.5-release', ext: 'aar')
   }
   \`\`\`

**Note:** This framework automatically depends on React Native via vsco-rn-host SDK, which resolves dependencies from Maven Central.

### 2. Add This AAR

**Option A: Local AAR file**

\`\`\`gradle
dependencies {
    implementation files('libs/${AAR_NAME}')
}
\`\`\`

**Option B: Maven Local (if published)**

\`\`\`gradle
repositories {
    mavenLocal()
}

dependencies {
    implementation '${PACKAGE_NAME}:${FRAMEWORK_NAME}:1.0.0'
}
\`\`\`

### 3. Use in Code

\`\`\`kotlin
import ${PACKAGE_NAME}.${FRAMEWORK_NAME}

class ProductsActivity : AppCompatActivity() {
    private lateinit var reactRootView: ReactRootView
    private val reactInstanceManager get() =
        (application as ReactApplication).reactNativeHost.reactInstanceManager
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        val framework = ${FRAMEWORK_NAME}.getInstance()
        val bundlePath = framework.getBundlePath(this)
        val moduleName = framework.getModuleName()
        
        if (bundlePath != null) {
            reactRootView = ReactRootView(this)
            reactRootView.startReactApplication(reactInstanceManager, moduleName, null)
            setContentView(reactRootView)
        } else {
            // Handle error: bundle not found
            Log.e("ProductsActivity", "Bundle not found")
        }
    }
}
\`\`\`

**Or use the convenience method:**

\`\`\`kotlin
val framework = ${FRAMEWORK_NAME}.getInstance()
val rootView = framework.createView(
    context = this,
    reactInstanceManager = reactInstanceManager,
    initialProperties = null
)

if (rootView != null) {
    setContentView(rootView)
}
\`\`\`

## API

- \`getInstance(): ${FRAMEWORK_NAME}\` - Get singleton instance
- \`getBundlePath(context: Context): String?\` - Returns bundle file path
- \`getModuleName(): String\` - Returns registered module name
- \`createView(context: Context, reactInstanceManager: ReactInstanceManager, initialProperties: Bundle?): ReactRootView?\` - Creates React Native view

## Bundle

The JavaScript bundle is embedded in:
\`src/main/assets/module-${MODULE_NAME}.bundle\`

This bundle was created from the latest version published to Verdaccio.

## Version

Generated from: ${MODULE_PACKAGE}
Source: Verdaccio registry
EOF

########################################
# Summary
########################################
log "🎉 SUCCESS! ${FRAMEWORK_NAME} AAR framework generated"
echo ""
echo "📍 Location: $FRAMEWORK_DIR"
echo ""
echo "📦 Contents:"
echo "   • aars/${AAR_NAME} ✅ (Ready to use)"
echo "   • build.gradle"
echo "   • src/main/java/${PACKAGE_NAME//./\/}/${FRAMEWORK_NAME}.kt"
echo "   • src/main/assets/module-${MODULE_NAME}.bundle ($BUNDLE_SIZE)"
echo "   • README.md"
echo ""
echo "📝 Next steps:"
echo "   1. Ensure vsco-rn-host SDK is added to your Android app first (see README)"
echo "   2. Add this AAR to your app's dependencies:"
echo "      implementation files('libs/${AAR_NAME}')"
echo "   3. Use in code: import ${PACKAGE_NAME}.${FRAMEWORK_NAME}"
echo ""
echo "✅ Framework ready for distribution!"
echo "   • AAR file: ${AARS_DIR}/${AAR_NAME}"
echo "   • React Native types automatically available via dependency"
echo "   • No manual bundle copying needed"
echo "   • Plug-and-play similar to iOS module frameworks"
echo ""

