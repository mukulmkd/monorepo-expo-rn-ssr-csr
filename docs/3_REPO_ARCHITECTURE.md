# 3-Repository Architecture Guide

This document provides a complete step-by-step guide for splitting the monorepo into three separate repositories for better separation of concerns and independent versioning.

## 📋 Table of Contents

1. [Overview](#overview)
2. [Git Repository Structure](#git-repository-structure)
3. [Repository 1: Monorepo (React Native Development)](#repository-1-monorepo-react-native-development)
4. [Repository 2: Runtime Repository](#repository-2-runtime-repository)
5. [Repository 3: Module Repository](#repository-3-module-repository)
6. [Migration Steps](#migration-steps)
7. [Workflow After Split](#workflow-after-split)
8. [Troubleshooting](#troubleshooting)

---

## Overview

### Current State
- **Monorepo**: Contains React Native modules, packages, Verdaccio, and framework generation scripts
- **Frameworks**: Generated AARs and SPM packages are stored in `frameworks/` directory

### Target State
- **Repository 1 (Monorepo)**: React Native development, Verdaccio publishing
- **Repository 2 (Runtime)**: Android runtime AAR (`mkd-rn-host`) and iOS runtime SPM (`MKDReactNativeRuntime`)
- **Repository 3 (Modules)**: Module AARs and SPM packages (products, cart, pdp)

### Benefits
- ✅ **Separation of Concerns**: Each repo has a clear purpose
- ✅ **Independent Versioning**: Runtime and modules can version independently
- ✅ **Team Scalability**: Different teams can own different repos
- ✅ **Distribution Flexibility**: GitHub for iOS SPM, Maven/Artifactory for Android AAR

---

## Git Repository Structure

### Question 1: Runtime Repository Git Structure

**Answer: You can use your existing runtime Git repository.**

You have two options:

#### Option A: Single Runtime Repository (Recommended)
- **One Git repository** containing both Android and iOS runtime
- Structure:
  ```
  runtime-repo/
  ├── android/          # Android runtime (mkd-rn-host)
  ├── ios/              # iOS runtime (MKDReactNativeRuntime)
  └── scripts/          # Build/publish scripts
  ```
- **Pros**: Simpler, single source of truth, easier to maintain
- **Cons**: Android and iOS must be versioned together

#### Option B: Separate Repositories
- **Two Git repositories**: `runtime-android` and `runtime-ios`
- **Pros**: Independent versioning for Android and iOS
- **Cons**: More complex, need to coordinate releases

**Recommendation**: Use **Option A** (single repository) unless you have a specific need for independent versioning.

---

### Question 2: Module SPM Git Structure

**Answer: You have two options for iOS SPM packages.**

#### Option A: One Repository Per Module (Recommended)
- **Three separate Git repositories**:
  - `MKDRNModuleProductsSPM.git`
  - `MKDRNModuleCartSPM.git`
  - `MKDRNModulePDPSPM.git`
- **Pros**:
  - ✅ Industry standard for SPM
  - ✅ Independent versioning per module
  - ✅ Cleaner dependency management
  - ✅ Better for CI/CD pipelines
- **Cons**: More repositories to manage

#### Option B: Monorepo for Modules
- **One Git repository** containing all module SPM packages:
  ```
  modules-repo/
  ├── ios/
  │   ├── MKDRNModuleProductsSPM/
  │   ├── MKDRNModuleCartSPM/
  │   └── MKDRNModulePDPSPM/
  └── android/
      ├── mkd-rn-module-products/
      ├── mkd-rn-module-cart/
      └── mkd-rn-module-pdp/
  ```
- **Pros**: Single repository, easier to coordinate releases
- **Cons**: 
  - ⚠️ SPM requires Git tags for versioning (can work with subdirectories)
  - ⚠️ Less flexible for independent module versioning

**Recommendation**: 
- **Option A** (one repo per module): Best for independent versioning and granular control
- **Option B** (single repo): Best for scalability and simpler management (especially with many modules)

**📖 See [Single Repository Strategy Guide](./3_REPO_MODULES_SPM_ALTERNATE_STRATEGY.md) for complete details on Option B.**

**Note**: For Android AARs, you can keep them all in the same repository (modules-repo) since Maven doesn't require separate repos.

---

## Repository 1: Monorepo (React Native Development)

### Purpose
React Native module development, package management, and Verdaccio publishing.

### Structure
```
monorepo-expo-rn-ssr-csr/
├── apps/
│   ├── shell/
│   ├── module-products/
│   ├── module-cart/
│   └── module-pdp/
├── packages/
│   ├── core/
│   ├── state/
│   ├── ui/
│   └── ...
├── tools/
│   └── verdaccio/
│       └── config.yaml
├── docs/
│   ├── LOCAL_REGISTRY.md
│   ├── PACKAGES.md
│   └── 3_REPO_ARCHITECTURE.md
├── README.md
└── package.json
```

### What Stays
- ✅ All React Native source code (`apps/`, `packages/`)
- ✅ Verdaccio configuration and scripts
- ✅ Documentation (LOCAL_REGISTRY.md, PACKAGES.md)
- ✅ Development scripts

### What Goes
- ❌ `frameworks/android/` → Move to Runtime Repository
- ❌ `frameworks/ios/MKDReactNativeRuntime/` → Move to Runtime Repository
- ❌ `frameworks/ios/MKDRNModule*/` → Move to Module Repository
- ❌ Framework generation scripts → Move to respective repositories
- ❌ `android-props/` → Move to Runtime and Module repositories

### Scripts to Keep
```json
{
  "scripts": {
    "dev": "...",
    "build": "...",
    "verdaccio:start": "...",
    "publish:verdaccio": "..."
  }
}
```

### Scripts to Remove
- `framework:android:aar:*` → Move to Runtime/Module repos
- `framework:ios:spm:*` → Move to Runtime/Module repos

---

## Repository 2: Runtime Repository

### Purpose
Android runtime AAR (`mkd-rn-host`) and iOS runtime SPM (`MKDReactNativeRuntime`).

### Structure
```
react-native-runtime/
├── README.md
├── NATIVE_INTEGRATION.md
├── android/
│   ├── mkd-rn-host/
│   │   ├── src/
│   │   ├── build.gradle
│   │   ├── settings.gradle
│   │   ├── gradle.properties
│   │   └── gradlew
│   └── distribution/
│       └── aars/
│           └── mkd-rn-host-release.aar
├── ios/
│   └── MKDReactNativeRuntime/
│       ├── Package.swift
│       ├── README.md
│       ├── MKDReactNativeRuntime.xcframework/
│       ├── hermes.xcframework/
│       └── Sources/
├── scripts/
│   ├── build-android-aar.sh
│   ├── build-ios-spm.sh
│   ├── publish-android-aar.sh
│   └── publish-ios-spm.sh
└── android-props/
    ├── local.properties
    ├── artifactory.properties
    └── artifactory.properties.example
```

### Git Repository Setup

#### If Using Existing Runtime Repository:
```bash
# Navigate to your existing runtime repository
cd /path/to/your-runtime-repo

# Create the structure
mkdir -p android/mkd-rn-host
mkdir -p ios/MKDReactNativeRuntime
mkdir -p scripts
mkdir -p android-props
```

#### If Creating New Repository:
```bash
# Create new repository
mkdir react-native-runtime
cd react-native-runtime
git init
git remote add origin https://github.com/yourorg/react-native-runtime.git
```

### Files to Move from Monorepo

1. **Android Runtime:**
   ```bash
   # From monorepo
   cp -r frameworks/android/mkd-rn-host/* runtime-repo/android/mkd-rn-host/
   ```

2. **iOS Runtime:**
   ```bash
   # From monorepo
   cp -r frameworks/ios/MKDReactNativeRuntime/* runtime-repo/ios/MKDReactNativeRuntime/
   ```

3. **Android Properties:**
   ```bash
   # From monorepo
   cp -r android-props/* runtime-repo/android-props/
   ```

### Scripts to Create

#### `scripts/build-android-aar.sh`
```bash
#!/usr/bin/env bash
# Build Android runtime AAR

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST_DIR="${REPO_ROOT}/android/mkd-rn-host"
ANDROID_PROPS_DIR="${REPO_ROOT}/android-props"

log() { echo -e "\n==> $*\n"; }
err() { echo -e "\n‼️ ERROR: $*\n" >&2; }

log "Building mkd-rn-host AAR"

# Copy local.properties
if [ -f "${ANDROID_PROPS_DIR}/local.properties" ]; then
  cp "${ANDROID_PROPS_DIR}/local.properties" "${HOST_DIR}/local.properties"
  log "✅ Copied local.properties"
else
  err "android-props/local.properties not found"
  exit 1
fi

# Build
cd "$HOST_DIR"
chmod +x gradlew
./gradlew clean assembleRelease

# Copy to distribution
DIST_DIR="${REPO_ROOT}/android/distribution/aars"
mkdir -p "$DIST_DIR"
HOST_AAR=$(find build -name "mkd-rn-host-release.aar" | head -1)
if [ -f "$HOST_AAR" ]; then
  cp "$HOST_AAR" "$DIST_DIR/"
  log "✅ AAR copied to distribution: $DIST_DIR"
else
  err "AAR not found after build"
  exit 1
fi
```

#### `scripts/build-ios-spm.sh`
```bash
#!/usr/bin/env bash
# Build iOS runtime SPM package
# Note: This script assumes the xcframework is already built
# You may need to adapt this based on your iOS build process

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="${REPO_ROOT}/ios/MKDReactNativeRuntime"

log() { echo -e "\n==> $*\n"; }
err() { echo -e "\n‼️ ERROR: $*\n" >&2; }

log "Building iOS runtime SPM package"

# Verify Package.swift exists
if [ ! -f "${IOS_DIR}/Package.swift" ]; then
  err "Package.swift not found in ${IOS_DIR}"
  exit 1
fi

# Verify xcframeworks exist
if [ ! -d "${IOS_DIR}/MKDReactNativeRuntime.xcframework" ]; then
  err "MKDReactNativeRuntime.xcframework not found"
  exit 1
fi

if [ ! -d "${IOS_DIR}/hermes.xcframework" ]; then
  err "hermes.xcframework not found"
  exit 1
fi

log "✅ iOS SPM package structure verified"
log "Package is ready for Git publishing"
```

#### `scripts/publish-android-aar.sh`
```bash
#!/usr/bin/env bash
# Publish Android runtime AAR to Maven Local or Artifactory

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST_DIR="${REPO_ROOT}/android/mkd-rn-host"
ANDROID_PROPS_DIR="${REPO_ROOT}/android-props"

LOCATION="${1:-local}"  # local or central
VERSION="${2:-0.1.0}"

log() { echo -e "\n==> $*\n"; }
err() { echo -e "\n‼️ ERROR: $*\n" >&2; }

if [ "$LOCATION" != "local" ] && [ "$LOCATION" != "central" ]; then
  err "Invalid location: $LOCATION. Use 'local' or 'central'"
  exit 1
fi

log "Publishing mkd-rn-host AAR to $LOCATION (version: $VERSION)"

# Check AAR exists
AAR_FILE="${REPO_ROOT}/android/distribution/aars/mkd-rn-host-release.aar"
if [ ! -f "$AAR_FILE" ]; then
  err "AAR not found: $AAR_FILE"
  err "Please build the AAR first: ./scripts/build-android-aar.sh"
  exit 1
fi

# Copy AAR to build directory
mkdir -p "${HOST_DIR}/build/outputs/aar"
cp "$AAR_FILE" "${HOST_DIR}/build/outputs/aar/"

# Set version in gradle.properties
echo "publish_version=$VERSION" >> "${HOST_DIR}/gradle.properties"

# Add publishing block to build.gradle (if not present)
# This is similar to the publish-aar.sh script from monorepo

cd "$HOST_DIR"

if [ "$LOCATION" == "local" ]; then
  ./gradlew clean assembleRelease publishReleasePublicationToMavenLocal
  log "✅ Published to Maven Local (~/.m2/repository/com/mkdcorp/mkd-rn-host-sdk/)"
else
  # Configure Artifactory
  if [ ! -f "${ANDROID_PROPS_DIR}/artifactory.properties" ]; then
    err "artifactory.properties not found"
    exit 1
  fi
  
  # Source artifactory properties
  source "${ANDROID_PROPS_DIR}/artifactory.properties"
  
  # Add publishing configuration (similar to monorepo publish-aar.sh)
  # ... (implementation details)
  
  ./gradlew clean assembleRelease publishReleasePublicationToArtifactoryRepository
  log "✅ Published to Artifactory"
fi
```

#### `scripts/publish-ios-spm.sh`
```bash
#!/usr/bin/env bash
# Publish iOS runtime SPM package to GitHub

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="${REPO_ROOT}/ios/MKDReactNativeRuntime"
VERSION="${1:-}"

log() { echo -e "\n==> $*\n"; }
err() { echo -e "\n‼️ ERROR: $*\n" >&2; }

if [ -z "$VERSION" ]; then
  err "Version required. Usage: $0 <version>"
  err "Example: $0 1.0.0"
  exit 1
fi

log "Publishing MKDReactNativeRuntime to GitHub (version: $VERSION)"

# Verify we're in a git repository
if [ ! -d "${IOS_DIR}/.git" ] && [ ! -d "${REPO_ROOT}/.git" ]; then
  err "Not a git repository. Please initialize git first."
  exit 1
fi

# Check if remote is configured
cd "$IOS_DIR" 2>/dev/null || cd "$REPO_ROOT"

if ! git remote get-url origin >/dev/null 2>&1; then
  err "Git remote 'origin' not configured"
  err "Please set up the GitHub repository first:"
  err "  git remote add origin https://github.com/yourorg/MKDReactNativeRuntime.git"
  exit 1
fi

# Verify Package.swift exists
if [ ! -f "${IOS_DIR}/Package.swift" ]; then
  err "Package.swift not found"
  exit 1
fi

# Stage all changes
git add -A

# Commit if there are changes
if ! git diff --staged --quiet; then
  git commit -m "Release v${VERSION}"
fi

# Push to main/master
BRANCH=$(git branch --show-current)
git push origin "$BRANCH"

# Create and push tag
git tag -a "v${VERSION}" -m "Release v${VERSION}"
git push origin "v${VERSION}"

log "✅ Published to GitHub"
log "Package URL: $(git remote get-url origin)"
log "Version: v${VERSION}"
log ""
log "To use in Xcode:"
log "  .package(url: \"$(git remote get-url origin)\", from: \"${VERSION}\")"
```

### Package.json Scripts
```json
{
  "name": "react-native-runtime",
  "version": "1.0.0",
  "scripts": {
    "build:android": "./scripts/build-android-aar.sh",
    "build:ios": "./scripts/build-ios-spm.sh",
    "build:all": "npm run build:android && npm run build:ios",
    "publish:android:local": "./scripts/publish-android-aar.sh local",
    "publish:android:central": "./scripts/publish-android-aar.sh central",
    "publish:ios": "./scripts/publish-ios-spm.sh"
  }
}
```

---

## Repository 3: Module Repository

### Purpose
Module AARs and SPM packages (products, cart, pdp).

### Structure

#### Option A: One Repo Per Module (Recommended for iOS SPM)
```
# Separate repositories for each module
MKDRNModuleProductsSPM/          # GitHub repo
├── Package.swift
├── Sources/
└── README.md

MKDRNModuleCartSPM/              # GitHub repo
├── Package.swift
├── Sources/
└── README.md

MKDRNModulePDPSPM/               # GitHub repo
├── Package.swift
├── Sources/
└── README.md

# Single repository for Android modules
react-native-modules-android/    # Git repo
├── mkd-rn-module-products/
├── mkd-rn-module-cart/
├── mkd-rn-module-pdp/
└── scripts/
```

#### Option B: Monorepo for All Modules
```
react-native-modules/
├── README.md
├── android/
│   ├── mkd-rn-module-products/
│   ├── mkd-rn-module-cart/
│   ├── mkd-rn-module-pdp/
│   └── distribution/
│       └── aars/
├── ios/
│   ├── MKDRNModuleProductsSPM/
│   ├── MKDRNModuleCartSPM/
│   └── MKDRNModulePDPSPM/
├── scripts/
│   ├── generate-android-aar.sh
│   ├── generate-ios-spm.sh
│   ├── publish-android-aar.sh
│   └── publish-ios-spm.sh
└── android-props/
    ├── local.properties
    └── artifactory.properties
```

**Recommendation**: Use **Option A** for iOS (separate repos) and a single repo for Android modules.

### Files to Move from Monorepo

1. **Android Modules:**
   ```bash
   # From monorepo
   cp -r frameworks/android/mkd-rn-module-* modules-repo/android/
   ```

2. **iOS Modules:**
   ```bash
   # From monorepo
   cp -r frameworks/ios/MKDRNModule*SPM/* modules-repo/ios/MKDRNModule*SPM/
   ```

3. **Android Properties:**
   ```bash
   # From monorepo
   cp -r android-props/* modules-repo/android-props/
   ```

### Scripts to Create

#### `scripts/generate-android-aar.sh`
```bash
#!/usr/bin/env bash
# Generate Android module AAR from Verdaccio

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANDROID_PROPS_DIR="${REPO_ROOT}/android-props"

# Parse arguments
MODULE_NAME="${1:-}"
VERDACCIO_URL="${VERDACCIO_URL:-http://localhost:4873}"

log() { echo -e "\n==> $*\n"; }
err() { echo -e "\n‼️ ERROR: $*\n" >&2; }

if [ -z "$MODULE_NAME" ]; then
  err "Module name required. Usage: $0 <module-name>"
  err "Example: $0 products"
  exit 1
fi

log "Generating Android AAR for module: $MODULE_NAME"

# Map module name to package details
case "$MODULE_NAME" in
  products)
    MODULE_PACKAGE="@app/module-products"
    MODULE_COMPONENT="ModuleProducts"
    ;;
  cart)
    MODULE_PACKAGE="@app/module-cart"
    MODULE_COMPONENT="ModuleCart"
    ;;
  pdp)
    MODULE_PACKAGE="@app/module-pdp"
    MODULE_COMPONENT="ModulePDP"
    ;;
  *)
    err "Unknown module: $MODULE_NAME"
    exit 1
    ;;
esac

# Check Verdaccio is running
if ! curl -s "$VERDACCIO_URL" >/dev/null 2>&1; then
  err "Verdaccio is not running on $VERDACCIO_URL"
  err "Please start Verdaccio in the monorepo: npm run verdaccio:start"
  exit 1
fi

# Create temp directory
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Fetch package from Verdaccio
log "Fetching $MODULE_PACKAGE from Verdaccio..."
cd "$TEMP_DIR"
npm pack "$MODULE_PACKAGE" --registry="$VERDACCIO_URL" || {
  err "Failed to fetch package from Verdaccio"
  exit 1
}

PACKAGE_TGZ=$(ls *.tgz | head -1)
tar -xzf "$PACKAGE_TGZ"
PACKAGE_DIR=$(ls -d */ | head -1)

# Generate bundle (similar to monorepo script)
# ... (implementation from monorepo generate-module-framework-aar.sh)

# Create Android project structure
MODULE_DIR="${REPO_ROOT}/android/mkd-rn-module-${MODULE_NAME}"
mkdir -p "$MODULE_DIR"

# Copy Android project template (from monorepo)
# ... (implementation)

# Build AAR
cd "$MODULE_DIR"
if [ -f "${ANDROID_PROPS_DIR}/local.properties" ]; then
  cp "${ANDROID_PROPS_DIR}/local.properties" "$MODULE_DIR/local.properties"
fi

chmod +x gradlew
./gradlew clean assembleRelease

# Copy to distribution
DIST_DIR="${REPO_ROOT}/android/distribution/aars"
mkdir -p "$DIST_DIR"
AAR_FILE=$(find build -name "mkd-rn-module-${MODULE_NAME}-release.aar" | head -1)
if [ -f "$AAR_FILE" ]; then
  cp "$AAR_FILE" "$DIST_DIR/"
  log "✅ AAR generated: $DIST_DIR/$(basename $AAR_FILE)"
else
  err "AAR not found after build"
  exit 1
fi
```

#### `scripts/generate-ios-spm.sh`
```bash
#!/usr/bin/env bash
# Generate iOS module SPM package from Verdaccio

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERDACCIO_URL="${VERDACCIO_URL:-http://localhost:4873}"

MODULE_NAME="${1:-}"

log() { echo -e "\n==> $*\n"; }
err() { echo -e "\n‼️ ERROR: $*\n" >&2; }

if [ -z "$MODULE_NAME" ]; then
  err "Module name required. Usage: $0 <module-name>"
  err "Example: $0 products"
  exit 1
fi

# Map module name
case "$MODULE_NAME" in
  products)
    MODULE_PACKAGE="@app/module-products"
    MODULE_COMPONENT="ModuleProducts"
    SPM_NAME="MKDRNModuleProductsSPM"
    ;;
  cart)
    MODULE_PACKAGE="@app/module-cart"
    MODULE_COMPONENT="ModuleCart"
    SPM_NAME="MKDRNModuleCartSPM"
    ;;
  pdp)
    MODULE_PACKAGE="@app/module-pdp"
    MODULE_COMPONENT="ModulePDP"
    SPM_NAME="MKDRNModulePDPSPM"
    ;;
  *)
    err "Unknown module: $MODULE_NAME"
    exit 1
    ;;
esac

log "Generating iOS SPM package for module: $MODULE_NAME"

# Check Verdaccio
if ! curl -s "$VERDACCIO_URL" >/dev/null 2>&1; then
  err "Verdaccio is not running on $VERDACCIO_URL"
  exit 1
fi

# Fetch and generate (similar to monorepo script)
# ... (implementation from monorepo generate-module-framework-spm.sh)

SPM_DIR="${REPO_ROOT}/ios/${SPM_NAME}"
log "✅ SPM package generated: $SPM_DIR"
log ""
log "Next steps:"
log "  1. Initialize git repository: cd $SPM_DIR && git init"
log "  2. Create GitHub repository: https://github.com/yourorg/${SPM_NAME}"
log "  3. Add remote: git remote add origin https://github.com/yourorg/${SPM_NAME}.git"
log "  4. Publish: ./scripts/publish-ios-spm.sh $MODULE_NAME <version>"
```

#### `scripts/publish-android-aar.sh`
```bash
#!/usr/bin/env bash
# Publish Android module AAR

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_PROPS_DIR="${REPO_ROOT}/android-props"

MODULE_NAME="${1:-}"
LOCATION="${2:-local}"
VERSION="${3:-0.1.0}"

log() { echo -e "\n==> $*\n"; }
err() { echo -e "\n‼️ ERROR: $*\n" >&2; }

if [ -z "$MODULE_NAME" ]; then
  err "Module name required. Usage: $0 <module-name> <location> [version]"
  err "Example: $0 products local 1.0.0"
  exit 1
fi

AAR_NAME="mkd-rn-module-${MODULE_NAME}"
MODULE_DIR="${REPO_ROOT}/android/${AAR_NAME}"
AAR_FILE="${REPO_ROOT}/android/distribution/aars/${AAR_NAME}-release.aar"

# Check AAR exists
if [ ! -f "$AAR_FILE" ]; then
  err "AAR not found: $AAR_FILE"
  err "Please generate the AAR first: ./scripts/generate-android-aar.sh $MODULE_NAME"
  exit 1
fi

# Similar to runtime publish script
# ... (implementation)
```

#### `scripts/publish-ios-spm.sh`
```bash
#!/usr/bin/env bash
# Publish iOS module SPM package to GitHub

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MODULE_NAME="${1:-}"
VERSION="${2:-}"

log() { echo -e "\n==> $*\n"; }
err() { echo -e "\n‼️ ERROR: $*\n" >&2; }

if [ -z "$MODULE_NAME" ] || [ -z "$VERSION" ]; then
  err "Usage: $0 <module-name> <version>"
  err "Example: $0 products 1.0.0"
  exit 1
fi

# Map module name to SPM name
case "$MODULE_NAME" in
  products) SPM_NAME="MKDRNModuleProductsSPM" ;;
  cart) SPM_NAME="MKDRNModuleCartSPM" ;;
  pdp) SPM_NAME="MKDRNModulePDPSPM" ;;
  *)
    err "Unknown module: $MODULE_NAME"
    exit 1
    ;;
esac

SPM_DIR="${REPO_ROOT}/ios/${SPM_NAME}"

if [ ! -d "$SPM_DIR" ]; then
  err "SPM package not found: $SPM_DIR"
  err "Please generate it first: ./scripts/generate-ios-spm.sh $MODULE_NAME"
  exit 1
fi

cd "$SPM_DIR"

# Check git
if [ ! -d ".git" ]; then
  log "Initializing git repository..."
  git init
  git add -A
  git commit -m "Initial commit"
fi

# Check remote
if ! git remote get-url origin >/dev/null 2>&1; then
  err "Git remote 'origin' not configured"
  err "Please set up GitHub repository:"
  err "  git remote add origin https://github.com/yourorg/${SPM_NAME}.git"
  exit 1
fi

# Commit and push
git add -A
if ! git diff --staged --quiet; then
  git commit -m "Release v${VERSION}"
fi

BRANCH=$(git branch --show-current || echo "main")
git push origin "$BRANCH"

# Tag and push
git tag -a "v${VERSION}" -m "Release v${VERSION}"
git push origin "v${VERSION}"

log "✅ Published ${SPM_NAME} v${VERSION} to GitHub"
```

### Package.json Scripts
```json
{
  "name": "react-native-modules",
  "version": "1.0.0",
  "scripts": {
    "generate:android:products": "./scripts/generate-android-aar.sh products",
    "generate:android:cart": "./scripts/generate-android-aar.sh cart",
    "generate:android:pdp": "./scripts/generate-android-aar.sh pdp",
    "generate:android:all": "npm run generate:android:products && npm run generate:android:cart && npm run generate:android:pdp",
    "generate:ios:products": "./scripts/generate-ios-spm.sh products",
    "generate:ios:cart": "./scripts/generate-ios-spm.sh cart",
    "generate:ios:pdp": "./scripts/generate-ios-spm.sh pdp",
    "generate:ios:all": "npm run generate:ios:products && npm run generate:ios:cart && npm run generate:ios:pdp",
    "publish:android:products:local": "./scripts/publish-android-aar.sh products local",
    "publish:android:products:central": "./scripts/publish-android-aar.sh products central",
    "publish:ios:products": "./scripts/publish-ios-spm.sh products"
  }
}
```

---

## Migration Steps

### Step 1: Prepare Monorepo

1. **Backup current state:**
   ```bash
   cd /path/to/monorepo
   git tag backup-before-split
   git push origin backup-before-split
   ```

2. **Document current structure:**
   ```bash
   tree frameworks/ -L 3 > frameworks-structure.txt
   ```

### Step 2: Create Runtime Repository

#### Option A: Using Existing Runtime Repository
```bash
cd /path/to/your-runtime-repo

# Create structure
mkdir -p android/mkd-rn-host
mkdir -p ios/MKDReactNativeRuntime
mkdir -p scripts
mkdir -p android-props

# Copy from monorepo
cp -r /path/to/monorepo/frameworks/android/mkd-rn-host/* android/mkd-rn-host/
cp -r /path/to/monorepo/frameworks/ios/MKDReactNativeRuntime/* ios/MKDReactNativeRuntime/
cp -r /path/to/monorepo/android-props/* android-props/

# Create scripts (use templates above)
# Create README.md
# Commit and push
git add -A
git commit -m "Initial runtime repository setup"
git push origin main
```

#### Option B: Creating New Runtime Repository
```bash
# Create new repository
mkdir react-native-runtime
cd react-native-runtime
git init
git remote add origin https://github.com/yourorg/react-native-runtime.git

# Follow Option A steps above
```

### Step 3: Create Module Repository

#### For Android Modules (Single Repository)
```bash
mkdir react-native-modules-android
cd react-native-modules-android
git init
git remote add origin https://github.com/yourorg/react-native-modules-android.git

# Create structure
mkdir -p android
mkdir -p scripts
mkdir -p android-props

# Copy from monorepo
cp -r /path/to/monorepo/frameworks/android/mkd-rn-module-* android/
cp -r /path/to/monorepo/android-props/* android-props/

# Create scripts (use templates above)
# Commit and push
git add -A
git commit -m "Initial Android modules repository"
git push origin main
```

#### For iOS Modules (Separate Repositories)
```bash
# For each module (products, cart, pdp)
MODULE_NAME=products
SPM_NAME=MKDRNModuleProductsSPM

mkdir "$SPM_NAME"
cd "$SPM_NAME"
git init
git remote add origin "https://github.com/yourorg/${SPM_NAME}.git"

# Copy from monorepo
cp -r "/path/to/monorepo/frameworks/ios/${SPM_NAME}"/* .

# Commit and push
git add -A
git commit -m "Initial ${SPM_NAME} package"
git push origin main

# Repeat for cart and pdp
```

### Step 4: Update Monorepo

1. **Remove framework directories:**
   ```bash
   cd /path/to/monorepo
   rm -rf frameworks/
   rm -rf android-props/
   ```

2. **Remove framework scripts from package.json:**
   ```bash
   # Edit package.json to remove framework:* scripts
   ```

3. **Update README.md:**
   ```bash
   # Update documentation to reference new repositories
   ```

4. **Commit changes:**
   ```bash
   git add -A
   git commit -m "Remove framework generation - moved to separate repos"
   git push origin main
   ```

### Step 5: Test End-to-End

1. **In Monorepo:**
   ```bash
   npm run verdaccio:start
   npm run publish:verdaccio
   ```

2. **In Runtime Repository:**
   ```bash
   npm run build:android
   npm run build:ios
   npm run publish:android:local
   npm run publish:ios 1.0.0
   ```

3. **In Module Repository:**
   ```bash
   npm run generate:android:products
   npm run generate:ios:products
   npm run publish:android:products:local
   npm run publish:ios:products 1.0.0
   ```

4. **In Native Apps:**
   - Test Android app with AARs from Maven Local
   - Test iOS app with SPM packages from GitHub

---

## Workflow After Split

### Development Workflow

**1. In Monorepo (React Native Development):**
```bash
# Develop modules
npm run dev

# Publish to Verdaccio
npm run publish:verdaccio
```

**2. In Runtime Repository:**
```bash
# Build Android AAR
npm run build:android

# Build iOS SPM
npm run build:ios

# Publish Android AAR
npm run publish:android:local      # For local development
npm run publish:android:central    # For production

# Publish iOS SPM
npm run publish:ios 1.0.0
```

**3. In Module Repository:**
```bash
# Generate AARs/SPMs (fetches from Verdaccio)
npm run generate:android:products
npm run generate:ios:products

# Publish
npm run publish:android:products:local
npm run publish:ios:products 1.0.0
```

### Integration in Native Apps

**Android:**
```gradle
// settings.gradle
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        mavenLocal()  // For local development
        // Or Artifactory for production
    }
}

// app/build.gradle
dependencies {
    implementation 'com.mkdcorp:mkd-rn-host-sdk:1.0.0'
    implementation 'com.mkdcorp:mkd-rn-module-products:1.0.0'
}
```

**iOS:**
```swift
// Package.swift or Xcode UI
dependencies: [
    .package(url: "https://github.com/yourorg/MKDReactNativeRuntime.git", from: "1.0.0"),
    .package(url: "https://github.com/yourorg/MKDRNModuleProductsSPM.git", from: "1.0.0")
]
```

---

## Troubleshooting

### Issue: Verdaccio Connection Failed
**Error:** `Verdaccio is not running on http://localhost:4873`

**Solution:**
```bash
# In monorepo
npm run verdaccio:start
```

### Issue: AAR Not Found
**Error:** `AAR not found in distribution folder`

**Solution:**
```bash
# Build AAR first
npm run build:android  # In runtime repo
# or
npm run generate:android:products  # In module repo
```

### Issue: Git Remote Not Configured
**Error:** `Git remote 'origin' not configured`

**Solution:**
```bash
git remote add origin https://github.com/yourorg/REPO_NAME.git
```

### Issue: SPM Package Not Found in Xcode
**Error:** `Missing package product 'MKDReactNativeRuntime'`

**Solution:**
1. Verify GitHub repository exists and is accessible
2. Check Git tag exists: `git ls-remote --tags origin`
3. Ensure Package.swift is correct
4. Clear Xcode SPM cache: `File > Packages > Reset Package Caches`

### Issue: Maven Dependency Not Found
**Error:** `Could not find com.mkdcorp:mkd-rn-host-sdk`

**Solution:**
```bash
# Publish to Maven Local
npm run publish:android:local  # In runtime repo

# Or configure Artifactory in settings.gradle
```

---

## Summary

### Git Repository Structure

| Component | Repository Structure | Recommendation |
|-----------|---------------------|----------------|
| **Runtime** | Single repo (android + ios) | ✅ Recommended |
| **Android Modules** | Single repo (all modules) | ✅ Recommended |
| **iOS Modules** | One repo per module | ✅ Recommended (industry standard) |

### Key Decisions

1. **Runtime Repository**: Use your existing Git repository (single repo for both Android and iOS)
2. **Module iOS SPM**: Create separate GitHub repositories for each module (3 repos total)
3. **Module Android AAR**: Single repository for all Android modules

### Next Steps

1. ✅ Review this documentation
2. ✅ Set up GitHub repositories for iOS SPM packages
3. ✅ Migrate runtime code to runtime repository
4. ✅ Migrate module code to module repositories
5. ✅ Update monorepo to remove framework generation
6. ✅ Test end-to-end workflow

---

## Related Documentation

- [Android AAR Integration Guide](./ANDROID_AAR_INTEGRATION.md)
- [iOS SPM Integration Guide](./IOS_SPM_INTEGRATION.md)
- [Native Integration Guide](../NATIVE_INTEGRATION.md)
- [Local Registry Guide](./LOCAL_REGISTRY.md)

