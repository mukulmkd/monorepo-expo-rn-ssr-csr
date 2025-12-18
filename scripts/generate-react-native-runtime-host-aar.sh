#!/usr/bin/env bash
# Build vsco-rn-host AAR - Single unified AAR with all React Native dependencies
# Uses Maven dependencies directly (com.facebook.react:react-android, etc.)

set -e

MONOREPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST_DIR="${MONOREPO_ROOT}/frameworks/android/vsco-rn-host"
ANDROID_PROPS_DIR="${MONOREPO_ROOT}/android-props"

log() { echo -e "\n==> $*\n"; }
err() { echo -e "\n‼️ ERROR: $*\n" >&2; }

log "Building vsco-rn-host AAR (unified React Native host)"
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
    err "gradlew not found in vsco-rn-host"
    exit 1
fi

chmod +x gradlew

log "Building vsco-rn-host AAR..."
log "  This will download React Native dependencies from Maven Central"
./gradlew clean assembleRelease

# Find the AAR
HOST_AAR=$(find build -name "vsco-rn-host-release.aar" -o -name "*.aar" 2>/dev/null | grep -E "(release|outputs)" | head -1)

if [ -z "$HOST_AAR" ] || [ ! -f "$HOST_AAR" ]; then
    err "vsco-rn-host AAR not found after build"
    exit 1
fi

# Publish to Maven Local to generate POM file (needed for Maven Central publishing)
log "Publishing to Maven Local to generate POM file..."
./gradlew publishReleasePublicationToMavenLocal > /dev/null 2>&1

# Copy to distribution directory
DIST_DIR="${MONOREPO_ROOT}/frameworks/android/distribution/aars"
mkdir -p "$DIST_DIR"
cp "$HOST_AAR" "$DIST_DIR/vsco-rn-host-release.aar"

# Copy POM file from local Maven repository (generated during publish)
# The POM is published to ~/.m2/repository/com/vscorp/vsco-rn-host-sdk/1.0.0/
MAVEN_LOCAL_POM="${HOME}/.m2/repository/com/vscorp/vsco-rn-host-sdk/1.0.0/vsco-rn-host-sdk-1.0.0.pom"
if [ -f "$MAVEN_LOCAL_POM" ]; then
    # Copy POM to build/outputs/aar folder (alongside the AAR)
    AAR_OUTPUT_DIR="${HOST_DIR}/build/outputs/aar"
    mkdir -p "$AAR_OUTPUT_DIR"
    cp "$MAVEN_LOCAL_POM" "$AAR_OUTPUT_DIR/vsco-rn-host-release.pom"
    log "✅ Copied POM file to build/outputs/aar/vsco-rn-host-release.pom"
    
    # Also copy to distribution directory
    cp "$MAVEN_LOCAL_POM" "$DIST_DIR/vsco-rn-host-release.pom"
    log "✅ Copied POM file to distribution directory"
    log "  POM includes all transitive dependencies (react-android, hermes-android, etc.)"
else
    warn "POM file not found in Maven Local repository"
    warn "  Expected: $MAVEN_LOCAL_POM"
    warn "  POM file is required for Maven Central publishing"
fi

HOST_AAR_SIZE=$(ls -lh "$DIST_DIR/vsco-rn-host-release.aar" | awk '{print $5}')
log "✅ vsco-rn-host AAR built successfully"
log "  Location: $DIST_DIR/vsco-rn-host-release.aar"
log "  Size: $HOST_AAR_SIZE"

echo ""
echo "=========================================="
echo "✅ vsco-rn-host AAR Ready!"
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

