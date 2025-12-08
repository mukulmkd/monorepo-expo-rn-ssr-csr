#!/usr/bin/env bash
# Publish a single AAR to local Maven or Artifactory
#
# Usage:
#   ./scripts/publish-aar.sh AAR=<aar-name> LOCATION=<local|central> [VERSION=<version>]
#
# Examples:
#   ./scripts/publish-aar.sh AAR=mkd-rn-host LOCATION=local
#   ./scripts/publish-aar.sh AAR=mkd-rn-host LOCATION=central VERSION=1.2.3
#   ./scripts/publish-aar.sh AAR=mkd-rn-module-products LOCATION=local VERSION=0.0.1
#
# Parameters:
#   AAR      - AAR name: mkd-rn-host, mkd-rn-module-products, mkd-rn-module-cart, mkd-rn-module-pdp
#   LOCATION - Where to publish: local (mavenLocal) or central (Artifactory)
#   VERSION  - Version to publish (optional, defaults to 1.0.0)
#
# Environment variables (for Artifactory, override artifactory.properties):
#   ARTIFACTORY_USER - Artifactory username
#   ARTIFACTORY_PASSWORD - Artifactory password
#   ARTIFACTORY_CONTEXT_URL - Artifactory URL
#   ARTIFACTORY_REPO - Repository name

set -euo pipefail

MONOREPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRAMEWORKS_ANDROID_DIR="${MONOREPO_ROOT}/frameworks/android"
DIST_DIR="${MONOREPO_ROOT}/frameworks/android/distribution/aars"
ANDROID_PROPS_DIR="${MONOREPO_ROOT}/android-props"
CONFIG_FILE="${ANDROID_PROPS_DIR}/artifactory.properties"

log() { echo -e "\n==> $*\n"; }
err() { echo -e "\n‼️ ERROR: $*\n" >&2; }
warn() { echo -e "\n⚠️  WARNING: $*\n"; }

########################################
# Parse parameters
########################################
AAR_NAME=""
LOCATION=""
VERSION=""

# Parse command line arguments (format: KEY=value)
for arg in "$@"; do
  if [[ "$arg" =~ ^AAR= ]]; then
    AAR_NAME="${arg#AAR=}"
  elif [[ "$arg" =~ ^LOCATION= ]]; then
    LOCATION="${arg#LOCATION=}"
  elif [[ "$arg" =~ ^VERSION= ]]; then
    VERSION="${arg#VERSION=}"
  fi
done

# Validate required parameters
if [ -z "$AAR_NAME" ] || [ -z "$LOCATION" ]; then
  err "Missing required parameters!"
  err ""
  err "Usage:"
  err "  ./scripts/publish-aar.sh AAR=<aar-name> LOCATION=<local|central> [VERSION=<version>]"
  err ""
  err "Examples:"
  err "  ./scripts/publish-aar.sh AAR=mkd-rn-host LOCATION=local"
  err "  ./scripts/publish-aar.sh AAR=mkd-rn-host LOCATION=central VERSION=1.2.3"
  err "  ./scripts/publish-aar.sh AAR=mkd-rn-module-products LOCATION=local VERSION=0.0.1"
  err ""
  err "Valid AAR names:"
  err "  - mkd-rn-host"
  err "  - mkd-rn-module-products"
  err "  - mkd-rn-module-cart"
  err "  - mkd-rn-module-pdp"
  err ""
  err "Valid locations:"
  err "  - local (publishes to ~/.m2/repository)"
  err "  - central (publishes to Artifactory)"
  exit 1
fi

# Validate LOCATION
if [ "$LOCATION" != "local" ] && [ "$LOCATION" != "central" ]; then
  err "Invalid LOCATION: $LOCATION"
  err "Must be 'local' or 'central'"
  exit 1
fi

# Map AAR name to expected AAR filename, directory, and artifact ID
case "$AAR_NAME" in
  mkd-rn-host)
    AAR_FILENAME="mkd-rn-host-release.aar"
    AAR_DIR="mkd-rn-host"
    GROUP_ID="com.mkdcorp"
    ARTIFACT_ID="mkd-rn-host-sdk"
    GENERATE_SCRIPT="framework:android:aar:host"
    ;;
  mkd-rn-module-products)
    AAR_FILENAME="mkd-rn-module-products-release.aar"
    AAR_DIR="mkd-rn-module-products"
    GROUP_ID="com.mkdcorp"
    ARTIFACT_ID="mkd-rn-module-products"
    GENERATE_SCRIPT="framework:android:aar:products"
    ;;
  mkd-rn-module-cart)
    AAR_FILENAME="mkd-rn-module-cart-release.aar"
    AAR_DIR="mkd-rn-module-cart"
    GROUP_ID="com.mkdcorp"
    ARTIFACT_ID="mkd-rn-module-cart"
    GENERATE_SCRIPT="framework:android:aar:cart"
    ;;
  mkd-rn-module-pdp)
    AAR_FILENAME="mkd-rn-module-pdp-release.aar"
    AAR_DIR="mkd-rn-module-pdp"
    GROUP_ID="com.mkdcorp"
    ARTIFACT_ID="mkd-rn-module-pdp"
    GENERATE_SCRIPT="framework:android:aar:pdp"
    ;;
  *)
    err "Unknown AAR name: $AAR_NAME"
    err "Valid AAR names: mkd-rn-host, mkd-rn-module-products, mkd-rn-module-cart, mkd-rn-module-pdp"
    exit 1
    ;;
esac

########################################
# Check if AAR exists in distribution folder
########################################
DIST_AAR="${DIST_DIR}/${AAR_FILENAME}"

if [ ! -f "$DIST_AAR" ]; then
  err "AAR not found in distribution folder!"
  err ""
  err "Expected location: $DIST_AAR"
  err ""
  err "Please generate the AAR first:"
  err "  npm run $GENERATE_SCRIPT"
  err ""
  err "The AAR must be generated and placed in the distribution folder before publishing."
  exit 1
fi

log "✅ Found AAR in distribution folder: $DIST_AAR"
AAR_SIZE=$(ls -lh "$DIST_AAR" | awk '{print $5}')
log "  Size: $AAR_SIZE"

AAR_PATH="${FRAMEWORKS_ANDROID_DIR}/${AAR_DIR}"

if [ ! -d "$AAR_PATH" ]; then
  err "AAR directory not found: $AAR_PATH"
  exit 1
fi

# Set default version if not provided
# Try to get from package.json first, then fallback to 1.0.0
if [ -z "$VERSION" ]; then
  PACKAGE_JSON="${MONOREPO_ROOT}/package.json"
  if [ -f "$PACKAGE_JSON" ]; then
    # Try to extract version from package.json
    PACKAGE_VERSION=$(grep -E '"version"' "$PACKAGE_JSON" | head -1 | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | xargs)
    if [ -n "$PACKAGE_VERSION" ]; then
      VERSION="$PACKAGE_VERSION"
      log "Using version from package.json: $VERSION"
    else
      VERSION="1.0.0"
    fi
  else
    VERSION="1.0.0"
  fi
fi

log "Publishing AAR:"
log "  AAR: $AAR_NAME"
log "  Distribution file: $DIST_AAR"
log "  Project directory: $AAR_DIR"
log "  Group ID: $GROUP_ID"
log "  Artifact ID: $ARTIFACT_ID"
log "  Version: $VERSION"
log "  Location: $LOCATION"

########################################
# Load Artifactory config (if publishing to central)
########################################
if [ "$LOCATION" = "central" ]; then
  log "Loading Artifactory configuration..."
  
  if [ ! -f "$CONFIG_FILE" ]; then
    err "Configuration file not found: $CONFIG_FILE"
    err "Required for publishing to Artifactory (central)"
    err "Please create the file with Artifactory settings."
    exit 1
  fi
  
  # Load properties from config file
  artifactory_contextUrl=$(grep "^artifactory_contextUrl=" "$CONFIG_FILE" | cut -d'=' -f2- | xargs)
  mobileRepo=$(grep "^mobileRepo=" "$CONFIG_FILE" | cut -d'=' -f2- | xargs)
  artifactory_user=$(grep "^artifactory_user=" "$CONFIG_FILE" | cut -d'=' -f2- | xargs)
  artifactory_password=$(grep "^artifactory_password=" "$CONFIG_FILE" | cut -d'=' -f2- | xargs)
  
  # Override with environment variables if provided
  ARTIFACTORY_CONTEXT_URL="${ARTIFACTORY_CONTEXT_URL:-${artifactory_contextUrl:-}}"
  ARTIFACTORY_REPO="${ARTIFACTORY_REPO:-${mobileRepo:-}}"
  ARTIFACTORY_USER="${ARTIFACTORY_USER:-${artifactory_user:-}}"
  ARTIFACTORY_PASSWORD="${ARTIFACTORY_PASSWORD:-${artifactory_password:-}}"
  
  # Validate Artifactory settings
  if [ -z "$ARTIFACTORY_CONTEXT_URL" ] || [ -z "$ARTIFACTORY_REPO" ] || \
     [ -z "$ARTIFACTORY_USER" ] || [ -z "$ARTIFACTORY_PASSWORD" ]; then
    err "Missing required Artifactory configuration!"
    err "  ARTIFACTORY_CONTEXT_URL: ${ARTIFACTORY_CONTEXT_URL:-NOT SET}"
    err "  ARTIFACTORY_REPO: ${ARTIFACTORY_REPO:-NOT SET}"
    err "  ARTIFACTORY_USER: ${ARTIFACTORY_USER:-NOT SET}"
    err "  ARTIFACTORY_PASSWORD: ${ARTIFACTORY_PASSWORD:-NOT SET}"
    err ""
    err "Set these in $CONFIG_FILE or as environment variables."
    exit 1
  fi
  
  ARTIFACTORY_URL="${ARTIFACTORY_CONTEXT_URL}/${ARTIFACTORY_REPO}"
  
  log "Artifactory configuration:"
  log "  URL: $ARTIFACTORY_URL"
  log "  Repository: $ARTIFACTORY_REPO"
  log "  User: $ARTIFACTORY_USER"
fi

########################################
# Publish AAR
########################################
log "Publishing $AAR_NAME to $LOCATION..."

cd "$AAR_PATH"

if [ ! -f "gradlew" ]; then
  err "gradlew not found in $AAR_DIR"
  exit 1
fi

chmod +x gradlew

# Ensure the AAR from distribution is available for publishing
BUILD_OUTPUT_AAR_DIR="${AAR_PATH}/build/outputs/aar"
mkdir -p "$BUILD_OUTPUT_AAR_DIR"

# Determine the expected AAR filename in build output
BUILD_AAR_FILENAME=""
if [ "$AAR_NAME" = "mkd-rn-host" ]; then
  BUILD_AAR_FILENAME="mkd-rn-host-release.aar"
else
  BUILD_AAR_FILENAME="$AAR_FILENAME"
fi

BUILD_AAR="${BUILD_OUTPUT_AAR_DIR}/${BUILD_AAR_FILENAME}"

# Copy AAR from distribution to build output as a reference
log "Preparing AAR from distribution folder..."
cp "$DIST_AAR" "$BUILD_AAR" 2>/dev/null || true
log "  ✅ AAR available for publishing"

# Clean up existing publishing configuration entries before adding new ones
log "Cleaning up existing publishing configuration in gradle.properties..."

TEMP_FILE=$(mktemp)
grep -v '^# Publishing configuration (added by publish script)$' gradle.properties | \
grep -v '^# Artifactory publishing configuration (added by publish script)$' | \
grep -v '^publish_version=' | \
grep -v '^artifactory_contextUrl=' | \
grep -v '^mobileRepo=' | \
grep -v '^artifactory_user=' | \
grep -v '^artifactory_password=' > "$TEMP_FILE" 2>/dev/null || cp gradle.properties "$TEMP_FILE"

awk 'NF || p; {p=NF}' "$TEMP_FILE" > "${TEMP_FILE}.clean" 2>/dev/null || cp "$TEMP_FILE" "${TEMP_FILE}.clean"
mv "${TEMP_FILE}.clean" "$TEMP_FILE"

if [ -s "$TEMP_FILE" ]; then
  tail -1 "$TEMP_FILE" | grep -q '^[[:space:]]*$' || echo "" >> "$TEMP_FILE"
else
  echo "" > "$TEMP_FILE"
fi

mv "$TEMP_FILE" gradle.properties

# Update gradle.properties with version and Artifactory settings (if needed)
if [ "$LOCATION" = "central" ]; then
  cat >> gradle.properties <<EOF

# Publishing configuration (added by publish script)
publish_version=$VERSION
artifactory_contextUrl=$ARTIFACTORY_CONTEXT_URL
mobileRepo=$ARTIFACTORY_REPO
artifactory_user=$ARTIFACTORY_USER
artifactory_password=$ARTIFACTORY_PASSWORD
EOF
else
  cat >> gradle.properties <<EOF

# Publishing configuration (added by publish script)
publish_version=$VERSION
EOF
fi

# Remove old publishing block from build.gradle if it exists
sed -i '' '/^\/\/ Publishing configuration (added by publish-aar.sh)$/,/^}$/d' build.gradle 2>/dev/null || true
sed -i '' '/^afterEvaluate {$/,/^}$/d' build.gradle 2>/dev/null || true

# Clean up trailing blank lines and comments
sed -i '' '/^\/\/ Publishing configuration will be added dynamically by publish-aar.sh when needed$/d' build.gradle
sed -i '' '/^$/N;/^\n$/d' build.gradle
echo "" >> build.gradle

# Add publishing configuration directly to build.gradle
# Use afterEvaluate with explicit project parameter to ensure components.release is available
log "Adding publishing configuration to build.gradle..."

# Use printf to avoid heredoc issues with special characters
if [ "$LOCATION" = "central" ]; then
  printf "\n// Publishing configuration (added by publish-aar.sh)\nafterEvaluate { project ->\n    def publishVersion = project.findProperty(\"publish_version\") ?: \"1.0.0\"\n    \n    project.publishing {\n        publications {\n            release(MavenPublication) {\n                groupId = \"$GROUP_ID\"\n                artifactId = \"$ARTIFACT_ID\"\n                version = publishVersion\n                from components.release\n            }\n        }\n        \n        repositories {\n            mavenLocal()\n            def artifactoryUrl = project.findProperty(\"artifactory_contextUrl\")\n            def mobileRepo = project.findProperty(\"mobileRepo\")\n            if (artifactoryUrl && mobileRepo) {\n                maven {\n                    name = \"Artifactory\"\n                    url = \"\${artifactoryUrl}/\${mobileRepo}\"\n                    authentication {\n                        basic(BasicAuthentication)\n                    }\n                    credentials {\n                        username = project.findProperty(\"artifactory_user\") as String?\n                        password = project.findProperty(\"artifactory_password\") as String?\n                    }\n                }\n            }\n        }\n    }\n    \n    project.tasks.named(\"publishReleasePublicationToMavenLocal\").configure {\n        dependsOn(\"assembleRelease\")\n    }\n    project.tasks.named(\"publishReleasePublicationToArtifactoryRepository\").configure {\n        dependsOn(\"assembleRelease\")\n    }\n}\n" >> build.gradle
else
  printf "\n// Publishing configuration (added by publish-aar.sh)\nafterEvaluate { project ->\n    def publishVersion = project.findProperty(\"publish_version\") ?: \"1.0.0\"\n    \n    project.publishing {\n        publications {\n            release(MavenPublication) {\n                groupId = \"$GROUP_ID\"\n                artifactId = \"$ARTIFACT_ID\"\n                version = publishVersion\n                from components.release\n            }\n        }\n        \n        repositories {\n            mavenLocal()\n        }\n    }\n    \n    project.tasks.named(\"publishReleasePublicationToMavenLocal\").configure {\n        dependsOn(\"assembleRelease\")\n    }\n}\n" >> build.gradle
fi

log "  ✅ Added publishing configuration to build.gradle"

# Build and publish
log "Building and publishing..."
./gradlew clean assembleRelease

if [ "$LOCATION" = "local" ]; then
  ./gradlew publishReleasePublicationToMavenLocal
  log "✅ Published $AAR_NAME to local Maven repository"
  log "  Location: ~/.m2/repository/$GROUP_ID/$ARTIFACT_ID/$VERSION/"
  log ""
  log "Native apps can use:"
  log "  implementation '$GROUP_ID:$ARTIFACT_ID:$VERSION'"
elif [ "$LOCATION" = "central" ]; then
  ./gradlew publishReleasePublicationToArtifactoryRepository
  log "✅ Published $AAR_NAME to Artifactory"
  log "  Location: $ARTIFACTORY_URL"
  log "  Coordinates: $GROUP_ID:$ARTIFACT_ID:$VERSION"
  log ""
  log "Native apps can use:"
  log "  repositories {"
  log "    maven {"
  log "      url \"$ARTIFACTORY_URL\""
  log "      credentials {"
  log "        username \"$ARTIFACTORY_USER\""
  log "        password \"$ARTIFACTORY_PASSWORD\""
  log "      }"
  log "    }"
  log "  }"
  log ""
  log "  dependencies {"
  log "    implementation '$GROUP_ID:$ARTIFACT_ID:$VERSION'"
  log "  }"
fi
