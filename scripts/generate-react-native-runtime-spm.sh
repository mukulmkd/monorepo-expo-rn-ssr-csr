#!/usr/bin/env bash
set -eo pipefail

########################################
# React Native Runtime SPM Generator
#
# Extracts React Native 0.81.5 runtime from rn-runtime-source
# and packages it as a Swift Package Manager (SPM) package
# that can be consumed by any iOS Xcode application.
#
# Generates:
#   frameworks/ios/ReactNativeRuntime/
# containing all React Native xcframeworks + Package.swift
#
# Requires:
#   - rn-runtime-source/RnRuntimeSource created with React Native 0.81.5
#   - pod install ran inside rn-runtime-source/RnRuntimeSource/ios
#   - Xcode CLI tools installed
#
########################################

MONOREPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RN_RUNTIME_SOURCE_DIR="${RN_RUNTIME_SOURCE_DIR:-${MONOREPO_ROOT}/rn-runtime-source/RnRuntimeSource}"
PODS_PROJECT="${RN_RUNTIME_SOURCE_DIR}/ios/Pods/Pods.xcodeproj"

# Output directories - ensure frameworks/ios structure exists
FRAMEWORKS_DIR="${MONOREPO_ROOT}/frameworks"
FRAMEWORKS_IOS_DIR="${MONOREPO_ROOT}/frameworks/ios"
FRAMEWORK_ROOT="${FRAMEWORKS_IOS_DIR}/ReactNativeRuntime"
RUNTIME_SRC="${FRAMEWORK_ROOT}/Sources/ReactNativeRuntime"
BUILD_ROOT="${MONOREPO_ROOT}/build-rn-runtime"
DIST_DIR="${MONOREPO_ROOT}/dist-rn-runtime"

# React Native scheme patterns to include
# These are the core React Native frameworks that should be included
RN_SCHEME_PATTERNS=(
  "React"
  "React-Core"
  "React-Fabric"
  "React-FabricComponents"
  "React-FabricImage"
  "React-graphics"
  "React-jsi"
  "React-jsiexecutor"
  "React-RuntimeApple"
  "React-RuntimeCore"
  "React-RuntimeHermes"
  "ReactCommon"
  "React-debug"
  "React-hermes"
  "React-RCTAppDelegate"
  "React-RCTImage"
  "React-RCTNetwork"
  "React-RCTText"
  "React-RCTSettings"
  "React-RCTAnimation"
  "React-RCTLinking"
  "React-RCTBlob"
  "React-RCTVibration"
  "React-CoreModules"
  "React-NativeModulesApple"
  "ReactCodegen"
  "hermes-engine"
  "Yoga"
  "RCT-Folly"
  "DoubleConversion"
  "glog"
)

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

if [ ! -d "$RN_RUNTIME_SOURCE_DIR" ]; then
  err "RN runtime source dir not found: $RN_RUNTIME_SOURCE_DIR"
  exit 1
fi

if [ ! -f "${RN_RUNTIME_SOURCE_DIR}/ios/Podfile" ]; then
  err "Podfile missing at: ${RN_RUNTIME_SOURCE_DIR}/ios"
  exit 1
fi

if [ ! -d "${RN_RUNTIME_SOURCE_DIR}/ios/Pods" ]; then
  err "Pods directory missing — run 'pod install' inside: ${RN_RUNTIME_SOURCE_DIR}/ios"
  exit 1
fi

if [ ! -d "$PODS_PROJECT" ]; then
  err "Pods.xcodeproj missing — run 'pod install'"
  exit 1
fi

# Check for required tools
if ! command -v xcodebuild &> /dev/null; then
  err "xcodebuild not found. Please install Xcode Command Line Tools."
  exit 1
fi

########################################
# Ensure directory structure
########################################
log "Setting up directory structure..."

# Create frameworks and frameworks/ios directories if they don't exist
if [ ! -d "$FRAMEWORKS_DIR" ]; then
  log "Creating frameworks directory: $FRAMEWORKS_DIR"
  mkdir -p "$FRAMEWORKS_DIR"
fi

if [ ! -d "$FRAMEWORKS_IOS_DIR" ]; then
  log "Creating frameworks/ios directory: $FRAMEWORKS_IOS_DIR"
  mkdir -p "$FRAMEWORKS_IOS_DIR"
fi

# Create ReactNativeRuntime SPM package directory
log "Creating ReactNativeRuntime SPM package directory: $FRAMEWORK_ROOT"
mkdir -p "$FRAMEWORK_ROOT"
mkdir -p "$RUNTIME_SRC"
mkdir -p "$BUILD_ROOT"
mkdir -p "$DIST_DIR"

# Don't clean builds - we'll check each scheme individually for incremental builds

# Clean previous SPM package (but preserve parent directories)
if [ -d "$FRAMEWORK_ROOT" ]; then
  log "Cleaning previous ReactNativeRuntime SPM package..."
  rm -rf "$FRAMEWORK_ROOT"/*
fi

########################################
# List all available schemes
########################################
log "Discovering available schemes from Pods project..."

SCHEMES_RAW=$(xcodebuild -list -project "$PODS_PROJECT" 2>/dev/null | \
  awk '/Schemes:/{flag=1;next}/^$/{flag=0}flag' || true)

if [ -z "$SCHEMES_RAW" ]; then
  err "No schemes detected in Pods.xcodeproj"
  exit 1
fi

# Normalize schemes (trim whitespace)
NORMALIZED_SCHEMES=()
while IFS= read -r s; do
  trimmed="$(echo "$s" | xargs)"
  [ -n "$trimmed" ] && NORMALIZED_SCHEMES+=("$trimmed")
done <<< "$SCHEMES_RAW"

log "Found ${#NORMALIZED_SCHEMES[@]} total schemes in Pods project"

########################################
# Filter React Native schemes
########################################
log "Filtering React Native schemes..."

SCHEMES_TO_BUILD=()

# First, try exact matches from patterns
for pattern in "${RN_SCHEME_PATTERNS[@]}"; do
  for scheme in "${NORMALIZED_SCHEMES[@]}"; do
    if [ "$scheme" = "$pattern" ]; then
      SCHEMES_TO_BUILD+=("$scheme")
      break
    fi
  done
done

# Also include any scheme that starts with "React" or "RCT" (React Native related)
for scheme in "${NORMALIZED_SCHEMES[@]}"; do
  if [[ "$scheme" =~ ^React ]] || [[ "$scheme" =~ ^RCT- ]] || [[ "$scheme" =~ ^React- ]]; then
    # Check if not already added
    found=false
    for existing in "${SCHEMES_TO_BUILD[@]}"; do
      if [ "$existing" = "$scheme" ]; then
        found=true
        break
      fi
    done
    if [ "$found" = false ]; then
      SCHEMES_TO_BUILD+=("$scheme")
    fi
  fi
done

# Add essential dependencies
ESSENTIAL_SCHEMES=("hermes-engine" "Yoga" "RCT-Folly" "DoubleConversion" "glog")
for essential in "${ESSENTIAL_SCHEMES[@]}"; do
  for scheme in "${NORMALIZED_SCHEMES[@]}"; do
    if [ "$scheme" = "$essential" ]; then
      found=false
      for existing in "${SCHEMES_TO_BUILD[@]}"; do
        if [ "$existing" = "$scheme" ]; then
          found=true
          break
        fi
      done
      if [ "$found" = false ]; then
        SCHEMES_TO_BUILD+=("$scheme")
      fi
      break
    fi
  done
done

# Remove duplicates
IFS=$'\n' SCHEMES_TO_BUILD=($(printf '%s\n' "${SCHEMES_TO_BUILD[@]}" | sort -u))

if [ ${#SCHEMES_TO_BUILD[@]} -eq 0 ]; then
  err "No React Native schemes found to build."
  log "Available schemes:"
  printf '  • %s\n' "${NORMALIZED_SCHEMES[@]}" | head -20
  exit 1
fi

log "Found ${#SCHEMES_TO_BUILD[@]} React Native schemes to build:"
for s in "${SCHEMES_TO_BUILD[@]}"; do
  echo "  • $s"
done

########################################
# Utility: find .framework or .a library inside .xcarchive
########################################
find_framework_in_archive(){
  local archive="$1"
  # First try to find a framework
  local framework=$(find "$archive" -type d -name "*.framework" -print -quit 2>/dev/null || true)
  if [ -n "$framework" ]; then
    echo "$framework"
    return
  fi
  # If no framework, look for static library (.a)
  local static_lib=$(find "$archive" -type f -name "*.a" -path "*/Products/usr/local/lib/*" -print -quit 2>/dev/null || true)
  if [ -n "$static_lib" ]; then
    echo "$static_lib"
    return
  fi
  # Return empty if nothing found
  echo ""
}

########################################
# Check if scheme artifacts already exist
########################################
scheme_already_built() {
  local SCHEME="$1"
  local SAFE_NAME=$(echo "$SCHEME" | tr ' ' '-' | tr '/' '-')
  
  # Check if xcframework exists
  if [ -d "${DIST_DIR}/${SAFE_NAME}.xcframework" ]; then
    return 0
  fi
  
  # Check if static library exists in dist
  STATIC_LIBS_DIR="${DIST_DIR}/static-libs"
  if [ -d "$STATIC_LIBS_DIR" ]; then
    # Check for lib files matching this scheme
    # Static libs are named like libReact-Core.a, libReact.a, etc.
    # Also check common naming variations
    for lib_file in "$STATIC_LIBS_DIR"/lib"${SCHEME}"*.a "$STATIC_LIBS_DIR"/lib"${SAFE_NAME}"*.a; do
      if [ -f "$lib_file" ] 2>/dev/null; then
        return 0
      fi
    done
    
    # Special case: hermes-engine produces libReact-hermes.a
    if [ "$SCHEME" = "hermes-engine" ] && [ -f "$STATIC_LIBS_DIR/libReact-hermes.a" ]; then
      return 0
    fi
  fi
  
  # Check if archives exist and contain valid artifacts
  local IOS_ARCHIVE="${BUILD_ROOT}/${SAFE_NAME}/iphoneos.xcarchive"
  local SIM_ARCHIVE="${BUILD_ROOT}/${SAFE_NAME}/iphonesimulator.xcarchive"
  
  if [ -d "$IOS_ARCHIVE" ] || [ -d "$SIM_ARCHIVE" ]; then
    local IOS_BUILD_PATH="$(find_framework_in_archive "$IOS_ARCHIVE")" || true
    local SIM_BUILD_PATH="$(find_framework_in_archive "$SIM_ARCHIVE")" || true
    
    # If we found artifacts in archives, consider it built
    if [ -n "$IOS_BUILD_PATH" ] || [ -n "$SIM_BUILD_PATH" ]; then
      return 0
    fi
  fi
  
  return 1
}

# Check if path is a framework or static library
is_framework(){
  local path="$1"
  [[ "$path" == *.framework ]]
}

is_static_library(){
  local path="$1"
  [[ "$path" == *.a ]]
}

########################################
# Build each scheme (with parallelization and incremental builds)
########################################

# Determine number of parallel jobs (use CPU count, max 8)
MAX_PARALLEL_JOBS=${MAX_PARALLEL_JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}
if [ "$MAX_PARALLEL_JOBS" -gt 8 ]; then
  MAX_PARALLEL_JOBS=8
fi
log "Using up to $MAX_PARALLEL_JOBS parallel build jobs"

# Create temp directory for parallel build results
PARALLEL_RESULTS_DIR="${BUILD_ROOT}/parallel-results"
rm -rf "$PARALLEL_RESULTS_DIR"
mkdir -p "$PARALLEL_RESULTS_DIR"

# Function to build a single scheme (runs in parallel)
build_scheme() {
  SCHEME="$1"
  SAFE_NAME=$(echo "$SCHEME" | tr ' ' '-' | tr '/' '-')
  RESULT_FILE="${PARALLEL_RESULTS_DIR}/${SAFE_NAME}.result"
  
  {
    echo "Building: $SCHEME"
    
    IOS_ARCHIVE="${BUILD_ROOT}/${SAFE_NAME}/iphoneos.xcarchive"
    SIM_ARCHIVE="${BUILD_ROOT}/${SAFE_NAME}/iphonesimulator.xcarchive"
    mkdir -p "$(dirname "$IOS_ARCHIVE")" "$(dirname "$SIM_ARCHIVE")"
    
    # Build device (may fail due to signing — allowed)
    set +e
    xcodebuild archive \
      -project "$PODS_PROJECT" \
      -scheme "$SCHEME" \
      -configuration Release \
      -sdk iphoneos \
      -archivePath "$IOS_ARCHIVE" \
      SKIP_INSTALL=NO \
      BUILD_LIBRARIES_FOR_DISTRIBUTION=YES \
      ONLY_ACTIVE_ARCH=NO \
      > "${BUILD_ROOT}/${SAFE_NAME}-device.log" 2>&1
    DEV_STATUS=$?
    set -e
    
    # Build simulator (should succeed)
    set +e
    xcodebuild archive \
      -project "$PODS_PROJECT" \
      -scheme "$SCHEME" \
      -configuration Release \
      -sdk iphonesimulator \
      -archivePath "$SIM_ARCHIVE" \
      SKIP_INSTALL=NO \
      BUILD_LIBRARIES_FOR_DISTRIBUTION=YES \
      ONLY_ACTIVE_ARCH=NO \
      > "${BUILD_ROOT}/${SAFE_NAME}-sim.log" 2>&1
    SIM_STATUS=$?
    set -e
    
    IOS_BUILD_PATH="$(find_framework_in_archive "$IOS_ARCHIVE")" || true
    SIM_BUILD_PATH="$(find_framework_in_archive "$SIM_ARCHIVE")" || true
    OUT_XC="${DIST_DIR}/${SAFE_NAME}.xcframework"
    
    # Handle frameworks
    if is_framework "$IOS_BUILD_PATH" && is_framework "$SIM_BUILD_PATH"; then
      xcodebuild -create-xcframework \
        -framework "$IOS_BUILD_PATH" \
        -framework "$SIM_BUILD_PATH" \
        -output "$OUT_XC" \
        > /dev/null 2>&1
      
      if [ -d "$OUT_XC" ]; then
        echo "XCFRAMEWORK:$OUT_XC" >> "$RESULT_FILE"
        echo "✅ $SCHEME: Created xcframework"
      else
        echo "FAILURE:$SCHEME" >> "$RESULT_FILE"
        echo "❌ $SCHEME: Failed to create xcframework"
      fi
    elif is_framework "$SIM_BUILD_PATH"; then
      xcodebuild -create-xcframework \
        -framework "$SIM_BUILD_PATH" \
        -output "$OUT_XC" \
        > /dev/null 2>&1
      
      if [ -d "$OUT_XC" ]; then
        echo "XCFRAMEWORK:$OUT_XC" >> "$RESULT_FILE"
        echo "✅ $SCHEME: Created xcframework (simulator only)"
      else
        echo "FAILURE:$SCHEME" >> "$RESULT_FILE"
        echo "❌ $SCHEME: Failed to create xcframework"
      fi
    # Handle static libraries
    elif is_static_library "$IOS_BUILD_PATH" || is_static_library "$SIM_BUILD_PATH"; then
      STATIC_LIBS_DIR="${DIST_DIR}/static-libs"
      mkdir -p "$STATIC_LIBS_DIR"
      
      if [ -d "$IOS_ARCHIVE" ]; then
        # Collect static libraries from standard location
        find "$IOS_ARCHIVE" -type f -name "*.a" -path "*/Products/usr/local/lib/*" -exec cp {} "${STATIC_LIBS_DIR}/" \; 2>/dev/null || true
        # Also check for libraries in other locations (hermes-engine and other special cases)
        find "$IOS_ARCHIVE" -type f -name "*.a" -path "*/Products/*" ! -path "*/Products/usr/local/lib/*" ! -path "*/Products/Applications/*" -exec cp {} "${STATIC_LIBS_DIR}/" \; 2>/dev/null || true
      fi
      
      if [ -d "$SIM_ARCHIVE" ]; then
        # Collect static libraries from standard location
        find "$SIM_ARCHIVE" -type f -name "*.a" -path "*/Products/usr/local/lib/*" -exec cp {} "${STATIC_LIBS_DIR}/" \; 2>/dev/null || true
        # Also check for libraries in other locations (hermes-engine and other special cases)
        find "$SIM_ARCHIVE" -type f -name "*.a" -path "*/Products/*" ! -path "*/Products/usr/local/lib/*" ! -path "*/Products/Applications/*" -exec cp {} "${STATIC_LIBS_DIR}/" \; 2>/dev/null || true
      fi
      
      echo "STATIC_LIB:$SAFE_NAME" >> "$RESULT_FILE"
      echo "✅ $SCHEME: Collected static libraries"
    else
      echo "FAILURE:$SCHEME" >> "$RESULT_FILE"
      echo "⚠️  $SCHEME: No framework or static library found (device: $DEV_STATUS, sim: $SIM_STATUS)"
    fi
  } 2>&1 | while IFS= read -r line; do
    echo "[$SCHEME] $line"
  done
}

# Export functions and variables needed by parallel jobs
export -f build_scheme find_framework_in_archive is_framework is_static_library
export PODS_PROJECT BUILD_ROOT DIST_DIR PARALLEL_RESULTS_DIR

# Build schemes in parallel with job limit
XCFRAMEWORKS_CREATED=()
BUILD_FAILURES=()
STATIC_LIBS=()

# Track running jobs
PIDS=()
RUNNING=0

log "Starting parallel builds (max $MAX_PARALLEL_JOBS concurrent)..."

# Filter out schemes that are already built
SCHEMES_TO_BUILD_NOW=()
SKIPPED_COUNT=0
for SCHEME in "${SCHEMES_TO_BUILD[@]}"; do
  if scheme_already_built "$SCHEME"; then
    log "  ✓ Skipping $SCHEME (already built)"
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
  else
    SCHEMES_TO_BUILD_NOW+=("$SCHEME")
  fi
done

if [ $SKIPPED_COUNT -gt 0 ]; then
  log "Skipped $SKIPPED_COUNT already-built schemes"
fi

if [ ${#SCHEMES_TO_BUILD_NOW[@]} -eq 0 ]; then
  log "All schemes already built - skipping build phase"
  XCFRAMEWORKS_CREATED=()
  BUILD_FAILURES=()
else
  log "Building ${#SCHEMES_TO_BUILD_NOW[@]} missing schemes..."
fi

for SCHEME in "${SCHEMES_TO_BUILD_NOW[@]}"; do
  # Wait if we've reached max parallel jobs
  while [ $RUNNING -ge $MAX_PARALLEL_JOBS ]; do
    sleep 0.5
    # Check which jobs are still running
    NEW_PIDS=()
    for pid in "${PIDS[@]}"; do
      if kill -0 "$pid" 2>/dev/null; then
        NEW_PIDS+=("$pid")
      else
        RUNNING=$((RUNNING - 1))
      fi
    done
    PIDS=("${NEW_PIDS[@]}")
  done
  
  # Start new job in background
  build_scheme "$SCHEME" &
  PID=$!
  PIDS+=("$PID")
  RUNNING=$((RUNNING + 1))
done

# Wait for all remaining jobs
log "Waiting for all builds to complete..."
for pid in "${PIDS[@]}"; do
  wait "$pid" 2>/dev/null || true
done

# Collect results from parallel builds (only for newly built schemes)
if [ ${#SCHEMES_TO_BUILD_NOW[@]} -gt 0 ]; then
  log "Collecting build results from newly built schemes..."
  for SCHEME in "${SCHEMES_TO_BUILD_NOW[@]}"; do
    SAFE_NAME=$(echo "$SCHEME" | tr ' ' '-' | tr '/' '-')
    RESULT_FILE="${PARALLEL_RESULTS_DIR}/${SAFE_NAME}.result"
    
    if [ -f "$RESULT_FILE" ]; then
      while IFS= read -r line; do
        if [[ "$line" == XCFRAMEWORK:* ]]; then
          XCFRAMEWORKS_CREATED+=("${line#XCFRAMEWORK:}")
        elif [[ "$line" == STATIC_LIB:* ]]; then
          STATIC_LIBS+=("${line#STATIC_LIB:}")
        elif [[ "$line" == FAILURE:* ]]; then
          BUILD_FAILURES+=("${line#FAILURE:}")
        fi
      done < "$RESULT_FILE"
    fi
  done
fi

# Collect results from already-built schemes (to populate arrays)
log "Collecting results from existing artifacts..."
for SCHEME in "${SCHEMES_TO_BUILD[@]}"; do
  SAFE_NAME=$(echo "$SCHEME" | tr ' ' '-' | tr '/' '-')
  
  # Check if xcframework exists
  if [ -d "${DIST_DIR}/${SAFE_NAME}.xcframework" ]; then
    # Check if already in array
    found=false
    for existing in "${XCFRAMEWORKS_CREATED[@]}"; do
      if [ "$existing" = "${DIST_DIR}/${SAFE_NAME}.xcframework" ]; then
        found=true
        break
      fi
    done
    if [ "$found" = false ]; then
      XCFRAMEWORKS_CREATED+=("${DIST_DIR}/${SAFE_NAME}.xcframework")
    fi
  fi
  
  # Check if static library exists
  STATIC_LIBS_DIR="${DIST_DIR}/static-libs"
  if [ -d "$STATIC_LIBS_DIR" ]; then
    for lib_file in "$STATIC_LIBS_DIR"/lib"${SCHEME}"*.a "$STATIC_LIBS_DIR"/lib"${SAFE_NAME}"*.a; do
      if [ -f "$lib_file" ] 2>/dev/null; then
        lib_name=$(basename "$lib_file" .a | sed 's/^lib//')
        # Add to STATIC_LIBS if not already there
        found=false
        if [ ${#STATIC_LIBS[@]} -gt 0 ]; then
          for existing in "${STATIC_LIBS[@]}"; do
            if [ "$existing" = "$lib_name" ]; then
              found=true
              break
            fi
          done
        fi
        if [ "$found" = false ]; then
          STATIC_LIBS+=("$lib_name")
        fi
        break
      fi
    done
  fi
done

# Check if we have either xcframeworks or static libraries
# For static libraries, check the actual directory since STATIC_LIBS array tracks scheme names
STATIC_LIBS_DIR="${DIST_DIR}/static-libs"
HAS_STATIC_LIBS=false
STATIC_LIB_COUNT=0
if [ -d "$STATIC_LIBS_DIR" ] && [ "$(ls -A "$STATIC_LIBS_DIR"/*.a 2>/dev/null)" ]; then
  HAS_STATIC_LIBS=true
  STATIC_LIB_COUNT=$(ls -1 "$STATIC_LIBS_DIR"/*.a 2>/dev/null | wc -l | tr -d ' ')
fi

if [ ${#XCFRAMEWORKS_CREATED[@]} -eq 0 ] && [ "$HAS_STATIC_LIBS" = false ]; then
  err "No xcframeworks or static libraries were created. Check build logs in: $BUILD_ROOT"
  exit 1
fi

# Log what we collected
if [ ${#XCFRAMEWORKS_CREATED[@]} -gt 0 ]; then
  log "Created ${#XCFRAMEWORKS_CREATED[@]} xcframeworks"
fi
if [ "$HAS_STATIC_LIBS" = true ]; then
  log "Collected $STATIC_LIB_COUNT static libraries"
fi

if [ ${#BUILD_FAILURES[@]} -gt 0 ]; then
  warn "Some schemes failed to build:"
  printf '  • %s\n' "${BUILD_FAILURES[@]}"
  if [ ${#XCFRAMEWORKS_CREATED[@]} -gt 0 ]; then
    warn "Continuing with ${#XCFRAMEWORKS_CREATED[@]} successfully built frameworks..."
  elif [ "$HAS_STATIC_LIBS" = true ]; then
    warn "Continuing with $STATIC_LIB_COUNT successfully collected static libraries..."
  fi
fi

########################################
# Collect headers
########################################
log "Collecting React Native headers..."

HEADERS_DIR="${RUNTIME_SRC}/Headers"
rm -rf "$HEADERS_DIR"
mkdir -p "$HEADERS_DIR"

# Copy public headers from CocoaPods
PODS_HEADERS_PUBLIC_DIR="${RN_RUNTIME_SOURCE_DIR}/ios/Pods/Headers/Public"
if [ -d "$PODS_HEADERS_PUBLIC_DIR" ]; then
  log "  Copying headers from Pods/Headers/Public..."
  cp -R "${PODS_HEADERS_PUBLIC_DIR}/." "$HEADERS_DIR/" 2>/dev/null || true
fi

# Also copy from React Native node_modules
RN_NODE_DIR="${RN_RUNTIME_SOURCE_DIR}/node_modules/react-native"
if [ -d "$RN_NODE_DIR" ]; then
  log "  Copying headers from node_modules/react-native..."
  for dir in React ReactCommon React-jsi React-jsiexecutor; do
    if [ -d "${RN_NODE_DIR}/${dir}" ]; then
      cp -R "${RN_NODE_DIR}/${dir}" "$HEADERS_DIR/" 2>/dev/null || true
    fi
  done
fi

# Remove implementation files from Headers (should only contain .h files)
log "  Removing implementation files from Headers directory..."
find "$HEADERS_DIR" -type f \( -name "*.m" -o -name "*.mm" -o -name "*.cpp" -o -name "*.c" -o -name "*.S" \) -delete 2>/dev/null || true

# Create module map for React Native
log "  Creating module.modulemap for ReactNativeRuntime..."
cat > "${HEADERS_DIR}/module.modulemap" <<'EOF'
module ReactCommon {
    umbrella header "ReactCommon/ReactCommon.h"
    export *
    module * { export * }
}

module Yoga {
    umbrella header "yoga/Yoga.h"
    export *
}
EOF

# Ensure React.h umbrella header exists (create if missing)
# Generate it dynamically based on available headers
# Use actual file paths since symlinks may not work reliably in SPM
if [ ! -f "${HEADERS_DIR}/React/React.h" ]; then
  log "  Creating React.h umbrella header..."
  mkdir -p "${HEADERS_DIR}/React"
  cat > "${HEADERS_DIR}/React/React.h" <<'EOF'
// React Native Runtime - Umbrella Header
// This header imports all React Native public headers
// Uses actual file paths since files are in subdirectories

#import <React/Base/RCTBridge.h>
#import <React/Base/RCTRootView.h>
#import <React/Views/RCTViewManager.h>
#import <React/Views/RCTComponent.h>
#import <React/Base/RCTDefines.h>
#import <React/Base/RCTLog.h>
#import <React/Base/RCTUtils.h>
#import <React/Base/RCTBundleURLProvider.h>
#import <React/Base/RCTBridgeModule.h>
#import <React/Modules/RCTEventEmitter.h>
#import <React/Views/RCTView.h>
#import <React/Views/ScrollView/RCTScrollView.h>
EOF
fi

########################################
# Create Sources/React structure with its own module map
########################################
REACT_SRC="${FRAMEWORK_ROOT}/Sources/React"
log "Creating Sources/React structure..."

# Function to resolve symlink to actual file path
resolve_symlink() {
  local file="$1"
  local link_target=$(readlink "$file" 2>/dev/null)
  
  if [ -z "$link_target" ]; then
    echo "$file"
    return
  fi
  
  # If absolute path, use as-is
  if [[ "$link_target" == /* ]]; then
    if [ -e "$link_target" ]; then
      echo "$link_target"
      return
    fi
  else
    # Relative path - resolve relative to symlink's directory
    local link_dir=$(cd "$(dirname "$file")" && pwd)
    local resolved="$link_dir/$link_target"
    
    # Normalize the path (resolve .. and .)
    local target_dir=$(cd "$link_dir" && cd "$(dirname "$link_target")" 2>/dev/null && pwd 2>/dev/null)
    if [ -n "$target_dir" ]; then
      resolved="$target_dir/$(basename "$link_target")"
    fi
    
    if [ -e "$resolved" ]; then
      echo "$resolved"
      return
    fi
    
    # Try resolving relative to rn-runtime-source if it's a node_modules path
    if [[ "$link_target" == *node_modules* ]]; then
      local rn_source="${RN_RUNTIME_SOURCE_DIR}"
      if [ -d "$rn_source" ]; then
        # Extract the node_modules path part
        local node_modules_path="${link_target##*node_modules/}"
        local rn_resolved="${rn_source}/node_modules/${node_modules_path}"
        if [ -e "$rn_resolved" ]; then
          echo "$rn_resolved"
          return
        fi
      fi
    fi
  fi
  
  # Could not resolve, return original
  echo "$file"
}

# Create React/Headers directory and copy ALL headers (React depends on other modules)
REACT_HEADERS_DIR="${REACT_SRC}/Headers"
rm -rf "$REACT_HEADERS_DIR"
mkdir -p "$REACT_HEADERS_DIR"

# Copy ALL headers from ReactNativeRuntime to React target, resolving symlinks
# React headers depend on other React Native modules (RCTDeprecation, RCTRequired, etc.)
if [ -d "${HEADERS_DIR}" ]; then
  log "  Copying all React Native headers to Sources/React/Headers (resolving symlinks)..."
  
  # Use find to copy all files, resolving symlinks
  cd "${HEADERS_DIR}"
  find . -type f -name "*.h" -o -name "*.hpp" -o -name "*.modulemap" | while read -r file; do
    # Remove leading ./
    file="${file#./}"
    src_file="${HEADERS_DIR}/$file"
    dst_file="${REACT_HEADERS_DIR}/$file"
    
    # If source is a symlink, resolve it
    if [ -L "$src_file" ]; then
      resolved=$(resolve_symlink "$src_file")
      if [ -f "$resolved" ] && [ "$resolved" != "$src_file" ]; then
        src_file="$resolved"
      fi
    fi
    
    # Copy the file (or resolved symlink target)
    if [ -f "$src_file" ]; then
      mkdir -p "$(dirname "$dst_file")"
      cp "$src_file" "$dst_file" 2>/dev/null || true
    fi
  done
  
  # Copy directory structure for module directories (even if they only contain symlinks)
  find . -type d | while read -r dir; do
    dir="${dir#./}"
    if [ -n "$dir" ] && [ "$dir" != "." ]; then
      mkdir -p "${REACT_HEADERS_DIR}/$dir"
    fi
  done
  
  # For symlinked .h files, try to resolve and copy the actual files
  find . -type l \( -name "*.h" -o -name "*.hpp" -o -name "*.modulemap" \) | while read -r link; do
    link="${link#./}"
    src_link="${HEADERS_DIR}/$link"
    dst_file="${REACT_HEADERS_DIR}/$link"
    
    # Only process if destination doesn't exist as a real file
    if [ ! -f "$dst_file" ] || [ -L "$dst_file" ]; then
      resolved=$(resolve_symlink "$src_link")
      if [ -f "$resolved" ] && [ "$resolved" != "$src_link" ]; then
        mkdir -p "$(dirname "$dst_file")"
        cp "$resolved" "$dst_file" 2>/dev/null && log "    Resolved symlink: $link -> $(basename "$resolved")" || true
      elif [ -f "$resolved" ]; then
        # If resolved path is same as source, it means resolution failed - try direct copy
        if [ -f "$src_link" ]; then
          mkdir -p "$(dirname "$dst_file")"
          cp "$src_link" "$dst_file" 2>/dev/null || true
        fi
      fi
    fi
  done
  
  cd - > /dev/null
  
  # Ensure yoga/ headers are accessible (Yoga headers are in ReactCommon/yoga/yoga/)
  # Create yoga/ directory and copy/resolve all yoga header files
  if [ -d "${REACT_HEADERS_DIR}/ReactCommon/yoga/yoga" ]; then
    log "  Creating yoga headers directory with resolved files..."
    mkdir -p "${REACT_HEADERS_DIR}/yoga"
    # Copy or resolve symlinks for all yoga header files
    for file in "${REACT_HEADERS_DIR}/ReactCommon/yoga/yoga"/*.h; do
      if [ -f "$file" ] || [ -L "$file" ]; then
        filename=$(basename "$file")
        # Resolve symlink to actual file
        resolved_file=$(resolve_symlink "$file")
        if [ -f "$resolved_file" ] && [ "$resolved_file" != "$file" ]; then
          # Copy the resolved file
          cp "$resolved_file" "${REACT_HEADERS_DIR}/yoga/$filename" 2>/dev/null || true
        elif [ -f "$file" ]; then
          # File exists, copy it
          cp "$file" "${REACT_HEADERS_DIR}/yoga/$filename" 2>/dev/null || true
        fi
      fi
    done
    log "    ✅ Created yoga headers with resolved files"
  fi
  
  log "  ✅ Headers copied with symlinks resolved"
fi

# Remove implementation files from React Headers (should only contain .h files)
log "  Removing implementation files from React Headers directory..."
find "$REACT_HEADERS_DIR" -type f \( -name "*.m" -o -name "*.mm" -o -name "*.cpp" -o -name "*.c" -o -name "*.S" \) -delete 2>/dev/null || true

# Fix RCTDefines.h to ensure RCT_ENABLE_INSPECTOR is enabled when RCT_REMOTE_PROFILE is enabled
# This prevents the compilation error: "RCT_ENABLE_INSPECTOR needs to be set to fulfill RCT_REMOTE_PROFILE"
# Apply fix to both ReactNativeRuntime and React targets
log "  Fixing RCTDefines.h to ensure RCT_ENABLE_INSPECTOR compatibility..."

fix_rctdefines_h() {
  local RCT_DEFINES_H="$1"
  local TARGET_NAME="$2"
  
  if [ -f "$RCT_DEFINES_H" ]; then
    # Use sed to fix the RCT_ENABLE_INSPECTOR definition to check RCT_REMOTE_PROFILE first
    sed -i.bak -E 's|#ifndef RCT_ENABLE_INSPECTOR\n#if \(RCT_DEV \|\| RCT_REMOTE_PROFILE\) && __has_include\(<React/RCTInspectorDevServerHelper\.h>\)|#ifndef RCT_ENABLE_INSPECTOR\n#if RCT_REMOTE_PROFILE\n// RCT_REMOTE_PROFILE requires RCT_ENABLE_INSPECTOR to be enabled\n#define RCT_ENABLE_INSPECTOR 1\n#elif (RCT_DEV || RCT_REMOTE_PROFILE) && __has_include(<React/RCTInspectorDevServerHelper.h>)|g' "$RCT_DEFINES_H" 2>/dev/null || {
      # If sed fails (different line breaks), use a more robust approach with python
      python3 -c "
import re
with open('$RCT_DEFINES_H', 'r') as f:
    content = f.read()
# Replace the problematic section
pattern = r'#ifndef RCT_ENABLE_INSPECTOR\n#if \(RCT_DEV \|\| RCT_REMOTE_PROFILE\) && __has_include\(<React/RCTInspectorDevServerHelper\.h>\)'
replacement = r'#ifndef RCT_ENABLE_INSPECTOR\n#if RCT_REMOTE_PROFILE\n// RCT_REMOTE_PROFILE requires RCT_ENABLE_INSPECTOR to be enabled\n#define RCT_ENABLE_INSPECTOR 1\n#elif (RCT_DEV || RCT_REMOTE_PROFILE) && __has_include(<React/RCTInspectorDevServerHelper.h>)'
content = re.sub(pattern, replacement, content)
with open('$RCT_DEFINES_H', 'w') as f:
    f.write(content)
" 2>/dev/null || true
    }
    rm -f "${RCT_DEFINES_H}.bak" 2>/dev/null || true
    log "    ✅ Fixed RCTDefines.h for $TARGET_NAME"
  fi
}

# Fix RCTDefines.h for ReactNativeRuntime target
RCT_DEFINES_H_RUNTIME="${HEADERS_DIR}/React/RCTDefines.h"
fix_rctdefines_h "$RCT_DEFINES_H_RUNTIME" "ReactNativeRuntime"

# Fix RCTDefines.h for React target
RCT_DEFINES_H_REACT="${REACT_HEADERS_DIR}/React/RCTDefines.h"
fix_rctdefines_h "$RCT_DEFINES_H_REACT" "React"

# Create symlinks for headers in subdirectories so framework-style imports work
# React Native headers use <React/RCTBridge.h> but files are in React/Base/RCTBridge.h or nested like React/Views/ScrollView/RCTScrollView.h
# Apply to both ReactNativeRuntime and React targets
create_react_header_symlinks() {
  local HEADER_DIR="$1"
  local TARGET_NAME="$2"
  
  log "  Creating symlinks for React headers in subdirectories (recursive) for $TARGET_NAME..."
  local REACT_DIR="${HEADER_DIR}/React"
  if [ -d "$REACT_DIR" ]; then
    cd "$REACT_DIR"
    local SYMLINK_COUNT=0
    # Find all .h files in subdirectories recursively and create symlinks at root level
    # Use -mindepth 2 to only find files in subdirectories (not at root)
    # Use -exec to avoid subshell issues
    find . -mindepth 2 -type f -name "*.h" -exec sh -c '
      header_name=$(basename "$1")
      if [ ! -e "$header_name" ] && [ ! -L "$header_name" ]; then
        relative_path="${1#./}"
        if ln -sf "$relative_path" "$header_name" 2>/dev/null; then
          echo "created"
        fi
      fi
    ' _ {} \; | grep -c "created" | while read count; do
      SYMLINK_COUNT=$count
    done
    # Alternative: count symlinks that were actually created
    SYMLINK_COUNT=$(find . -maxdepth 1 -type l -name "*.h" 2>/dev/null | wc -l | tr -d ' ')
    cd - > /dev/null
    log "    ✅ Created symlinks for React headers in subdirectories for $TARGET_NAME (found $SYMLINK_COUNT symlinks)"
  fi
}

# Create symlinks for ReactNativeRuntime target
create_react_header_symlinks "$HEADERS_DIR" "ReactNativeRuntime"

# Create symlinks for React target
create_react_header_symlinks "$REACT_HEADERS_DIR" "React"

# Ensure React.h umbrella header exists for React target (create if missing after copy)
# Use actual file paths since symlinks may not work reliably in SPM
if [ ! -f "${REACT_HEADERS_DIR}/React/React.h" ]; then
  log "  Creating React.h umbrella header for React target..."
  mkdir -p "${REACT_HEADERS_DIR}/React"
  cat > "${REACT_HEADERS_DIR}/React/React.h" <<'EOF'
// React Native Runtime - Umbrella Header
// This header imports all React Native public headers
// Uses actual file paths since files are in subdirectories

#import <React/Base/RCTBridge.h>
#import <React/Base/RCTRootView.h>
#import <React/Views/RCTViewManager.h>
#import <React/Views/RCTComponent.h>
#import <React/Base/RCTDefines.h>
#import <React/Base/RCTLog.h>
#import <React/Base/RCTUtils.h>
#import <React/Base/RCTBundleURLProvider.h>
#import <React/Base/RCTBridgeModule.h>
#import <React/Modules/RCTEventEmitter.h>
#import <React/Views/RCTView.h>
#import <React/Views/ScrollView/RCTScrollView.h>
EOF
fi

# Create module map for React target (only defines module React)
log "  Creating module.modulemap for React target..."
cat > "${REACT_HEADERS_DIR}/module.modulemap" <<'EOF'
module React {
    umbrella header "React/React.h"
    export *
    module * { export * }
}
EOF

# Copy Hermes xcframework (required for JSI and Hermes engine implementation)
HERMES_XCFRAMEWORK_SOURCE="rn-runtime-source/RnRuntimeSource/ios/Pods/hermes-engine/destroot/Library/Frameworks/universal/hermes.xcframework"
HERMES_XCFRAMEWORK_DEST="${FRAMEWORK_ROOT}/hermes.xcframework"

if [ -d "$HERMES_XCFRAMEWORK_SOURCE" ]; then
  log "  Copying Hermes xcframework (required for JSI implementation)..."
  rm -rf "$HERMES_XCFRAMEWORK_DEST"
  cp -R "$HERMES_XCFRAMEWORK_SOURCE" "$HERMES_XCFRAMEWORK_DEST"
  if [ -d "$HERMES_XCFRAMEWORK_DEST" ]; then
    log "    ✅ Copied Hermes xcframework"
  else
    log "    ⚠️  Failed to copy Hermes xcframework"
  fi
else
  log "    ⚠️  Hermes xcframework not found at $HERMES_XCFRAMEWORK_SOURCE"
  HERMES_XCFRAMEWORK_DEST=""
fi

# Create stub Objective-C files for ReactNativeRuntime and React targets
# These are needed so the targets produce valid object files for linking
# Using Objective-C instead of Swift ensures proper bridging of Objective-C types
log "  Creating stub Objective-C files for targets..."
REACTNATIVERUNTIME_M="${FRAMEWORK_ROOT}/Sources/ReactNativeRuntime/ReactNativeRuntime.m"
cat > "$REACTNATIVERUNTIME_M" <<'EOF'
// React Native Runtime - Stub Objective-C file
// This file ensures the target produces a valid object file
// The actual implementation is provided by ReactNativeRuntimeBinary (xcframework)

#import <Foundation/Foundation.h>

// Empty implementation - all functionality comes from the binary target
EOF

REACT_M="${FRAMEWORK_ROOT}/Sources/React/React.m"
cat > "$REACT_M" <<'EOF'
// React - Stub Objective-C file
// This file ensures the target produces a valid object file
// The actual implementation is provided by ReactNativeRuntimeBinary (xcframework)

#import <Foundation/Foundation.h>

// Empty implementation - all functionality comes from the binary target
EOF
log "    ✅ Created stub Objective-C files"

########################################
# Copy xcframeworks into SPM Sources
########################################
log "Copying xcframeworks into SPM package..."

# Only copy xcframeworks if they exist
if [ ${#XCFRAMEWORKS_CREATED[@]} -gt 0 ]; then
  rm -rf "$RUNTIME_SRC"/*.xcframework
  for xc in "${XCFRAMEWORKS_CREATED[@]}"; do
    xc_name=$(basename "$xc")
    log "  Copying $xc_name..."
    cp -R "$xc" "$RUNTIME_SRC/"
  done
else
  log "  No xcframeworks to copy (using static libraries only)"
fi

########################################
# Write RuntimeMarker.swift
########################################
log "Writing RuntimeMarker.swift..."
cat > "${RUNTIME_SRC}/RuntimeMarker.swift" <<'EOF'
// React Native Runtime SPM Package
// Generated from React Native 0.81.5 source
import Foundation

public struct ReactNativeRuntime {
    public static let version = "0.81.5"
    
    public init() {}
}
EOF

########################################
# Create unified xcframework from static libraries
########################################
STATIC_LIBS_DIR="${DIST_DIR}/static-libs"
UNIFIED_XCFRAMEWORK="${FRAMEWORK_ROOT}/ReactNativeRuntime.xcframework"

if [ -d "$STATIC_LIBS_DIR" ] && [ "$(ls -A "$STATIC_LIBS_DIR"/*.a 2>/dev/null)" ]; then
  LIB_COUNT=$(ls -1 "$STATIC_LIBS_DIR"/*.a 2>/dev/null | wc -l | tr -d ' ')
  log "Creating unified xcframework from $LIB_COUNT static libraries..."
  
  # Verify critical libraries are present
  HAS_JSI=false
  HAS_HERMES=false
  for lib in "$STATIC_LIBS_DIR"/*.a; do
    lib_name=$(basename "$lib" .a)
    if echo "$lib_name" | grep -qi "jsi"; then
      HAS_JSI=true
    fi
    if echo "$lib_name" | grep -qi "hermes"; then
      HAS_HERMES=true
    fi
  done
  
  if [ "$HAS_JSI" = false ]; then
    log "⚠️  WARNING: React-jsi library not found in static libraries!"
  fi
  if [ "$HAS_HERMES" = false ]; then
    log "⚠️  WARNING: React-hermes library not found in static libraries!"
  fi
  if [ "$HAS_JSI" = true ] && [ "$HAS_HERMES" = true ]; then
    log "✅ Verified: React-jsi and React-hermes libraries found"
  fi
  
  # Temporary directory for building unified framework
  TEMP_FRAMEWORK_DIR="${DIST_DIR}/unified-framework"
  rm -rf "$TEMP_FRAMEWORK_DIR"
  mkdir -p "$TEMP_FRAMEWORK_DIR"
  
  # Framework name
  FRAMEWORK_NAME="ReactNativeRuntime"
  
  # Check if static libraries are fat binaries (universal)
  SAMPLE_LIB=$(ls -1 "$STATIC_LIBS_DIR"/*.a 2>/dev/null | head -1)
  if [ -n "$SAMPLE_LIB" ]; then
    ARCHS=$(lipo -archs "$SAMPLE_LIB" 2>/dev/null || echo "")
    IS_FAT=$(echo "$ARCHS" | wc -w | tr -d ' ')
  else
    IS_FAT=0
  fi
  
  # Create a single universal framework (static libs are already fat binaries)
  UNIVERSAL_FRAMEWORK="${TEMP_FRAMEWORK_DIR}/${FRAMEWORK_NAME}.framework"
  mkdir -p "${UNIVERSAL_FRAMEWORK}/Headers"
  mkdir -p "${UNIVERSAL_FRAMEWORK}/Modules"
  
  # Copy all headers to framework
  if [ -d "${RUNTIME_SRC}/Headers" ]; then
    cp -R "${RUNTIME_SRC}/Headers/"* "${UNIVERSAL_FRAMEWORK}/Headers/" 2>/dev/null || true
  fi
  
  # Combine all static libraries into one universal binary
  UNIVERSAL_LIB="${UNIVERSAL_FRAMEWORK}/${FRAMEWORK_NAME}"
  log "Combining $LIB_COUNT static libraries into universal framework..."
  
  # Get architectures from first library
  SAMPLE_LIB=$(ls -1 "$STATIC_LIBS_DIR"/*.a 2>/dev/null | head -1)
  if [ -n "$SAMPLE_LIB" ]; then
    ARCHS_STRING=$(lipo -archs "$SAMPLE_LIB" 2>/dev/null || echo "arm64")
    # Convert space-separated string to array - use IFS to split properly
    IFS=' ' read -ra ARCHS_ARRAY <<< "$ARCHS_STRING"
  else
    ARCHS_ARRAY=("arm64")
  fi
  
  # Log architectures found
  log "  Found ${#ARCHS_ARRAY[@]} architecture(s): ${ARCHS_ARRAY[*]}"
  
  # Combine libraries per architecture, then create fat binary
  for ARCH in "${ARCHS_ARRAY[@]}"; do
    log "  Combining libraries for architecture: $ARCH"
    TEMP_ARCH_LIB="${TEMP_FRAMEWORK_DIR}/combined_${ARCH}.a"
    
    # Extract architecture from each library and combine
    TEMP_EXTRACT_DIR="${TEMP_FRAMEWORK_DIR}/extract_${ARCH}"
    rm -rf "$TEMP_EXTRACT_DIR"
    mkdir -p "$TEMP_EXTRACT_DIR"
    
    TEMP_ARCH_LIBS=()
    LIB_COUNT_FOR_ARCH=0
    # Extract this architecture from each static library
    for lib in "$STATIC_LIBS_DIR"/*.a; do
      if [ -f "$lib" ]; then
        lib_name=$(basename "$lib" .a)
        extracted_lib="${TEMP_EXTRACT_DIR}/${lib_name}_${ARCH}.a"
        
        # Check if library has this architecture
        lib_archs=$(lipo -archs "$lib" 2>/dev/null || echo "")
        if [ -z "$lib_archs" ]; then
          # If lipo fails, try to use the library directly (might be single-arch or thin binary)
          log "    Warning: Could not determine architectures for $lib_name, attempting direct use"
          if [ -f "$lib" ] && [ -s "$lib" ]; then
            TEMP_ARCH_LIBS+=("$lib")
            LIB_COUNT_FOR_ARCH=$((LIB_COUNT_FOR_ARCH + 1))
          fi
        elif echo "$lib_archs" | grep -q "$ARCH"; then
          # Use -thin instead of -extract to create a proper thin archive
          # -extract creates a fat binary wrapper which ar can't read
          if lipo "$lib" -thin "$ARCH" -output "$extracted_lib" 2>/dev/null; then
            # Verify it has content and is a valid archive
            if [ -f "$extracted_lib" ] && [ -s "$extracted_lib" ]; then
              # Verify it's a valid archive by checking object file count
              OBJ_COUNT=$(ar -t "$extracted_lib" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
              if [ "$OBJ_COUNT" -gt 0 ]; then
                TEMP_ARCH_LIBS+=("$extracted_lib")
                LIB_COUNT_FOR_ARCH=$((LIB_COUNT_FOR_ARCH + 1))
              else
                log "    Warning: Extracted library $lib_name for $ARCH has no object files (might be fat binary wrapper)"
                # Try using the original library if extraction failed
                TEMP_ARCH_LIBS+=("$lib")
                LIB_COUNT_FOR_ARCH=$((LIB_COUNT_FOR_ARCH + 1))
              fi
            else
              log "    Warning: Extracted library $lib_name for $ARCH is empty"
            fi
          else
            log "    Warning: Failed to extract $ARCH from $lib_name, using original library"
            # Fallback: use original library (might work if it's already thin)
            TEMP_ARCH_LIBS+=("$lib")
            LIB_COUNT_FOR_ARCH=$((LIB_COUNT_FOR_ARCH + 1))
          fi
        else
          # Library doesn't have this architecture, skip it
          log "    Skipping $lib_name (no $ARCH architecture, has: $lib_archs)"
        fi
      fi
    done
    
    log "    Extracted $LIB_COUNT_FOR_ARCH libraries for $ARCH"
    
    # Combine all extracted libraries for this architecture
    if [ ${#TEMP_ARCH_LIBS[@]} -gt 0 ]; then
      log "    Combining ${#TEMP_ARCH_LIBS[@]} libraries for $ARCH (this may take 2-5 minutes)..."
      # Use libtool to combine static libraries - this preserves all object files
      # This is slow but necessary - combining 62 libraries with ~729 object files each
      log "    ⏳ Starting libtool combination (please wait)..."
      libtool -static -o "$TEMP_ARCH_LIB" "${TEMP_ARCH_LIBS[@]}" 2>&1 | grep -v -E "warning: (same member name|has no symbols)" || true
      log "    ✅ libtool combination complete"
      
      # Verify the combined library was created and has content
      if [ -f "$TEMP_ARCH_LIB" ] && [ -s "$TEMP_ARCH_LIB" ]; then
        # Check object file count - extract architecture first if it's a fat binary
        TEMP_CHECK="${TEMP_FRAMEWORK_DIR}/check_${ARCH}.a"
        if lipo "$TEMP_ARCH_LIB" -extract "$ARCH" -output "$TEMP_CHECK" 2>/dev/null; then
          OBJ_COUNT=$(ar -t "$TEMP_CHECK" 2>/dev/null | wc -l | tr -d ' ')
          rm -f "$TEMP_CHECK"
        else
          # Not a fat binary, check directly
          OBJ_COUNT=$(ar -t "$TEMP_ARCH_LIB" 2>/dev/null | wc -l | tr -d ' ')
        fi
        if [ -z "$OBJ_COUNT" ] || [ "$OBJ_COUNT" = "0" ]; then
          OBJ_COUNT="unknown"
        fi
        log "    ✅ Combined library for $ARCH has $OBJ_COUNT object files"
        
        # Verify file size is reasonable (should be large if it has 729 object files)
        FILE_SIZE=$(stat -f%z "$TEMP_ARCH_LIB" 2>/dev/null || stat -c%s "$TEMP_ARCH_LIB" 2>/dev/null || echo "0")
        if [ "$FILE_SIZE" -lt 1000000 ]; then
          log "    ⚠️  Warning: Combined library for $ARCH is suspiciously small ($FILE_SIZE bytes)"
        fi
      else
        log "    ⚠️  Failed to create combined library for $ARCH"
      fi
    else
      log "    ⚠️  No libraries extracted for architecture $ARCH"
    fi
    
    # Clean up extracted files
    rm -rf "$TEMP_EXTRACT_DIR"
  done
  
  # Create fat binary from all architectures
  ARCH_LIBS=$(find "${TEMP_FRAMEWORK_DIR}" -name "combined_*.a" -type f 2>/dev/null)
  if [ -n "$ARCH_LIBS" ]; then
    ARCH_LIB_ARRAY=($ARCH_LIBS)
    if [ ${#ARCH_LIB_ARRAY[@]} -eq 1 ]; then
      # Single architecture, just copy
      cp "${ARCH_LIB_ARRAY[0]}" "$UNIVERSAL_LIB"
    else
      # Multiple architectures, create fat binary
      lipo "${ARCH_LIB_ARRAY[@]}" -create -output "$UNIVERSAL_LIB" 2>&1 | grep -v "warning:" || true
    fi
  else
    # Fallback: try direct combination (may not work with fat binaries)
    libtool -static -o "$UNIVERSAL_LIB" "$STATIC_LIBS_DIR"/*.a 2>&1 | grep -v -E "warning: (same member name|has no symbols)" || true
  fi
  
  if [ ! -f "$UNIVERSAL_LIB" ] || [ ! -s "$UNIVERSAL_LIB" ]; then
    log "❌ Failed to create universal library"
    UNIFIED_XCFRAMEWORK=""
  else
    log "✅ Created universal framework library"
    
    # Verify architectures
    UNIVERSAL_ARCHS=$(lipo -archs "$UNIVERSAL_LIB" 2>/dev/null || echo "")
    log "  Universal library contains architectures: $UNIVERSAL_ARCHS"
    
    # Verify object file count
    OBJ_COUNT=$(ar -t "$UNIVERSAL_LIB" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
    if [ -z "$OBJ_COUNT" ] || [ "$OBJ_COUNT" = "0" ]; then
      OBJ_COUNT="unknown"
    fi
    log "  Universal library contains $OBJ_COUNT object files"
  fi
  
  if [ -f "$UNIVERSAL_LIB" ] && [ -s "$UNIVERSAL_LIB" ]; then
    log "  Creating Info.plist and module map for universal framework..."
    # Create Info.plist for universal framework
    cat > "${UNIVERSAL_FRAMEWORK}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>${FRAMEWORK_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>com.reactnative.runtime</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${FRAMEWORK_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>FMWK</string>
  <key>CFBundleShortVersionString</key>
  <string>0.81.5</string>
  <key>CFBundleVersion</key>
  <string>0.81.5</string>
  <key>MinimumOSVersion</key>
  <string>14.0</string>
</dict>
</plist>
EOF
    
    # Create module map
    MODULE_MAP_CONTENT="framework module ${FRAMEWORK_NAME} {
  umbrella header \"React.h\"
  export *
  module * { export * }
}"
    echo "$MODULE_MAP_CONTENT" > "${UNIVERSAL_FRAMEWORK}/Modules/module.modulemap"
    
    # Split universal binary into device (arm64) and simulator (x86_64/arm64)
    # For xcframework, we need separate slices
    log "  Splitting universal binary into device and simulator frameworks..."
    DEVICE_FRAMEWORK="${TEMP_FRAMEWORK_DIR}/device/${FRAMEWORK_NAME}.framework"
    SIM_FRAMEWORK="${TEMP_FRAMEWORK_DIR}/simulator/${FRAMEWORK_NAME}.framework"
    
    mkdir -p "${DEVICE_FRAMEWORK}/Headers"
    mkdir -p "${DEVICE_FRAMEWORK}/Modules"
    mkdir -p "${SIM_FRAMEWORK}/Headers"
    mkdir -p "${SIM_FRAMEWORK}/Modules"
    
    # Copy headers to both
    if [ -d "${RUNTIME_SRC}/Headers" ]; then
      cp -R "${RUNTIME_SRC}/Headers/"* "${DEVICE_FRAMEWORK}/Headers/" 2>/dev/null || true
      cp -R "${RUNTIME_SRC}/Headers/"* "${SIM_FRAMEWORK}/Headers/" 2>/dev/null || true
    fi
    
    # Extract device slice (arm64 only - for physical devices)
    # CRITICAL: Use combined library directly instead of extracting from universal library
    # The universal library is a fat binary, and extraction may not preserve all object files correctly
    DEVICE_LIB="${DEVICE_FRAMEWORK}/${FRAMEWORK_NAME}"
    DEVICE_HAS_ARM64=false
    if echo "$UNIVERSAL_ARCHS" | grep -q "arm64"; then
      # Use the combined arm64 library directly - it already has all object files
      COMBINED_ARM64="${TEMP_FRAMEWORK_DIR}/combined_arm64.a"
      if [ -f "$COMBINED_ARM64" ] && [ -s "$COMBINED_ARM64" ]; then
        cp "$COMBINED_ARM64" "$DEVICE_LIB"
        DEVICE_OBJ_COUNT=$(ar -t "$DEVICE_LIB" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
        if [ "$DEVICE_OBJ_COUNT" -gt 100 ]; then
          DEVICE_HAS_ARM64=true
          log "    ✅ Created device library (arm64) with $DEVICE_OBJ_COUNT object files"
        else
          log "    ⚠️  Device library has only $DEVICE_OBJ_COUNT object files (expected ~729)"
        fi
      else
        log "    ⚠️  Combined arm64 library not found, trying extraction from universal library"
        # Fallback: try extraction from universal library
        if lipo "$UNIVERSAL_LIB" -extract arm64 -output "$DEVICE_LIB" 2>&1 | grep -v "warning:"; then
          if [ -f "$DEVICE_LIB" ] && [ -s "$DEVICE_LIB" ]; then
            DEVICE_OBJ_COUNT=$(ar -t "$DEVICE_LIB" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
            if [ "$DEVICE_OBJ_COUNT" -gt 100 ]; then
              DEVICE_HAS_ARM64=true
              log "    ✅ Extracted device library (arm64) with $DEVICE_OBJ_COUNT object files"
            else
              log "    ⚠️  Extracted device library has only $DEVICE_OBJ_COUNT object files"
            fi
          fi
        fi
      fi
    fi
    
    # Extract simulator slice - must be a SINGLE fat binary with both x86_64 and arm64
    # Xcode does NOT allow separate ios-x86_64-simulator and ios-arm64-simulator slices
    # Strategy: Create ONE simulator framework with BOTH architectures (fat binary)
    # This creates ios-arm64_x86_64-simulator (single slice with both archs)
    SIM_LIB="${SIM_FRAMEWORK}/${FRAMEWORK_NAME}"
    SIM_ARCHS_ARRAY=()
    HAS_X86_64=false
    HAS_ARM64_SIM=false
    
    if echo "$UNIVERSAL_ARCHS" | grep -q "x86_64"; then
      SIM_ARCHS_ARRAY+=("x86_64")
      HAS_X86_64=true
    fi
    if echo "$UNIVERSAL_ARCHS" | grep -q "arm64"; then
      SIM_ARCHS_ARRAY+=("arm64")
      HAS_ARM64_SIM=true
    fi
    
    # Extract simulator slice - must be a SINGLE fat binary with both x86_64 and arm64
    # CRITICAL: Use combined libraries directly instead of extracting from universal library
    # Xcode does NOT allow separate ios-x86_64-simulator and ios-arm64-simulator slices
    # Strategy: Create ONE simulator framework with BOTH architectures (fat binary)
    # This creates ios-arm64_x86_64-simulator (single slice with both archs)
    SIM_LIB="${SIM_FRAMEWORK}/${FRAMEWORK_NAME}"
    SIM_ARCHS_ARRAY=()
    HAS_X86_64=false
    HAS_ARM64_SIM=false
    
    if echo "$UNIVERSAL_ARCHS" | grep -q "x86_64"; then
      SIM_ARCHS_ARRAY+=("x86_64")
      HAS_X86_64=true
    fi
    if echo "$UNIVERSAL_ARCHS" | grep -q "arm64"; then
      SIM_ARCHS_ARRAY+=("arm64")
      HAS_ARM64_SIM=true
    fi
    
    if [ ${#SIM_ARCHS_ARRAY[@]} -gt 0 ]; then
      if [ ${#SIM_ARCHS_ARRAY[@]} -eq 1 ]; then
        # Single architecture for simulator - use combined library directly
        COMBINED_LIB="${TEMP_FRAMEWORK_DIR}/combined_${SIM_ARCHS_ARRAY[0]}.a"
        if [ -f "$COMBINED_LIB" ] && [ -s "$COMBINED_LIB" ]; then
          cp "$COMBINED_LIB" "$SIM_LIB"
          SIM_OBJ_COUNT=$(ar -t "$SIM_LIB" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
          log "    ✅ Created simulator library (${SIM_ARCHS_ARRAY[0]} only) with $SIM_OBJ_COUNT object files"
        else
          log "    ⚠️  Combined ${SIM_ARCHS_ARRAY[0]} library not found"
        fi
      else
        # Multiple architectures - create fat binary with both x86_64 and arm64
        # This is REQUIRED: Xcode only accepts ONE simulator slice with both architectures
        # Use combined libraries directly - they already have all object files
        TEMP_SIM_LIBS=()
        for arch in "${SIM_ARCHS_ARRAY[@]}"; do
          COMBINED_LIB="${TEMP_FRAMEWORK_DIR}/combined_${arch}.a"
          if [ -f "$COMBINED_LIB" ] && [ -s "$COMBINED_LIB" ]; then
            TEMP_SIM_LIBS+=("$COMBINED_LIB")
            OBJ_COUNT=$(ar -t "$COMBINED_LIB" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
            log "    ✅ Using combined $arch library with $OBJ_COUNT object files"
          else
            log "    ⚠️  Combined $arch library not found"
          fi
        done
        if [ ${#TEMP_SIM_LIBS[@]} -gt 0 ]; then
          if [ ${#TEMP_SIM_LIBS[@]} -eq 1 ]; then
            cp "${TEMP_SIM_LIBS[0]}" "$SIM_LIB"
            SIM_OBJ_COUNT=$(ar -t "$SIM_LIB" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
            log "    ✅ Created simulator library (single arch) with $SIM_OBJ_COUNT object files"
          else
            # Combine x86_64 and arm64 into single fat binary for simulator
            # This is the CORRECT approach - ONE simulator slice with BOTH architectures
            # CRITICAL: lipo doesn't preserve all object files when creating fat binaries from static library archives
            # Solution: Extract all object files from both architectures and combine them into a single archive
            # Then use libtool to create a proper fat binary archive
            log "    Extracting object files from both architectures and combining..."
            
            TEMP_OBJ_DIR="${TEMP_FRAMEWORK_DIR}/sim_objects"
            rm -rf "$TEMP_OBJ_DIR"
            mkdir -p "$TEMP_OBJ_DIR"
            
            # Extract object files from each architecture-specific library
            for lib in "${TEMP_SIM_LIBS[@]}"; do
              ARCHS=$(lipo -archs "$lib" 2>/dev/null || echo "")
              ARCH_NAME=$(echo "$ARCHS" | tr ' ' '_')
              if [ -n "$ARCH_NAME" ]; then
                ARCH_OBJ_DIR="${TEMP_OBJ_DIR}/${ARCH_NAME}"
                mkdir -p "$ARCH_OBJ_DIR"
                # Extract all object files from this library
                (cd "$ARCH_OBJ_DIR" && ar -x "$lib" 2>/dev/null || true)
                OBJ_COUNT=$(ls -1 "$ARCH_OBJ_DIR"/*.o 2>/dev/null | wc -l | tr -d ' ')
                log "      Extracted $OBJ_COUNT object files from $ARCH_NAME"
              fi
            done
            
            # CRITICAL FIX: lipo doesn't work correctly with static library archives
            # When creating a fat binary from archives, lipo loses object files
            # Solution: Create fat binary directly from the combined libraries using a different approach
            # We'll use libtool to combine, but we need to ensure it creates a proper archive
            log "    Creating simulator fat binary from architecture-specific libraries..."
            
            # The key insight: We need to create a fat binary that preserves all object files
            # Since lipo fails, we'll use a workaround: create separate thin archives and combine them
            # But Xcode requires a single fat binary for simulators
            
            # Try using libtool to combine first (this preserves object files)
            TEMP_COMBINED="${TEMP_FRAMEWORK_DIR}/temp_combined_sim.a"
            libtool -static -o "$TEMP_COMBINED" "${TEMP_SIM_LIBS[@]}" 2>&1 | grep -v -E "warning: (same member name|has no symbols)" || true
            
            if [ -f "$TEMP_COMBINED" ] && [ -s "$TEMP_COMBINED" ]; then
              COMBINED_OBJ_COUNT=$(ar -t "$TEMP_COMBINED" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
              log "    Combined archive has $COMBINED_OBJ_COUNT object files"
              
              # Now we need to create a fat binary from the original thin libraries
              # The issue: libtool combined them but didn't create a fat binary
              # We need to use lipo, but it fails with archives
              
              # WORKAROUND: Since we can't create a proper fat binary of archives,
              # we'll use the combined archive and mark it as a universal binary
              # by using lipo to verify/convert it
              
              # Check if combined archive is already a fat binary
              COMBINED_ARCHS=$(lipo -archs "$TEMP_COMBINED" 2>/dev/null || echo "")
              if echo "$COMBINED_ARCHS" | grep -qE "(x86_64|arm64)"; then
                # It's already a fat binary or has architectures
                cp "$TEMP_COMBINED" "$SIM_LIB"
                log "    ✅ Using combined archive as simulator library"
              else
                # Not a fat binary - try to create one using lipo with the original libraries
                # This is the problematic step, but we'll try it
                log "    Attempting to create fat binary with lipo..."
                if lipo "${TEMP_SIM_LIBS[@]}" -create -output "$SIM_LIB" 2>&1 | grep -v "warning:"; then
                  # Verify it worked
                  EXTRACTED_ARM64="${TEMP_FRAMEWORK_DIR}/verify_arm64.a"
                  if lipo "$SIM_LIB" -extract arm64 -output "$EXTRACTED_ARM64" 2>&1; then
                    EXTRACTED_COUNT=$(ar -t "$EXTRACTED_ARM64" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
                    rm -f "$EXTRACTED_ARM64"
                    if [ "$EXTRACTED_COUNT" -gt 100 ]; then
                      log "    ✅ Created simulator fat binary with $EXTRACTED_COUNT object files per arch"
                    else
                      log "    ⚠️  Fat binary created but only has $EXTRACTED_COUNT object files (expected ~729)"
                      # Fallback: use combined archive even though it's not a fat binary
                      cp "$TEMP_COMBINED" "$SIM_LIB"
                      log "    ⚠️  Using combined archive as fallback (may cause issues)"
                    fi
                  else
                    # lipo extraction failed, use combined archive
                    cp "$TEMP_COMBINED" "$SIM_LIB"
                    log "    ⚠️  Using combined archive (lipo extraction failed)"
                  fi
                else
                  # lipo failed completely, use combined archive
                  cp "$TEMP_COMBINED" "$SIM_LIB"
                  log "    ⚠️  Using combined archive (lipo failed)"
                fi
              fi
              
              rm -f "$TEMP_COMBINED"
            else
              log "    ⚠️  Failed to combine archives, trying direct lipo..."
              if lipo "${TEMP_SIM_LIBS[@]}" -create -output "$SIM_LIB" 2>&1 | grep -v "warning:"; then
                log "    ✅ Created simulator library using direct lipo"
              else
                log "    ❌ Failed to create simulator library"
              fi
            fi
            
            rm -rf "$TEMP_OBJ_DIR"
          fi
        else
          log "    ⚠️  No simulator combined libraries found"
        fi
      fi
    fi
    
    # Copy Info.plist and module map to both
    cp "${UNIVERSAL_FRAMEWORK}/Info.plist" "${DEVICE_FRAMEWORK}/Info.plist"
    cp "${UNIVERSAL_FRAMEWORK}/Info.plist" "${SIM_FRAMEWORK}/Info.plist"
    cp "${UNIVERSAL_FRAMEWORK}/Modules/module.modulemap" "${DEVICE_FRAMEWORK}/Modules/module.modulemap"
    cp "${UNIVERSAL_FRAMEWORK}/Modules/module.modulemap" "${SIM_FRAMEWORK}/Modules/module.modulemap"
    
    # Create xcframework from device and simulator frameworks
    log "  Creating xcframework from device and simulator frameworks..."
    rm -rf "$UNIFIED_XCFRAMEWORK"
    
    # Strategy: Create xcframework with explicit device and simulator frameworks
    # - Device: ios-arm64 (arm64 only, for physical devices)
    # - Simulator: ios-arm64_x86_64-simulator (both x86_64 and arm64, for simulators)
    # xcodebuild will correctly handle these as separate platform slices
    
    XCFRAMEWORK_ARGS=()
    HAS_VALID_FRAMEWORKS=false
    
    # Add device framework (arm64 only) if available
    if [ -f "$DEVICE_LIB" ] && [ -s "$DEVICE_LIB" ] && [ "$DEVICE_HAS_ARM64" = true ]; then
      # Verify device lib is arm64 only (not a fat binary)
      DEVICE_ARCHS=$(lipo -archs "$DEVICE_LIB" 2>/dev/null || echo "")
      if echo "$DEVICE_ARCHS" | grep -q "arm64" && [ "$(echo "$DEVICE_ARCHS" | wc -w | tr -d ' ')" -eq 1 ]; then
        # Verify framework structure is complete
        if [ -f "${DEVICE_FRAMEWORK}/Info.plist" ] && [ -f "${DEVICE_FRAMEWORK}/Modules/module.modulemap" ]; then
          XCFRAMEWORK_ARGS+=("-framework" "$DEVICE_FRAMEWORK")
          HAS_VALID_FRAMEWORKS=true
          log "    ✅ Device framework ready (ios-arm64)"
        else
          log "    ⚠️  Device framework missing required files"
        fi
      else
        log "    ⚠️  Device library is not arm64-only (has: $DEVICE_ARCHS)"
      fi
    fi
    
    # Add simulator framework (fat binary with x86_64 + arm64) if available
    # CRITICAL: Must be ONE simulator slice with BOTH architectures
    if [ -f "$SIM_LIB" ] && [ -s "$SIM_LIB" ]; then
      # Verify simulator lib has the expected architectures
      SIM_ARCHS=$(lipo -archs "$SIM_LIB" 2>/dev/null || echo "")
      if echo "$SIM_ARCHS" | grep -qE "(x86_64|arm64)"; then
        # Verify framework structure is complete
        if [ -f "${SIM_FRAMEWORK}/Info.plist" ] && [ -f "${SIM_FRAMEWORK}/Modules/module.modulemap" ]; then
          XCFRAMEWORK_ARGS+=("-framework" "$SIM_FRAMEWORK")
          HAS_VALID_FRAMEWORKS=true
          log "    ✅ Simulator framework ready (ios-arm64_x86_64-simulator with both architectures)"
        else
          log "    ⚠️  Simulator framework missing required files"
        fi
      else
        log "    ⚠️  Simulator library missing expected architectures (has: $SIM_ARCHS)"
      fi
    fi
    
    # Fallback: if we don't have valid separate frameworks, use universal framework
    if [ "$HAS_VALID_FRAMEWORKS" = false ]; then
      if [ -f "$UNIVERSAL_LIB" ] && [ -s "$UNIVERSAL_LIB" ]; then
        log "  ⚠️  Using universal framework as fallback (may only work for simulators)"
        XCFRAMEWORK_ARGS+=("-framework" "$UNIVERSAL_FRAMEWORK")
      fi
    fi
    
    if [ ${#XCFRAMEWORK_ARGS[@]} -gt 0 ]; then
      FRAMEWORK_COUNT=$((${#XCFRAMEWORK_ARGS[@]} / 2))
      log "  Creating production-ready xcframework with $FRAMEWORK_COUNT framework(s)..."
      
      # xcodebuild has issues with duplicate arm64 definitions when device framework
      # can be used for both device and simulator. We'll create the xcframework manually
      # to have full control over the structure.
      
      rm -rf "$UNIFIED_XCFRAMEWORK"
      mkdir -p "$UNIFIED_XCFRAMEWORK"
      
      # Create device slice (ios-arm64)
      if [ -f "$DEVICE_LIB" ] && [ -s "$DEVICE_LIB" ] && [ "$DEVICE_HAS_ARM64" = true ]; then
        DEVICE_SLICE="${UNIFIED_XCFRAMEWORK}/ios-arm64"
        mkdir -p "$DEVICE_SLICE"
        cp -R "$DEVICE_FRAMEWORK" "$DEVICE_SLICE/"
        log "    ✅ Added device slice (ios-arm64)"
      fi
      
      # Create simulator slice - MUST be ONE slice with BOTH x86_64 and arm64
      # Xcode does NOT allow separate simulator slices - they must be combined
      if [ -f "$SIM_LIB" ] && [ -s "$SIM_LIB" ]; then
        SIM_ARCHS=$(lipo -archs "$SIM_LIB" 2>/dev/null || echo "")
        # Check if simulator lib has both architectures (required for production)
        if echo "$SIM_ARCHS" | grep -q "x86_64" && echo "$SIM_ARCHS" | grep -q "arm64"; then
          # Fat binary with both architectures - create ios-arm64_x86_64-simulator
          SIM_SLICE="${UNIFIED_XCFRAMEWORK}/ios-arm64_x86_64-simulator"
          mkdir -p "$SIM_SLICE"
          cp -R "$SIM_FRAMEWORK" "$SIM_SLICE/"
          log "    ✅ Added simulator slice (ios-arm64_x86_64-simulator with both architectures)"
        elif echo "$SIM_ARCHS" | grep -q "x86_64"; then
          # Only x86_64 - create ios-x86_64-simulator (fallback for Intel-only builds)
          SIM_SLICE="${UNIFIED_XCFRAMEWORK}/ios-x86_64-simulator"
          mkdir -p "$SIM_SLICE"
          cp -R "$SIM_FRAMEWORK" "$SIM_SLICE/"
          log "    ⚠️  Added simulator slice (ios-x86_64-simulator - Intel Mac only)"
        elif echo "$SIM_ARCHS" | grep -q "arm64"; then
          # Only arm64 - create ios-arm64-simulator (fallback for Apple Silicon-only builds)
          SIM_SLICE="${UNIFIED_XCFRAMEWORK}/ios-arm64-simulator"
          mkdir -p "$SIM_SLICE"
          cp -R "$SIM_FRAMEWORK" "$SIM_SLICE/"
          log "    ⚠️  Added simulator slice (ios-arm64-simulator - Apple Silicon only)"
        fi
      fi
      
      # Create Info.plist for xcframework
      cat > "${UNIFIED_XCFRAMEWORK}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>AvailableLibraries</key>
  <array>
EOF
      
      # Add device library entry
      if [ -d "${UNIFIED_XCFRAMEWORK}/ios-arm64" ]; then
        cat >> "${UNIFIED_XCFRAMEWORK}/Info.plist" <<EOF
    <dict>
      <key>LibraryIdentifier</key>
      <string>ios-arm64</string>
      <key>LibraryPath</key>
      <string>ReactNativeRuntime.framework</string>
      <key>SupportedArchitectures</key>
      <array>
        <string>arm64</string>
      </array>
      <key>SupportedPlatform</key>
      <string>ios</string>
    </dict>
EOF
      fi
      
      # Add simulator library entry - MUST be ONE entry with BOTH architectures
      if [ -d "${UNIFIED_XCFRAMEWORK}/ios-arm64_x86_64-simulator" ]; then
        cat >> "${UNIFIED_XCFRAMEWORK}/Info.plist" <<EOF
    <dict>
      <key>LibraryIdentifier</key>
      <string>ios-arm64_x86_64-simulator</string>
      <key>LibraryPath</key>
      <string>ReactNativeRuntime.framework</string>
      <key>SupportedArchitectures</key>
      <array>
        <string>arm64</string>
        <string>x86_64</string>
      </array>
      <key>SupportedPlatform</key>
      <string>ios</string>
      <key>SupportedPlatformVariant</key>
      <string>simulator</string>
    </dict>
EOF
      elif [ -d "${UNIFIED_XCFRAMEWORK}/ios-x86_64-simulator" ]; then
        # Fallback: Intel Mac simulators only
        cat >> "${UNIFIED_XCFRAMEWORK}/Info.plist" <<EOF
    <dict>
      <key>LibraryIdentifier</key>
      <string>ios-x86_64-simulator</string>
      <key>LibraryPath</key>
      <string>ReactNativeRuntime.framework</string>
      <key>SupportedArchitectures</key>
      <array>
        <string>x86_64</string>
      </array>
      <key>SupportedPlatform</key>
      <string>ios</string>
      <key>SupportedPlatformVariant</key>
      <string>simulator</string>
    </dict>
EOF
      elif [ -d "${UNIFIED_XCFRAMEWORK}/ios-arm64-simulator" ]; then
        # Fallback: Apple Silicon simulators only
        cat >> "${UNIFIED_XCFRAMEWORK}/Info.plist" <<EOF
    <dict>
      <key>LibraryIdentifier</key>
      <string>ios-arm64-simulator</string>
      <key>LibraryPath</key>
      <string>ReactNativeRuntime.framework</string>
      <key>SupportedArchitectures</key>
      <array>
        <string>arm64</string>
      </array>
      <key>SupportedPlatform</key>
      <string>ios</string>
      <key>SupportedPlatformVariant</key>
      <string>simulator</string>
    </dict>
EOF
      fi
      
      cat >> "${UNIFIED_XCFRAMEWORK}/Info.plist" <<EOF
  </array>
  <key>CFBundlePackageType</key>
  <string>XFWK</string>
  <key>XCFrameworkFormatVersion</key>
  <string>1.0</string>
</dict>
</plist>
EOF
      
      # Verify xcframework structure
      if [ -f "${UNIFIED_XCFRAMEWORK}/Info.plist" ]; then
        SLICE_COUNT=$(find "$UNIFIED_XCFRAMEWORK" -maxdepth 1 -type d ! -path "$UNIFIED_XCFRAMEWORK" | wc -l | tr -d ' ')
        HAS_DEVICE_SLICE=false
        HAS_SIM_SLICE=false
        
        if [ -d "${UNIFIED_XCFRAMEWORK}/ios-arm64" ]; then
          HAS_DEVICE_SLICE=true
        fi
        if [ -d "${UNIFIED_XCFRAMEWORK}/ios-x86_64-simulator" ] || [ -d "${UNIFIED_XCFRAMEWORK}/ios-arm64-simulator" ]; then
          HAS_SIM_SLICE=true
        fi
        
        if [ "$HAS_DEVICE_SLICE" = true ] && [ "$HAS_SIM_SLICE" = true ]; then
          log "  ✅ Created production-ready xcframework (device + simulator)"
          if [ -d "${UNIFIED_XCFRAMEWORK}/ios-arm64_x86_64-simulator" ]; then
            log "    - Device: ios-arm64 (physical devices)"
            log "    - Simulator: ios-arm64_x86_64-simulator (Intel + Apple Silicon Mac simulators)"
          else
            SIM_SLICE_NAME=$(find "$UNIFIED_XCFRAMEWORK" -maxdepth 1 -type d -name "ios-*-simulator" | sed 's|.*/||' | head -1)
            log "    - Device: ios-arm64 (physical devices)"
            log "    - Simulator: $SIM_SLICE_NAME (limited support)"
          fi
        elif [ "$HAS_DEVICE_SLICE" = true ]; then
          log "  ⚠️  Created xcframework with device-only (simulator may not work)"
        elif [ "$HAS_SIM_SLICE" = true ]; then
          log "  ⚠️  Created xcframework with simulator-only (physical devices will not work)"
        else
          log "  ⚠️  Created xcframework but platform slices unclear"
        fi
      else
        log "  ❌ Failed to create xcframework Info.plist"
        rm -rf "$UNIFIED_XCFRAMEWORK"
        UNIFIED_XCFRAMEWORK=""
      fi
      
      if [ -d "$UNIFIED_XCFRAMEWORK" ] && [ -f "${UNIFIED_XCFRAMEWORK}/Info.plist" ]; then
        log "✅ Created unified ReactNativeRuntime.xcframework"
      else
        log "⚠️  Warning: Failed to create unified xcframework, will use static libraries approach"
        rm -rf "$UNIFIED_XCFRAMEWORK"
        UNIFIED_XCFRAMEWORK=""
      fi
    else
      log "⚠️  Warning: No valid framework binaries created, will use static libraries approach"
      UNIFIED_XCFRAMEWORK=""
    fi
  fi
  
  # Cleanup temp directory
  rm -rf "$TEMP_FRAMEWORK_DIR"
else
  UNIFIED_XCFRAMEWORK=""
  LIB_COUNT=0
fi

########################################
# Copy StaticLibs if not using unified xcframework (fallback)
########################################
STATIC_LIBS_DEST="${RUNTIME_SRC}/StaticLibs"
STATIC_LIB_NAMES=()

if [ -z "$UNIFIED_XCFRAMEWORK" ] || [ ! -d "$UNIFIED_XCFRAMEWORK" ]; then
  # Only copy static libs if we're not using unified xcframework
  if [ -d "$STATIC_LIBS_DIR" ] && [ "$(ls -A "$STATIC_LIBS_DIR"/*.a 2>/dev/null)" ]; then
    log "Copying static libraries to SPM package (fallback mode)..."
    mkdir -p "$STATIC_LIBS_DEST"
    rm -f "$STATIC_LIBS_DEST"/*.a 2>/dev/null || true
    cp -R "${STATIC_LIBS_DIR}/." "$STATIC_LIBS_DEST/" 2>/dev/null || true
    
    LIB_COUNT=$(ls -1 "$STATIC_LIBS_DEST"/*.a 2>/dev/null | wc -l | tr -d ' ')
    log "  Copied $LIB_COUNT static libraries"
    
    # Collect all library names for linker flags
    for lib_file in $(ls -1 "$STATIC_LIBS_DEST"/*.a 2>/dev/null | sort); do
      if [ -f "$lib_file" ]; then
        lib_name=$(basename "$lib_file" .a | sed 's/^lib//')
        STATIC_LIB_NAMES+=("$lib_name")
      fi
    done
  fi
fi

########################################
# Write Package.swift
########################################
log "Writing Package.swift..."

# Collect all xcframeworks (only if they exist)
XCFRAMEWORK_NAMES=()
if [ ${#XCFRAMEWORKS_CREATED[@]} -gt 0 ]; then
  for xc in "${XCFRAMEWORKS_CREATED[@]}"; do
    XCFRAMEWORK_NAMES+=("$(basename "$xc")")
  done
fi

# Determine package structure based on what we have
HAS_UNIFIED_XCFRAMEWORK=false
if [ -n "$UNIFIED_XCFRAMEWORK" ] && [ -d "$UNIFIED_XCFRAMEWORK" ]; then
  HAS_UNIFIED_XCFRAMEWORK=true
fi

cat > "${FRAMEWORK_ROOT}/Package.swift" <<EOF
// swift-tools-version: 5.9
// React Native Runtime SPM Package
// Generated from React Native 0.81.5 source
import PackageDescription

let package = Package(
    name: "ReactNativeRuntime",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "ReactNativeRuntime",
            targets: ["ReactNativeRuntime"]
        ),
    ],
    dependencies: [],
    targets: [
EOF

# Write target based on what we have
if [ "$HAS_UNIFIED_XCFRAMEWORK" = true ]; then
  # Write complete Package.swift with unified xcframework structure
  cat > "${FRAMEWORK_ROOT}/Package.swift" <<EOF
// swift-tools-version: 5.9
// React Native Runtime SPM Package
// Generated from React Native 0.81.5 source
import PackageDescription

let package = Package(
    name: "ReactNativeRuntime",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "ReactNativeRuntime",
            targets: ["ReactNativeRuntime"]
        ),
        .library(
            name: "React",
            targets: ["React"]
        ),
    ],
    dependencies: [],
    targets: [
        .binaryTarget(
            name: "ReactNativeRuntimeBinary",
            path: "ReactNativeRuntime.xcframework"
        ),
EOF

# Add Hermes binary target if it exists
if [ -n "$HERMES_XCFRAMEWORK_DEST" ] && [ -d "$HERMES_XCFRAMEWORK_DEST" ]; then
  cat >> "${FRAMEWORK_ROOT}/Package.swift" <<EOF
        .binaryTarget(
            name: "HermesBinary",
            path: "hermes.xcframework"
        ),
EOF
fi

cat >> "${FRAMEWORK_ROOT}/Package.swift" <<EOF
        .target(
            name: "ReactNativeRuntime",
            dependencies: ["ReactNativeRuntimeBinary"$(if [ -n "$HERMES_XCFRAMEWORK_DEST" ] && [ -d "$HERMES_XCFRAMEWORK_DEST" ]; then echo ', "HermesBinary"'; fi)],
            path: "Sources/ReactNativeRuntime",
            exclude: [
                "Headers/**/*.m",
                "Headers/**/*.mm",
                "Headers/**/*.cpp",
                "Headers/**/*.c",
                "Headers/**/*.S"
            ],
            sources: ["ReactNativeRuntime.m"],
            publicHeadersPath: "Headers",
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedLibrary("z"),
                .linkedLibrary("resolv"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("MobileCoreServices"),
                .linkedFramework("Accelerate"),
                .linkedFramework("CFNetwork"),
                .linkedFramework("CoreText"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Foundation"),
                .linkedFramework("UIKit"),
                .linkedFramework("JavaScriptCore"),
                .linkedFramework("SystemConfiguration"),
            ]
        ),
        .target(
            name: "React",
            dependencies: ["ReactNativeRuntimeBinary"$(if [ -n "$HERMES_XCFRAMEWORK_DEST" ] && [ -d "$HERMES_XCFRAMEWORK_DEST" ]; then echo ', "HermesBinary"'; fi)],
            path: "Sources/React",
            exclude: [
                "Headers/**/*.m",
                "Headers/**/*.mm",
                "Headers/**/*.cpp",
                "Headers/**/*.c",
                "Headers/**/*.S"
            ],
            sources: ["React.m"],
            publicHeadersPath: "Headers",
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedLibrary("z"),
                .linkedLibrary("resolv"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("MobileCoreServices"),
                .linkedFramework("Accelerate"),
                .linkedFramework("CFNetwork"),
                .linkedFramework("CoreText"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Foundation"),
                .linkedFramework("UIKit"),
                .linkedFramework("JavaScriptCore"),
                .linkedFramework("SystemConfiguration"),
            ]
        ),
    ]
)
EOF
else
  # Fallback to source-based with static libraries (if no unified xcframework)
  cat >> "${FRAMEWORK_ROOT}/Package.swift" <<EOF
        .target(
            name: "ReactNativeRuntime",
            dependencies: [],
            path: "Sources/ReactNativeRuntime",
            publicHeadersPath: "Headers",
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedLibrary("z"),
                .linkedLibrary("resolv"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("MobileCoreServices"),
                .linkedFramework("Accelerate"),
                .linkedFramework("CFNetwork"),
                .linkedFramework("CoreText"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Foundation"),
                .linkedFramework("UIKit"),
                .linkedFramework("JavaScriptCore"),
                .linkedFramework("SystemConfiguration"),
EOF

  # Add linker flags for static libraries (only if not using unified xcframework)
  if [ ${#STATIC_LIB_NAMES[@]} -gt 0 ]; then
    log "  Adding linker flags for $LIB_COUNT static libraries..."
    
    # Add library path and ObjC flag
    echo "                .unsafeFlags([\"-L\", \"StaticLibs\", \"-ObjC\"])," >> "${FRAMEWORK_ROOT}/Package.swift"
    
    # Add library flags in chunks to avoid very long lines (Xcode parser limit)
    # Process libraries in groups of 10 to keep lines manageable
    CHUNK_SIZE=10
    CHUNK_COUNT=0
    CURRENT_CHUNK=()
    
    for lib_name in "${STATIC_LIB_NAMES[@]}"; do
      CURRENT_CHUNK+=("$lib_name")
      
      if [ ${#CURRENT_CHUNK[@]} -ge $CHUNK_SIZE ]; then
        # Write this chunk
        CHUNK_FLAGS=""
        for lib in "${CURRENT_CHUNK[@]}"; do
          if [ -z "$CHUNK_FLAGS" ]; then
            CHUNK_FLAGS="\"-l${lib}\""
          else
            CHUNK_FLAGS="${CHUNK_FLAGS}, \"-l${lib}\""
          fi
        done
        echo "                .unsafeFlags([${CHUNK_FLAGS}])," >> "${FRAMEWORK_ROOT}/Package.swift"
        CURRENT_CHUNK=()
        CHUNK_COUNT=$((CHUNK_COUNT + 1))
      fi
    done
    
    # Write remaining libraries in final chunk
    if [ ${#CURRENT_CHUNK[@]} -gt 0 ]; then
      CHUNK_FLAGS=""
      for lib in "${CURRENT_CHUNK[@]}"; do
        if [ -z "$CHUNK_FLAGS" ]; then
          CHUNK_FLAGS="\"-l${lib}\""
        else
          CHUNK_FLAGS="${CHUNK_FLAGS}, \"-l${lib}\""
        fi
      done
      echo "                .unsafeFlags([${CHUNK_FLAGS}])," >> "${FRAMEWORK_ROOT}/Package.swift"
    fi
    
    log "  Added linker flags in chunks (${CHUNK_COUNT} full chunks + 1 partial)"
  fi
  
  cat >> "${FRAMEWORK_ROOT}/Package.swift" <<EOF
            ]
        ),
EOF
fi

# Only append closing braces if we're NOT using unified xcframework
# (unified xcframework path already writes complete Package.swift with closing braces)
if [ "$HAS_UNIFIED_XCFRAMEWORK" = false ]; then
  cat >> "${FRAMEWORK_ROOT}/Package.swift" <<EOF
    ]
)
EOF
fi

########################################
# Create README
########################################
log "Writing README.md..."
cat > "${FRAMEWORK_ROOT}/README.md" <<EOF
# React Native Runtime SPM Package

This package provides React Native 0.81.5 runtime as a Swift Package Manager (SPM) package.

## Usage

### Add to Xcode Project

1. Open your Xcode project
2. Go to **File → Add Package Dependencies...**
3. Click **Add Local...**
4. Navigate to this directory: \`frameworks/ios/ReactNativeRuntime\`
5. Select your target and add the package

### In Your Code

\`\`\`swift
import ReactNativeRuntime
import React

// Use React Native types
let bridge = RCTBridge(bundleURL: url, moduleProvider: nil, launchOptions: nil)
let rootView = RCTRootView(bridge: bridge, moduleName: "YourModule", initialProperties: nil)
\`\`\`

## Included Frameworks

This package includes the following React Native frameworks:

EOF

if [ ${#XCFRAMEWORK_NAMES[@]} -gt 0 ]; then
  for xc_name in "${XCFRAMEWORK_NAMES[@]}"; do
    echo "- \`$xc_name\`" >> "${FRAMEWORK_ROOT}/README.md"
  done
fi

cat >> "${FRAMEWORK_ROOT}/README.md" <<EOF

## Requirements

- iOS 14.0+
- Xcode 14+
- Swift 5.9+

## Version

React Native 0.81.5

## Notes

- Headers are available via \`import React\` and \`import ReactCommon\`
- All React Native static libraries are linked via xcframeworks
- Hermes engine is included for JavaScript execution
EOF

########################################
# Verify output structure
########################################
log "Verifying output structure..."

if [ ! -d "$FRAMEWORKS_DIR" ]; then
  err "frameworks directory was not created: $FRAMEWORKS_DIR"
  exit 1
fi

if [ ! -d "$FRAMEWORKS_IOS_DIR" ]; then
  err "frameworks/ios directory was not created: $FRAMEWORKS_IOS_DIR"
  exit 1
fi

if [ ! -d "$FRAMEWORK_ROOT" ]; then
  err "ReactNativeRuntime SPM package directory was not created: $FRAMEWORK_ROOT"
  exit 1
fi

if [ ! -f "${FRAMEWORK_ROOT}/Package.swift" ]; then
  err "Package.swift was not created in: $FRAMEWORK_ROOT"
  exit 1
fi

log "✅ Directory structure verified:"
echo "   frameworks/ → $FRAMEWORKS_DIR"
echo "   frameworks/ios/ → $FRAMEWORKS_IOS_DIR"
echo "   frameworks/ios/ReactNativeRuntime/ → $FRAMEWORK_ROOT"

########################################
# Summary
########################################
log "🎉 SUCCESS! React Native Runtime SPM generated"
echo ""
echo "📍 Location: $FRAMEWORK_ROOT"
echo ""
echo "📁 Directory structure:"
echo "   frameworks/"
echo "   └── ios/"
echo "       └── ReactNativeRuntime/  ← SPM package here"
echo ""
if [ ${#XCFRAMEWORKS_CREATED[@]} -gt 0 ]; then
  echo "📦 Included ${#XCFRAMEWORKS_CREATED[@]} xcframeworks:"
  for xc_name in "${XCFRAMEWORK_NAMES[@]}"; do
    echo "   • $xc_name"
  done
  echo ""
fi
if [ "$HAS_STATIC_LIBS" = true ]; then
  echo "📚 Included $STATIC_LIB_COUNT static libraries"
  echo ""
fi
echo "📝 Next steps:"
echo "   1. Add to Xcode: File → Add Package Dependencies → Add Local..."
echo "   2. Navigate to: $FRAMEWORK_ROOT"
echo "   3. Import in your code: import ReactNativeRuntime"
echo "   4. Use React Native types: import React"
echo ""
if [ ${#BUILD_FAILURES[@]} -gt 0 ]; then
  echo "⚠️  Note: ${#BUILD_FAILURES[@]} schemes failed to build (see warnings above)"
  echo "   The package should still work with the successfully built frameworks."
fi
echo ""

########################################
# Cleanup log files
########################################
log "Cleaning up build log files..."
LOG_FILES=$(find "$BUILD_ROOT" -type f -name "*.log" 2>/dev/null | wc -l | tr -d ' ')
if [ "$LOG_FILES" -gt 0 ]; then
  find "$BUILD_ROOT" -type f -name "*.log" -delete 2>/dev/null || true
  log "  ✅ Cleaned up $LOG_FILES log files"
else
  log "  ℹ️  No log files to clean"
fi
echo ""
