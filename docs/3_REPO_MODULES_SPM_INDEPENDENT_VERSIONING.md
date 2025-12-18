# Module SPM Independent Versioning in Single Repository

This document describes how to maintain a **single Git repository** for all module SPM packages while achieving **independent versioning** for each module. This approach uses Git subtrees and module-prefixed tags to enable per-module versioning.

---

## 📋 Table of Contents

1. [Overview](#overview)
2. [How It Works](#how-it-works)
3. [Repository Structure](#repository-structure)
4. [Setup Instructions](#setup-instructions)
5. [Versioning Strategy](#versioning-strategy)
6. [Package.swift Configuration](#packageswift-configuration)
7. [Version Management Scripts](#version-management-scripts)
8. [Publishing Workflow](#publishing-workflow)
9. [Consumption in Native Apps](#consumption-in-native-apps)
10. [Version Tracking](#version-tracking)
11. [Troubleshooting](#troubleshooting)
12. [Limitations and Workarounds](#limitations-and-workarounds)

---

## Overview

### The Goal

- ✅ **Single Repository**: All module SPM packages in one Git repository
- ✅ **Independent Versioning**: Each module can have its own version (e.g., `products@1.0.0`, `cart@2.0.0`)
- ✅ **SPM Compatible**: Works with Swift Package Manager
- ✅ **Scalable**: Easy to add new modules

### The Challenge

Swift Package Manager (SPM) uses Git tags at the repository root for versioning. By default, all packages in a repository share the same version tags. To achieve independent versioning, we use:

1. **Git Tags with Module Prefixes**: `products-v1.0.0`, `cart-v2.0.0`
2. **Root Package.swift**: References all modules and manages dependencies
3. **Version Manifest**: Tracks current versions of each module
4. **Helper Scripts**: Automate versioning and publishing

---

## How It Works

### Architecture

```
react-native-modules/
├── Package.swift              # Root package (all modules)
├── VERSIONS.md                # Current versions manifest
├── ios/
│   ├── MKDRNModuleProductsSPM/  # Tagged: products-v1.0.0
│   ├── MKDRNModuleCartSPM/      # Tagged: cart-v2.0.0
│   └── MKDRNModulePDPSPM/       # Tagged: pdp-v1.5.0
└── scripts/
    ├── version-module.sh        # Tag a specific module
    ├── list-versions.sh         # List all module versions
    └── publish-module.sh        # Publish a module release
```

### Versioning Flow

1. **Develop Module**: Make changes to `ios/MKDRNModuleProductsSPM/`
2. **Tag Module**: `git tag products-v1.1.0 -m "Release products v1.1.0"`
3. **Update Manifest**: Update `VERSIONS.md` with new version
4. **Push Tags**: `git push origin products-v1.1.0`
5. **Consume**: Reference repository in Xcode, check `VERSIONS.md` for available versions

---

## Repository Structure

### Recommended Structure

```
react-native-modules/
├── README.md
├── Package.swift                    # Root package manifest
├── VERSIONS.md                      # Version manifest (see below)
├── CHANGELOG.md                     # Combined changelog
├── ios/
│   ├── MKDRNModuleProductsSPM/
│   │   ├── Package.swift
│   │   ├── README.md
│   │   └── Sources/
│   │       └── MKDRNModuleProductsSPM/
│   ├── MKDRNModuleCartSPM/
│   │   ├── Package.swift
│   │   ├── README.md
│   │   └── Sources/
│   │       └── MKDRNModuleCartSPM/
│   └── MKDRNModulePDPSPM/
│       ├── Package.swift
│       ├── README.md
│       └── Sources/
│           └── MKDRNModulePDPSPM/
├── android/
│   ├── mkd-rn-module-products/
│   ├── mkd-rn-module-cart/
│   └── mkd-rn-module-pdp/
├── scripts/
│   ├── version-module.sh
│   ├── list-versions.sh
│   ├── publish-module.sh
│   └── update-versions-md.sh
└── android-props/
    ├── local.properties
    └── artifactory.properties
```

### VERSIONS.md Format

```markdown
# Module Versions

This file tracks the current version of each module in this repository.

| Module | Current Version | Last Updated | Git Tag |
|--------|----------------|--------------|---------|
| MKDRNModuleProductsSPM | 1.0.0 | 2024-01-15 | products-v1.0.0 |
| MKDRNModuleCartSPM | 2.0.0 | 2024-01-20 | cart-v2.0.0 |
| MKDRNModulePDPSPM | 1.5.0 | 2024-01-18 | pdp-v1.5.0 |

## Version History

### MKDRNModuleProductsSPM
- **v1.0.0** (2024-01-15): Initial release
- **v0.9.0** (2024-01-10): Beta release

### MKDRNModuleCartSPM
- **v2.0.0** (2024-01-20): Major update with new features
- **v1.5.0** (2024-01-15): Bug fixes
- **v1.0.0** (2024-01-01): Initial release

### MKDRNModulePDPSPM
- **v1.5.0** (2024-01-18): Performance improvements
- **v1.0.0** (2024-01-01): Initial release
```

---

## Setup Instructions

### Step 1: Create Repository Structure

```bash
mkdir react-native-modules
cd react-native-modules
git init
git remote add origin https://github.com/yourorg/react-native-modules.git
```

### Step 2: Copy Modules from Monorepo

```bash
# Copy iOS modules
cp -r /path/to/monorepo/frameworks/ios/MKDRNModule*SPM ios/

# Copy Android modules (if applicable)
cp -r /path/to/monorepo/frameworks/android/mkd-rn-module-* android/
```

### Step 3: Create Root Package.swift

Create `Package.swift` at the repository root (see [Package.swift Configuration](#packageswift-configuration) section).

### Step 4: Create Version Manifest

Create `VERSIONS.md` with initial versions:

```bash
cat > VERSIONS.md << 'EOF'
# Module Versions

| Module | Current Version | Last Updated | Git Tag |
|--------|----------------|--------------|---------|
| MKDRNModuleProductsSPM | 1.0.0 | $(date +%Y-%m-%d) | products-v1.0.0 |
| MKDRNModuleCartSPM | 1.0.0 | $(date +%Y-%m-%d) | cart-v1.0.0 |
| MKDRNModulePDPSPM | 1.0.0 | $(date +%Y-%m-%d) | pdp-v1.0.0 |
EOF
```

### Step 5: Create Helper Scripts

Create scripts in `scripts/` directory (see [Version Management Scripts](#version-management-scripts) section).

### Step 6: Initial Commit and Tag

```bash
git add -A
git commit -m "Initial commit - All modules"
git push origin main

# Tag initial versions
git tag products-v1.0.0 -m "Initial release: products v1.0.0"
git tag cart-v1.0.0 -m "Initial release: cart v1.0.0"
git tag pdp-v1.0.0 -m "Initial release: pdp v1.0.0"

git push origin --tags
```

---

## Versioning Strategy

### Tag Naming Convention

Use the format: `<module-name>-v<version>`

**Examples:**
- `products-v1.0.0`
- `cart-v2.0.0`
- `pdp-v1.5.0`
- `products-v1.0.0-beta.1` (pre-release)

### Module Name Mapping

| Module Directory | Tag Prefix | Example Tag |
|----------------|------------|-------------|
| `MKDRNModuleProductsSPM` | `products` | `products-v1.0.0` |
| `MKDRNModuleCartSPM` | `cart` | `cart-v1.0.0` |
| `MKDRNModulePDPSPM` | `pdp` | `pdp-v1.0.0` |

### Semantic Versioning

Follow [Semantic Versioning](https://semver.org/):
- **MAJOR.MINOR.PATCH**: `1.0.0`
- **Pre-release**: `1.0.0-beta.1`, `1.0.0-rc.1`
- **Build metadata**: `1.0.0+20240115`

---

## Package.swift Configuration

### Root Package.swift

Create `Package.swift` at the repository root:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ReactNativeModules",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        // Products module
        .library(
            name: "MKDRNModuleProductsSPM",
            targets: ["MKDRNModuleProductsSPM"]
        ),
        // Cart module
        .library(
            name: "MKDRNModuleCartSPM",
            targets: ["MKDRNModuleCartSPM"]
        ),
        // PDP module
        .library(
            name: "MKDRNModulePDPSPM",
            targets: ["MKDRNModulePDPSPM"]
        ),
    ],
    dependencies: [
        // React Native Runtime dependency
        .package(
            url: "https://github.com/yourorg/react-native-runtime.git",
            from: "1.0.0"
        )
    ],
    targets: [
        // Products target
        .target(
            name: "MKDRNModuleProductsSPM",
            dependencies: [
                .product(name: "MKDReactNativeRuntime", package: "react-native-runtime"),
                .product(name: "React", package: "react-native-runtime")
            ],
            path: "ios/MKDRNModuleProductsSPM/Sources/MKDRNModuleProductsSPM",
            resources: [
                .copy("Resources/module-products.bundle")
            ],
            publicHeadersPath: "include"
        ),
        // Cart target
        .target(
            name: "MKDRNModuleCartSPM",
            dependencies: [
                .product(name: "MKDReactNativeRuntime", package: "react-native-runtime"),
                .product(name: "React", package: "react-native-runtime")
            ],
            path: "ios/MKDRNModuleCartSPM/Sources/MKDRNModuleCartSPM",
            resources: [
                .copy("Resources/module-cart.bundle")
            ],
            publicHeadersPath: "include"
        ),
        // PDP target
        .target(
            name: "MKDRNModulePDPSPM",
            dependencies: [
                .product(name: "MKDReactNativeRuntime", package: "react-native-runtime"),
                .product(name: "React", package: "react-native-runtime")
            ],
            path: "ios/MKDRNModulePDPSPM/Sources/MKDRNModulePDPSPM",
            resources: [
                .copy("Resources/module-pdp.bundle")
            ],
            publicHeadersPath: "include"
        ),
    ]
)
```

### Individual Module Package.swift (Optional)

Each module can also have its own `Package.swift` for local development:

**`ios/MKDRNModuleProductsSPM/Package.swift`:**
```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MKDRNModuleProductsSPM",
    platforms: [.iOS(.v14)],
    products: [
        .library(name: "MKDRNModuleProductsSPM", targets: ["MKDRNModuleProductsSPM"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/yourorg/react-native-runtime.git",
            from: "1.0.0"
        )
    ],
    targets: [
        .target(
            name: "MKDRNModuleProductsSPM",
            dependencies: [
                .product(name: "MKDReactNativeRuntime", package: "react-native-runtime"),
                .product(name: "React", package: "react-native-runtime")
            ],
            path: "Sources/MKDRNModuleProductsSPM",
            resources: [.copy("Resources/module-products.bundle")],
            publicHeadersPath: "include"
        )
    ]
)
```

**Note:** The root `Package.swift` is what SPM uses when consuming the repository. Individual module `Package.swift` files are optional and mainly for local development.

---

## Version Management Scripts

### Script 1: `scripts/version-module.sh`

Tags a specific module with a new version:

```bash
#!/usr/bin/env bash
# Version a specific module

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { echo -e "\n==> $*\n"; }
err() { echo -e "\n‼️ ERROR: $*\n" >&2; }

MODULE_NAME="${1:-}"
VERSION="${2:-}"

if [ -z "$MODULE_NAME" ] || [ -z "$VERSION" ]; then
  err "Usage: $0 <module-name> <version>"
  err "Example: $0 products 1.0.0"
  err ""
  err "Available modules:"
  ls -1 "${REPO_ROOT}/ios" | grep "MKDRNModule" | sed 's/MKDRNModule//;s/SPM$//' | tr '[:upper:]' '[:lower:]' | sed 's/^/  - /'
  exit 1
fi

# Map module name to directory and tag prefix
case "$MODULE_NAME" in
  products)
    MODULE_DIR="MKDRNModuleProductsSPM"
    TAG_PREFIX="products"
    ;;
  cart)
    MODULE_DIR="MKDRNModuleCartSPM"
    TAG_PREFIX="cart"
    ;;
  pdp)
    MODULE_DIR="MKDRNModulePDPSPM"
    TAG_PREFIX="pdp"
    ;;
  *)
    err "Unknown module: $MODULE_NAME"
    err "Available modules: products, cart, pdp"
    exit 1
    ;;
esac

MODULE_PATH="${REPO_ROOT}/ios/${MODULE_DIR}"

if [ ! -d "$MODULE_PATH" ]; then
  err "Module directory not found: $MODULE_PATH"
  exit 1
fi

TAG_NAME="${TAG_PREFIX}-v${VERSION}"

log "Versioning module: $MODULE_NAME"
log "Version: $VERSION"
log "Tag: $TAG_NAME"

# Check if tag already exists
if git rev-parse "$TAG_NAME" >/dev/null 2>&1; then
  err "Tag $TAG_NAME already exists"
  exit 1
fi

# Create tag
git tag -a "$TAG_NAME" -m "Release $MODULE_NAME v${VERSION}"

log "✅ Created tag: $TAG_NAME"
log ""
log "Next steps:"
log "  1. Push tag: git push origin $TAG_NAME"
log "  2. Update VERSIONS.md: ./scripts/update-versions-md.sh $MODULE_NAME $VERSION"
```

### Script 2: `scripts/list-versions.sh`

Lists all module versions:

```bash
#!/usr/bin/env bash
# List all module versions

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() { echo -e "\n==> $*\n"; }

log "Module Versions:"
echo ""

# Map modules
declare -A MODULES=(
  ["products"]="MKDRNModuleProductsSPM"
  ["cart"]="MKDRNModuleCartSPM"
  ["pdp"]="MKDRNModulePDPSPM"
)

printf "%-20s %-15s %-30s\n" "Module" "Version" "Latest Tag"
echo "------------------------------------------------------------"

for module_name in "${!MODULES[@]}"; do
  MODULE_DIR="${MODULES[$module_name]}"
  TAG_PREFIX="$module_name"
  
  # Get latest tag for this module
  LATEST_TAG=$(git tag -l "${TAG_PREFIX}-v*" | sort -V | tail -1)
  
  if [ -z "$LATEST_TAG" ]; then
    VERSION="Not tagged"
    LATEST_TAG="N/A"
  else
    VERSION=$(echo "$LATEST_TAG" | sed "s/${TAG_PREFIX}-v//")
  fi
  
  printf "%-20s %-15s %-30s\n" "$MODULE_DIR" "$VERSION" "$LATEST_TAG"
done

echo ""
log "All Tags:"
git tag -l | grep -E "^(products|cart|pdp)-v" | sort -V
```

### Script 3: `scripts/update-versions-md.sh`

Updates VERSIONS.md with new version:

```bash
#!/usr/bin/env bash
# Update VERSIONS.md with new module version

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSIONS_FILE="${REPO_ROOT}/VERSIONS.md"

MODULE_NAME="${1:-}"
VERSION="${2:-}"

if [ -z "$MODULE_NAME" ] || [ -z "$VERSION" ]; then
  echo "Usage: $0 <module-name> <version>"
  exit 1
fi

# Map module name
case "$MODULE_NAME" in
  products) MODULE_DIR="MKDRNModuleProductsSPM" ;;
  cart) MODULE_DIR="MKDRNModuleCartSPM" ;;
  pdp) MODULE_DIR="MKDRNModulePDPSPM" ;;
  *) echo "Unknown module: $MODULE_NAME"; exit 1 ;;
esac

TAG_NAME="${MODULE_NAME}-v${VERSION}"
DATE=$(date +%Y-%m-%d)

# Update the versions table
if grep -q "| $MODULE_DIR |" "$VERSIONS_FILE"; then
  # Update existing entry
  sed -i.bak "s/| $MODULE_DIR |.*|.*|.*|/| $MODULE_DIR | $VERSION | $DATE | $TAG_NAME |/" "$VERSIONS_FILE"
  rm -f "${VERSIONS_FILE}.bak"
else
  # Add new entry (if needed)
  echo "| $MODULE_DIR | $VERSION | $DATE | $TAG_NAME |" >> "$VERSIONS_FILE"
fi

echo "✅ Updated VERSIONS.md: $MODULE_DIR -> $VERSION"
```

### Script 4: `scripts/publish-module.sh`

Complete workflow to publish a module:

```bash
#!/usr/bin/env bash
# Publish a module release (version, tag, push, update manifest)

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { echo -e "\n==> $*\n"; }
err() { echo -e "\n‼️ ERROR: $*\n" >&2; }

MODULE_NAME="${1:-}"
VERSION="${2:-}"

if [ -z "$MODULE_NAME" ] || [ -z "$VERSION" ]; then
  err "Usage: $0 <module-name> <version>"
  err "Example: $0 products 1.0.0"
  exit 1
fi

log "Publishing $MODULE_NAME v${VERSION}"

# Step 1: Version the module
log "Step 1: Creating version tag..."
"${SCRIPT_DIR}/version-module.sh" "$MODULE_NAME" "$VERSION"

# Step 2: Push tag
TAG_NAME="${MODULE_NAME}-v${VERSION}"
log "Step 2: Pushing tag to remote..."
git push origin "$TAG_NAME"

# Step 3: Update VERSIONS.md
log "Step 3: Updating VERSIONS.md..."
"${SCRIPT_DIR}/update-versions-md.sh" "$MODULE_NAME" "$VERSION"

# Step 4: Commit VERSIONS.md update
log "Step 4: Committing VERSIONS.md update..."
git add VERSIONS.md
git commit -m "Update version: $MODULE_NAME v${VERSION}" || true
git push origin main

log "✅ Published $MODULE_NAME v${VERSION}"
log "Tag: $TAG_NAME"
log "Repository: $(git remote get-url origin)"
```

---

## Publishing Workflow

### Workflow: Release a Module

```bash
# 1. Make changes to module
cd ios/MKDRNModuleProductsSPM
# ... make changes ...
git add .
git commit -m "Update products module"

# 2. Publish new version
cd ../..
./scripts/publish-module.sh products 1.1.0

# This will:
# - Create tag: products-v1.1.0
# - Push tag to GitHub
# - Update VERSIONS.md
# - Commit and push VERSIONS.md
```

### Workflow: Release Multiple Modules

```bash
# Release products module
./scripts/publish-module.sh products 1.1.0

# Release cart module (independent version)
./scripts/publish-module.sh cart 2.0.0

# Release pdp module (independent version)
./scripts/publish-module.sh pdp 1.5.0
```

### Workflow: Check Current Versions

```bash
# List all module versions
./scripts/list-versions.sh

# Or check VERSIONS.md
cat VERSIONS.md
```

---

## Consumption in Native Apps

### Method 1: Xcode UI

1. **Add Package:**
   - File → Add Packages...
   - Enter: `https://github.com/yourorg/react-native-modules.git`
   - Version: `Up to Next Major: 1.0.0` (or specific version)

2. **Select Products:**
   - Xcode will show all available products from root `Package.swift`
   - Select the modules you need:
     - ✅ MKDRNModuleProductsSPM
     - ✅ MKDRNModuleCartSPM
     - ✅ MKDRNModulePDPSPM

3. **Check Versions:**
   - Check `VERSIONS.md` in the repository for current module versions
   - Or use: `git tag | grep products` to see products module tags

4. **Import and Use:**
   ```swift
   import MKDRNModuleProductsSPM
   import MKDRNModuleCartSPM
   ```

### Method 2: Package.swift

**In your app's `Package.swift`:**
```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MyNativeApp",
    dependencies: [
        .package(
            url: "https://github.com/yourorg/react-native-runtime.git",
            from: "1.0.0"
        ),
        .package(
            url: "https://github.com/yourorg/react-native-modules.git",
            from: "1.0.0"  // Repository version (not module-specific)
        )
    ],
    targets: [
        .target(
            name: "MyNativeApp",
            dependencies: [
                .product(name: "MKDReactNativeRuntime", package: "react-native-runtime"),
                .product(name: "MKDRNModuleProductsSPM", package: "react-native-modules"),
                .product(name: "MKDRNModuleCartSPM", package: "react-native-modules"),
                .product(name: "MKDRNModulePDPSPM", package: "react-native-modules")
            ]
        )
    ]
)
```

### Method 3: Check Module Versions

Since Xcode/SPM shows the repository version (not per-module), check versions manually:

```bash
# In your native app project
# Check VERSIONS.md in the repository
curl https://raw.githubusercontent.com/yourorg/react-native-modules/main/VERSIONS.md

# Or check Git tags
git ls-remote --tags https://github.com/yourorg/react-native-modules.git | grep products
```

---

## Version Tracking

### VERSIONS.md

Maintain `VERSIONS.md` at the repository root to track current versions:

```markdown
# Module Versions

| Module | Current Version | Last Updated | Git Tag |
|--------|----------------|--------------|---------|
| MKDRNModuleProductsSPM | 1.1.0 | 2024-01-20 | products-v1.1.0 |
| MKDRNModuleCartSPM | 2.0.0 | 2024-01-20 | cart-v2.0.0 |
| MKDRNModulePDPSPM | 1.5.0 | 2024-01-18 | pdp-v1.5.0 |
```

### Git Tags

List all module tags:

```bash
# All tags
git tag -l

# Products module tags
git tag -l "products-v*"

# Cart module tags
git tag -l "cart-v*"

# Latest tag for each module
git tag -l "products-v*" | sort -V | tail -1
git tag -l "cart-v*" | sort -V | tail -1
git tag -l "pdp-v*" | sort -V | tail -1
```

### Automated Version Check

Create a script to check versions programmatically:

```bash
#!/bin/bash
# scripts/check-module-version.sh

MODULE=$1
REPO_URL="https://github.com/yourorg/react-native-modules.git"

# Get latest tag for module
LATEST_TAG=$(git ls-remote --tags "$REPO_URL" | grep "${MODULE}-v" | sort -V | tail -1 | sed 's/.*refs\/tags\///')

if [ -z "$LATEST_TAG" ]; then
  echo "No tags found for module: $MODULE"
else
  VERSION=$(echo "$LATEST_TAG" | sed "s/${MODULE}-v//")
  echo "$MODULE: $VERSION ($LATEST_TAG)"
fi
```

---

## Troubleshooting

### Issue: Xcode Shows Only Repository Version

**Problem:** Xcode shows the repository version (e.g., `1.0.0`) but not individual module versions.

**Solution:** 
- Check `VERSIONS.md` in the repository for current module versions
- Use `git tag | grep <module>` to see module-specific tags
- This is a limitation of SPM - it doesn't support per-module versioning natively

### Issue: Tag Not Found in Xcode

**Problem:** Created a tag but Xcode doesn't see it.

**Solution:**
```bash
# Ensure tag is pushed
git push origin <tag-name>

# Refresh Xcode package cache
# File → Packages → Reset Package Caches
```

### Issue: Module Not Listed in Xcode

**Problem:** Module doesn't appear in Xcode package products list.

**Solution:**
- Ensure module is defined in root `Package.swift`
- Check that `path` in target definition is correct
- Verify module directory structure matches `Package.swift`

### Issue: Version Conflict

**Problem:** Different modules require different versions of dependencies.

**Solution:**
- Use the highest required version in root `Package.swift`
- Or use separate repositories for modules with conflicting dependencies

---

## Limitations and Workarounds

### Limitation 1: Xcode Doesn't Show Per-Module Versions

**Issue:** Xcode shows repository version, not individual module versions.

**Workaround:**
- Maintain `VERSIONS.md` for version tracking
- Use helper scripts to check versions
- Document versioning strategy for team

### Limitation 2: SPM Uses Repository Tags

**Issue:** SPM expects semantic version tags at repository root.

**Workaround:**
- Use module-prefixed tags: `products-v1.0.0`
- Reference repository in Xcode/SPM
- Check `VERSIONS.md` for actual module versions

### Limitation 3: Dependency Version Conflicts

**Issue:** Different modules may need different dependency versions.

**Workaround:**
- Use highest required version in root `Package.swift`
- Or split conflicting modules into separate repositories

### Limitation 4: Tag Management

**Issue:** Many tags can clutter the repository.

**Workaround:**
- Use consistent naming: `<module>-v<version>`
- Document tag naming convention
- Use scripts to manage tags

---

## Best Practices

### 1. Version Naming

- Use consistent format: `<module>-v<version>`
- Follow semantic versioning
- Document versioning strategy

### 2. Tag Management

- Tag immediately after release
- Push tags promptly
- Keep `VERSIONS.md` updated

### 3. Documentation

- Maintain `VERSIONS.md` with current versions
- Document breaking changes in `CHANGELOG.md`
- Keep README.md updated

### 4. Automation

- Use scripts for versioning
- Automate `VERSIONS.md` updates
- CI/CD for tag validation

### 5. Team Communication

- Communicate version changes
- Document version dependencies
- Maintain version compatibility matrix

---

## Summary

This approach enables:

✅ **Single Repository**: All modules in one place  
✅ **Independent Versioning**: Each module has its own version  
✅ **SPM Compatible**: Works with Swift Package Manager  
✅ **Scalable**: Easy to add new modules  

**Trade-offs:**
- ⚠️ Xcode doesn't show per-module versions automatically
- ⚠️ Requires manual version tracking via `VERSIONS.md`
- ⚠️ More complex than shared versioning

**When to Use:**
- You need independent versioning per module
- You want a single repository for simplicity
- You're willing to maintain `VERSIONS.md` manually
- Your team understands the versioning strategy

---

## Related Documentation

- [3-Repository Architecture Guide](./3_REPO_ARCHITECTURE.md) - Complete architecture guide
- [Single Repository Strategy](./3_REPO_MODULES_SPM_ALTERNATE_STRATEGY.md) - Shared versioning approach
- [3-Repository Quick Reference](./3_REPO_QUICK_REFERENCE.md) - Quick answers
- [iOS SPM Integration Guide](./IOS_SPM_INTEGRATION.md) - Detailed iOS integration

