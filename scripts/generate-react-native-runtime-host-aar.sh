#!/usr/bin/env bash
# Build mkd-rn-host AAR - Single unified AAR with all React Native dependencies
# Uses Maven dependencies directly (com.facebook.react:react-android, etc.)

set -e

MONOREPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST_DIR="${MONOREPO_ROOT}/frameworks/android/mkd-rn-host"
ANDROID_PROPS_DIR="${MONOREPO_ROOT}/android-props"

log() { echo -e "\n==> $*\n"; }
err() { echo -e "\n‼️ ERROR: $*\n" >&2; }

log "Building mkd-rn-host AAR (unified React Native host)"
log "Using Maven dependencies: com.facebook.react:react-android, com.facebook.react:hermes-android"

# Ensure local.properties exists in host project (from central android-props)
if [ -f "${ANDROID_PROPS_DIR}/local.properties" ]; then
  mkdir -p "$HOST_DIR"
  cp "${ANDROID_PROPS_DIR}/local.properties" "${HOST_DIR}/local.properties"
  log "✅ Copied local.properties from android-props to host project"
elif [ ! -f "${HOST_DIR}/local.properties" ]; then
  warn "local.properties not found in android-props or host project"
  warn "SDK location may not be configured correctly"
fi

# Build the AAR
cd "$HOST_DIR"

if [ ! -f "gradlew" ]; then
    err "gradlew not found in mkd-rn-host"
    exit 1
fi

chmod +x gradlew

log "Building mkd-rn-host AAR..."
log "  This will download React Native dependencies from Maven Central"
./gradlew clean assembleRelease

# Find the AAR
HOST_AAR=$(find build -name "mkd-rn-host-release.aar" -o -name "*.aar" 2>/dev/null | grep -E "(release|outputs)" | head -1)

if [ -z "$HOST_AAR" ] || [ ! -f "$HOST_AAR" ]; then
    err "mkd-rn-host AAR not found after build"
    exit 1
fi

# Copy to distribution directory
DIST_DIR="${MONOREPO_ROOT}/frameworks/android/distribution/aars"
mkdir -p "$DIST_DIR"
cp "$HOST_AAR" "$DIST_DIR/mkd-rn-host-release.aar"

# Copy POM file if it exists (for transitive dependency resolution)
POM_FILE="${HOST_DIR}/build/outputs/aar/mkd-rn-host-release.pom"
if [ -f "$POM_FILE" ]; then
    cp "$POM_FILE" "$DIST_DIR/mkd-rn-host-release.pom"
    log "✅ Copied POM file for transitive dependency resolution"
fi

HOST_AAR_SIZE=$(ls -lh "$DIST_DIR/mkd-rn-host-release.aar" | awk '{print $5}')
log "✅ mkd-rn-host AAR built successfully"
log "  Location: $DIST_DIR/mkd-rn-host-release.aar"
log "  Size: $HOST_AAR_SIZE"

echo ""
echo "=========================================="
echo "✅ mkd-rn-host AAR Ready!"
echo "=========================================="
echo ""
echo "This single AAR includes:"
echo "  ✅ React Native (com.facebook.react:react-android:0.81.5)"
echo "  ✅ Hermes (com.facebook.react:hermes-android:0.81.5)"
echo "  ✅ All transitive dependencies (fbjni, soloader, fresco, okhttp, okio, infer-annotation)"
echo "  ✅ RNHost utilities"
echo ""
echo "Native apps only need to add this ONE AAR!"
echo "No runtime AARs needed - uses Maven dependencies directly!"

