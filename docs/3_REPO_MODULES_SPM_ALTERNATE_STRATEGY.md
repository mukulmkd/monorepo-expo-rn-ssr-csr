# Module SPM Single Repository Strategy

This document describes an alternate approach to the 3-repository architecture, specifically for iOS SPM modules. Instead of maintaining separate Git repositories for each module SPM package, this strategy uses a **single repository** for all module SPM packages with **shared versioning**.

---

## 📋 Table of Contents

1. [Overview](#overview)
2. [Why Single Repository?](#why-single-repository)
3. [Repository Structure](#repository-structure)
4. [Versioning Strategy](#versioning-strategy)
5. [Implementation](#implementation)
6. [Consumption in Native Apps](#consumption-in-native-apps)
7. [Publishing Workflow](#publishing-workflow)
8. [Pros and Cons](#pros-and-cons)
9. [Migration from Separate Repos](#migration-from-separate-repos)
10. [Comparison with Separate Repos](#comparison-with-separate-repos)

---

## Overview

### The Problem

As your project grows, you may have many React Native modules (products, cart, pdp, checkout, profile, etc.). Maintaining a separate Git repository for each module SPM package becomes:

- ❌ **Cumbersome**: Managing 10+ repositories
- ❌ **Complex CI/CD**: Setting up pipelines for each repo
- ❌ **Coordination Overhead**: Ensuring all repos are in sync
- ❌ **Dependency Management**: Harder to track cross-module dependencies

### The Solution

Use a **single Git repository** containing all module SPM packages with **shared versioning**. This approach:

- ✅ **Scales Better**: Add new modules without creating new repos
- ✅ **Simpler Management**: One repository to maintain
- ✅ **Easier CI/CD**: Single pipeline for all modules
- ✅ **Coordinated Releases**: All modules version together
- ✅ **Works with SPM**: Native Swift Package Manager support

---

## Why Single Repository?

### When to Use Single Repository

✅ **Use single repository when:**
- You have many modules (5+)
- Modules are released together
- You want simpler repository management
- You prefer coordinated versioning
- Your team prefers monorepo workflows

❌ **Use separate repositories when:**
- Modules have completely independent release cycles
- Different teams own different modules
- You need granular version control per module
- Modules are open-sourced separately

### Industry Examples

Many organizations use single repositories for related packages:
- **Apple's Swift Packages**: Often grouped in monorepos
- **Firebase iOS SDK**: Single repo with multiple SPM products
- **Realm Swift**: Single repo with multiple packages
- **RxSwift**: Single repo with related packages

---

## Repository Structure

### Recommended Structure

```
react-native-modules/
├── README.md
├── Package.swift                    # Root package manifest (optional)
├── CHANGELOG.md                     # Shared changelog
├── ios/
│   ├── MKDRNModuleProductsSPM/
│   │   ├── Package.swift
│   │   ├── README.md
│   │   └── Sources/
│   │       └── MKDRNModuleProductsSPM/
│   │           ├── ModuleProductsFramework.swift
│   │           ├── include/
│   │           └── Resources/
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
│   ├── generate-ios-spm.sh
│   ├── publish-ios-spm.sh
│   └── version.sh
└── android-props/
    ├── local.properties
    └── artifactory.properties
```

### Key Points

1. **Each module has its own `Package.swift`** - Maintains package independence
2. **Shared Git repository** - All modules in one repo
3. **Shared version tags** - All modules version together (e.g., `v1.0.0`)
4. **Separate Android modules** - Can coexist in the same repo

---

## Versioning Strategy

### Shared Versioning

All modules share the same version using Git tags at the repository root:

```
v1.0.0    # All modules at version 1.0.0
v1.1.0    # All modules at version 1.1.0
v2.0.0    # All modules at version 2.0.0
```

### Version Tag Format

Use semantic versioning:
- **Major.Minor.Patch**: `v1.0.0`, `v1.1.0`, `v2.0.0`
- **Pre-release**: `v1.0.0-beta.1`, `v1.0.0-rc.1`
- **No module prefix**: Tags are at repo root, not per-module

### Versioning Workflow

```bash
# 1. Make changes to one or more modules
git add ios/MKDRNModuleProductsSPM/
git commit -m "Update products module"

# 2. Tag the release (all modules share this version)
git tag -a v1.1.0 -m "Release v1.1.0 - All modules"
git push origin main --tags
```

**Important:** Even if only one module changed, all modules get the new version tag. This is the trade-off for simplicity.

---

## Implementation

### Option 1: Separate Package.swift per Module (Recommended)

Each module maintains its own `Package.swift`:

**`ios/MKDRNModuleProductsSPM/Package.swift`:**
```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MKDRNModuleProductsSPM",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "MKDRNModuleProductsSPM",
            targets: ["MKDRNModuleProductsSPM"]
        ),
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
            resources: [
                .copy("Resources/module-products.bundle")
            ],
            publicHeadersPath: "include"
        ),
    ]
)
```

**How SPM Discovers Packages:**

When you add the repository in Xcode or Package.swift, SPM will:
1. Look for `Package.swift` files in the repository
2. Discover all packages automatically
3. Allow you to select which packages to use

**Consumption:**
```swift
// In your app's Package.swift or Xcode
dependencies: [
    .package(
        url: "https://github.com/yourorg/react-native-modules.git",
        from: "1.0.0"
    )
]

// Then use individual products
.product(name: "MKDRNModuleProductsSPM", package: "react-native-modules")
.product(name: "MKDRNModuleCartSPM", package: "react-native-modules")
```

**Note:** SPM will automatically discover all `Package.swift` files in the repository. However, you may need to reference them explicitly in some cases.

---

### Option 2: Single Root Package.swift (Alternative)

Create one `Package.swift` at the repository root that defines all modules:

**`Package.swift` (at root):**
```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ReactNativeModules",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "MKDRNModuleProductsSPM",
            targets: ["MKDRNModuleProductsSPM"]
        ),
        .library(
            name: "MKDRNModuleCartSPM",
            targets: ["MKDRNModuleCartSPM"]
        ),
        .library(
            name: "MKDRNModulePDPSPM",
            targets: ["MKDRNModulePDPSPM"]
        ),
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
            path: "ios/MKDRNModuleProductsSPM/Sources/MKDRNModuleProductsSPM",
            resources: [
                .copy("Resources/module-products.bundle")
            ],
            publicHeadersPath: "include"
        ),
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

**Pros:**
- ✅ Single source of truth
- ✅ Easier to manage dependencies
- ✅ Clearer package structure

**Cons:**
- ❌ Less modular (all in one file)
- ❌ Harder to maintain as modules grow
- ❌ Requires updating root Package.swift for each new module

**Recommendation:** Use **Option 1** (separate Package.swift per module) for better modularity and scalability.

---

## Consumption in Native Apps

### Method 1: Xcode UI

1. **Add Package:**
   - File → Add Packages...
   - Enter: `https://github.com/yourorg/react-native-modules.git`
   - Version: `Up to Next Major: 1.0.0`

2. **Select Products:**
   - Xcode will show all available packages
   - Select the modules you need:
     - ✅ MKDRNModuleProductsSPM
     - ✅ MKDRNModuleCartSPM
     - ✅ MKDRNModulePDPSPM

3. **Import and Use:**
   ```swift
   import MKDRNModuleProductsSPM
   import MKDRNModuleCartSPM
   ```

### Method 2: Package.swift (Swift Package Manager)

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
            from: "1.0.0"
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

### Method 3: Xcode Project File (Package Dependencies)

If using Xcode project (not Package.swift), add via:
- Project Settings → Package Dependencies
- Add: `https://github.com/yourorg/react-native-modules.git`
- Select version: `1.0.0` or `Up to Next Major: 1.0.0`

---

## Publishing Workflow

### Script: `scripts/publish-ios-spm.sh`

```bash
#!/usr/bin/env bash
# Publish iOS module SPM packages to GitHub

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-}"

log() { echo -e "\n==> $*\n"; }
err() { echo -e "\n‼️ ERROR: $*\n" >&2; }

if [ -z "$VERSION" ]; then
  err "Version required. Usage: $0 <version>"
  err "Example: $0 1.0.0"
  exit 1
fi

log "Publishing all iOS module SPM packages to GitHub (version: $VERSION)"

# Verify we're in a git repository
if [ ! -d "${REPO_ROOT}/.git" ]; then
  err "Not a git repository. Please initialize git first."
  exit 1
fi

# Check if remote is configured
cd "$REPO_ROOT"

if ! git remote get-url origin >/dev/null 2>&1; then
  err "Git remote 'origin' not configured"
  err "Please set up the GitHub repository first:"
  err "  git remote add origin https://github.com/yourorg/react-native-modules.git"
  exit 1
fi

# Verify all Package.swift files exist
IOS_DIR="${REPO_ROOT}/ios"
for module_dir in "${IOS_DIR}"/MKDRNModule*SPM; do
  if [ ! -f "${module_dir}/Package.swift" ]; then
    err "Package.swift not found in ${module_dir}"
    exit 1
  fi
done

# Stage all changes
git add -A

# Commit if there are changes
if ! git diff --staged --quiet; then
  git commit -m "Release v${VERSION} - All modules"
fi

# Push to main/master
BRANCH=$(git branch --show-current || echo "main")
git push origin "$BRANCH"

# Create and push tag
git tag -a "v${VERSION}" -m "Release v${VERSION} - All modules"
git push origin "v${VERSION}"

log "✅ Published all modules v${VERSION} to GitHub"
log "Repository: $(git remote get-url origin)"
log "Version: v${VERSION}"
log ""
log "To use in Xcode:"
log "  .package(url: \"$(git remote get-url origin)\", from: \"${VERSION}\")"
```

### Publishing Steps

1. **Generate SPM packages** (from monorepo):
   ```bash
   # In monorepo
   npm run framework:ios:spm:all
   ```

2. **Copy to modules repository**:
   ```bash
   # Copy generated packages
   cp -r frameworks/ios/MKDRNModule*SPM modules-repo/ios/
   ```

3. **Commit and tag**:
   ```bash
   cd modules-repo
   ./scripts/publish-ios-spm.sh 1.0.0
   ```

4. **Verify**:
   ```bash
   git tag -l
   # Should show: v1.0.0
   ```

---

## Pros and Cons

### ✅ Pros

1. **Scalability**
   - Easy to add new modules (just add a folder)
   - No need to create new repositories
   - Single repository to maintain

2. **Simplified Management**
   - One CI/CD pipeline
   - One set of GitHub settings
   - Easier to coordinate releases

3. **Better for Teams**
   - Single source of truth
   - Easier code reviews (all modules in one place)
   - Simpler onboarding

4. **SPM Native Support**
   - Works with Swift Package Manager out of the box
   - No custom tooling required
   - Standard Git-based versioning

5. **Coordinated Releases**
   - All modules version together
   - Easier to ensure compatibility
   - Single changelog

### ❌ Cons

1. **Shared Versioning**
   - All modules must version together
   - Can't have `products@1.0.0` and `cart@2.0.0` simultaneously
   - If one module needs a patch, all modules get a new version

2. **Larger Repository**
   - Repository grows with each module
   - More files to clone
   - Potentially slower Git operations (usually negligible)

3. **Less Granular Control**
   - Can't version modules independently
   - Can't have different release cycles per module
   - All modules tied to same version tag

4. **Potential Conflicts**
   - Multiple developers working on different modules
   - Merge conflicts possible (but manageable with good practices)

---

## Migration from Separate Repos

If you currently have separate repositories and want to consolidate:

### Step 1: Create New Repository

```bash
mkdir react-native-modules
cd react-native-modules
git init
git remote add origin https://github.com/yourorg/react-native-modules.git
```

### Step 2: Copy Modules

```bash
# Copy from separate repos
git clone https://github.com/yourorg/MKDRNModuleProductsSPM.git temp-products
cp -r temp-products/* ios/MKDRNModuleProductsSPM/
rm -rf temp-products

# Repeat for other modules
```

### Step 3: Update Package.swift Files

Ensure each `Package.swift` references the runtime correctly and doesn't assume it's at the repo root.

### Step 4: Initial Commit

```bash
git add -A
git commit -m "Initial commit - Consolidate all module SPM packages"
git push origin main
```

### Step 5: Create First Tag

```bash
git tag -a v1.0.0 -m "Initial release - All modules"
git push origin v1.0.0
```

### Step 6: Update Native Apps

Update your native apps to reference the new repository:

```swift
// Old (separate repos)
.package(url: "https://github.com/yourorg/MKDRNModuleProductsSPM.git", from: "1.0.0")

// New (single repo)
.package(url: "https://github.com/yourorg/react-native-modules.git", from: "1.0.0")
```

---

## Comparison with Separate Repos

| Aspect | Single Repository | Separate Repositories |
|--------|------------------|----------------------|
| **Scalability** | ✅ Easy to add modules | ❌ Need new repo per module |
| **Versioning** | ⚠️ Shared versioning | ✅ Independent versioning |
| **Management** | ✅ Simpler | ❌ More complex |
| **CI/CD** | ✅ Single pipeline | ❌ Multiple pipelines |
| **SPM Support** | ✅ Native support | ✅ Native support |
| **Release Cycles** | ⚠️ Coordinated | ✅ Independent |
| **Repository Size** | ⚠️ Grows over time | ✅ Smaller per repo |
| **Team Workflow** | ✅ Single source of truth | ⚠️ Multiple sources |

---

## Best Practices

### 1. Version Management

- Use semantic versioning consistently
- Update `CHANGELOG.md` for each release
- Tag releases immediately after merging

### 2. Module Organization

- Keep each module in its own directory
- Maintain separate `Package.swift` per module
- Use consistent naming conventions

### 3. Git Workflow

- Use feature branches for module changes
- Require PR reviews before merging
- Tag releases from `main` branch only

### 4. Documentation

- Maintain README.md for each module
- Document breaking changes in CHANGELOG.md
- Keep root README.md updated

### 5. Testing

- Test all modules before tagging a release
- Ensure compatibility between modules
- Run integration tests

---

## When to Split Back to Separate Repos

Consider splitting if:

1. **Independent Release Cycles**: Modules need completely different release schedules
2. **Different Teams**: Different teams own different modules and want isolation
3. **Open Source**: Some modules are open-sourced while others are private
4. **Repository Size**: Repository becomes too large (rare, but possible)
5. **Version Conflicts**: Frequent need for independent versioning

**Migration Path:**
- Extract module to new repository
- Update native apps to reference new repo
- Maintain old repo for backward compatibility (or deprecate)

---

## Summary

The **single repository strategy** is ideal when:
- ✅ You have many modules (5+)
- ✅ Modules are released together
- ✅ You want simpler management
- ✅ You prefer coordinated versioning

Use **separate repositories** when:
- ❌ Modules have independent release cycles
- ❌ Different teams own different modules
- ❌ You need granular version control

**Recommendation:** Start with a single repository. You can always split specific modules into separate repos later if needed.

---

## Related Documentation

- [3-Repository Architecture Guide](./3_REPO_ARCHITECTURE.md) - Complete architecture guide
- [3-Repository Quick Reference](./3_REPO_QUICK_REFERENCE.md) - Quick answers
- [iOS SPM Integration Guide](./IOS_SPM_INTEGRATION.md) - Detailed iOS integration
- [Native Integration Guide](../NATIVE_INTEGRATION.md) - Native integration overview

