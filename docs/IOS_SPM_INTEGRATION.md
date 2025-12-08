# iOS SPM Integration Guide

Complete guide for generating iOS Swift Package Manager (SPM) packages from this monorepo and integrating them into native iOS applications.

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Monorepo Setup](#monorepo-setup)
4. [Generating SPM Packages](#generating-spm-packages)
5. [Integrating into Native iOS App](#integrating-into-native-ios-app)
6. [Troubleshooting](#troubleshooting)

---

## Overview

This monorepo generates Swift Package Manager (SPM) packages that can be integrated into any native iOS Xcode project:

- **`MKDReactNativeRuntime`** - Complete React Native runtime with Hermes engine
- **`MKDRNModuleProductsSPM`** - Products listing module
- **`MKDRNModuleCartSPM`** - Shopping cart module
- **`MKDRNModulePDPSPM`** - Product detail page module

All SPM packages are distributed as local packages (for development) or can be published to Git repositories (for production).

---

## Prerequisites

### Required Software

1. **Node.js LTS** (>=20) - [Download](https://nodejs.org/)
2. **Xcode** - Version 14.0 or higher (for iOS development)
3. **CocoaPods** - For building React Native dependencies
   ```bash
   sudo gem install cocoapods
   ```
4. **React Native Source Project** - Required for building React Native runtime
   - Must be React Native 0.81.5
   - Located at `rn-runtime-source/RnRuntimeSource/` (if using source build)

---

## Monorepo Setup

### Step 1: Start Verdaccio (Required for Module SPMs)

Module SPM packages fetch JavaScript bundles from Verdaccio, so it must be running:

```bash
# Start Verdaccio in a separate terminal (keep it running)
npm run verdaccio:start
```

**Expected output:**
```
warn --- http address - http://localhost:4873/ - verdaccio/6.0.5
```

**⚠️ Keep this terminal running** - Verdaccio must stay running.

### Step 2: Configure npm Scopes

```bash
# Configure npm to use Verdaccio for @app and @pkg scopes
npm config set @app:registry http://localhost:4873
npm config set @pkg:registry http://localhost:4873
```

### Step 3: Login to Verdaccio (First Time Only)

```bash
npm adduser --registry http://localhost:4873
```

When prompted:
- **Username**: Enter any username (e.g., `developer`)
- **Password**: Enter any password
- **Email**: Enter any email

### Step 4: Publish Packages to Verdaccio

```bash
# Publish all workspace packages to Verdaccio
npm run publish:verdaccio
```

**Expected output:**
```
✅ Published @pkg/core@0.1.0
✅ Published @pkg/state@0.1.5
✅ Published @app/module-products@0.1.8
✅ Published @app/module-cart@0.1.8
✅ Published @app/module-pdp@0.1.8
```

---

## Generating SPM Packages

### Generate React Native Runtime SPM Package

```bash
npm run framework:ios:spm:runtime
```

**What it does:**
1. Builds React Native runtime xcframework with Hermes engine
2. Creates SPM package structure in `frameworks/ios/MKDReactNativeRuntime/`
3. Includes device and simulator slices (ios-arm64, ios-arm64_x86_64-simulator)
4. Generates `Package.swift` with proper binary targets

**Expected output:**
```
✅ React Native Runtime SPM package generated
  Location: frameworks/ios/MKDReactNativeRuntime/
  Package: MKDReactNativeRuntime
```

### Generate Module SPM Packages

```bash
# Generate individual module SPM packages
npm run framework:ios:spm:products
npm run framework:ios:spm:cart
npm run framework:ios:spm:pdp

# Or generate all modules at once
npm run framework:ios:spm:all
```

**What it does (for each module):**
1. Fetches module from Verdaccio
2. Creates JavaScript bundle for iOS
3. Creates Swift wrapper class
4. Creates SPM package structure
5. Generates `Package.swift` with dependency on `MKDReactNativeRuntime`

**Expected output for each module:**
```
✅ Framework ready for distribution!
  • Package: MKDRNModuleProductsSPM
  • Location: frameworks/ios/MKDRNModuleProductsSPM/
  • Bundle: module-products.bundle (~2.9MB)
```

### Verify Generated SPM Packages

```bash
# Check generated packages
ls -la frameworks/ios/

# Expected packages:
# - MKDReactNativeRuntime/
# - MKDRNModuleProductsSPM/
# - MKDRNModuleCartSPM/
# - MKDRNModulePDPSPM/
```

---

## Integrating into Native iOS App

### Step 1: Add SPM Packages to Xcode Project

**Important:** Add packages in this order:
1. `MKDReactNativeRuntime` (base package - must be added first)
2. Module packages (Products, Cart, PDP)

**Method 1: Add Local Packages (Recommended for Development)**

1. Open your Xcode project
2. Select your project in the navigator
3. Select your app target
4. Go to **Package Dependencies** tab
5. Click **+** button
6. Select **Add Local...**
7. Navigate to `frameworks/ios/MKDReactNativeRuntime` and click **Add Package**
8. Repeat for each module package:
   - `frameworks/ios/MKDRNModuleProductsSPM`
   - `frameworks/ios/MKDRNModuleCartSPM`
   - `frameworks/ios/MKDRNModulePDPSPM`

**Method 2: Add from Git Repository (For Production)**

If packages are published to Git repositories:

1. In Xcode, go to **File → Add Package Dependencies...**
2. Enter Git URL: `https://github.com/yourorg/MKDReactNativeRuntime.git`
3. Select version: `Up to Next Major Version` from `1.0.0`
4. Click **Add Package**
5. Repeat for each module package

### Step 2: Import Packages in Swift Code

```swift
import UIKit
import React
import MKDReactNativeRuntime
import MKDRNModuleProductsSPM
import MKDRNModuleCartSPM
import MKDRNModulePDPSPM
```

### Step 3: Create ViewController to Host Module

```swift
import UIKit
import React
import MKDReactNativeRuntime
import MKDRNModuleProductsSPM

class ProductsViewController: UIViewController {
    var reactRootView: RCTRootView?
    var bridge: RCTBridge?

    override func viewDidLoad() {
        super.viewDidLoad()
        loadReactNativeModule()
    }

    func loadReactNativeModule() {
        // Get bundle URL from module package
        guard let bundleURL = Bundle.module.url(
            forResource: "module-products",
            withExtension: "bundle"
        ) else {
            print("❌ Bundle not found")
            return
        }

        // Create React Native bridge
        bridge = RCTBridge(bundleURL: bundleURL, moduleProvider: nil, launchOptions: nil)
        
        // Create React Root View
        let rootView = RCTRootView(
            bridge: bridge!,
            moduleName: "ModuleProducts",
            initialProperties: nil
        )

        rootView.backgroundColor = .white
        self.view = rootView
        self.reactRootView = rootView
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        bridge?.invalidate()
    }

    deinit {
        bridge?.invalidate()
    }
}
```

### Step 4: Configure AppDelegate (if needed)

If you need to configure React Native globally:

```swift
import UIKit
import React
import MKDReactNativeRuntime

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    var bridge: RCTBridge?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Configure React Native bridge if needed
        return true
    }
}
```

### Step 5: Build and Run

1. In Xcode, select your target device or simulator
2. Press **Cmd+B** to build
3. Press **Cmd+R** to run

---

## Package Structure

### MKDReactNativeRuntime Package

```
MKDReactNativeRuntime/
├── Package.swift
├── Sources/
│   └── MKDReactNativeRuntime/
│       └── MKDReactNativeRuntime.swift
└── MKDReactNativeRuntime.xcframework/
    ├── ios-arm64/
    ├── ios-arm64_x86_64-simulator/
    └── Info.plist
```

### Module Packages (e.g., MKDRNModuleProductsSPM)

```
MKDRNModuleProductsSPM/
├── Package.swift
└── Sources/
    └── MKDRNModuleProductsSPM/
        ├── MKDRNModuleProductsSPM.swift
        └── Resources/
            └── module-products.bundle
```

---

## Troubleshooting

### Issue 1: "Verdaccio is not running"

**Error:**
```
‼️ ERROR: Verdaccio is not running on http://localhost:4873
```

**Solution:**
```bash
# Start Verdaccio in a separate terminal
npm run verdaccio:start

# Verify it's running
curl http://localhost:4873
```

### Issue 2: "Module not found in Verdaccio"

**Error:**
```
npm ERR! 404 '@app/module-products@latest' is not in the npm registry
```

**Solution:**
```bash
# Ensure Verdaccio is running
npm run verdaccio:start

# Publish packages to Verdaccio
npm run publish:verdaccio

# Verify package is available
npm view @app/module-products --registry http://localhost:4873
```

### Issue 3: "Missing package product 'MKDReactNativeRuntime'"

**Error:**
```
Missing package product 'MKDReactNativeRuntime'
```

**Solution:**
1. Ensure `MKDReactNativeRuntime` is added to Xcode project first
2. Add module packages after runtime package
3. Clean build folder: **Product → Clean Build Folder** (Cmd+Shift+K)
4. Rebuild: **Product → Build** (Cmd+B)

### Issue 4: "Cannot open file handle for file at path: .../MKDReactNativeRuntime.framework"

**Error:**
```
Cannot open file handle for file at path: .../MKDReactNativeRuntime.framework
The file "MKDReactNativeRuntime.framework" doesn't exist.
```

**Solution:**
1. Verify xcframework was generated correctly:
   ```bash
   ls -la frameworks/ios/MKDReactNativeRuntime/MKDReactNativeRuntime.xcframework/
   ```
2. Regenerate the runtime package:
   ```bash
   npm run framework:ios:spm:runtime
   ```
3. Remove and re-add the package in Xcode

### Issue 5: "Bundle not found" at runtime

**Error:**
```
Bundle not found: module-products.bundle
```

**Solution:**
1. Verify bundle exists in package:
   ```bash
   ls -la frameworks/ios/MKDRNModuleProductsSPM/Sources/MKDRNModuleProductsSPM/Resources/
   ```
2. Check bundle is included in Package.swift resources
3. Use `Bundle.module` to access resources:
   ```swift
   guard let bundleURL = Bundle.module.url(
       forResource: "module-products",
       withExtension: "bundle"
   ) else { return }
   ```

### Issue 6: "Package dependency graph error"

**Error:**
```
Package dependency graph error: Could not resolve package dependencies
```

**Solution:**
1. Ensure all packages are in the same directory structure:
   ```
   frameworks/ios/
   ├── MKDReactNativeRuntime/
   ├── MKDRNModuleProductsSPM/
   ├── MKDRNModuleCartSPM/
   └── MKDRNModulePDPSPM/
   ```
2. Verify `Package.swift` files use correct relative paths
3. Remove and re-add packages in Xcode
4. Clean derived data: `rm -rf ~/Library/Developer/Xcode/DerivedData`

### Issue 7: "dsymutil warnings" (Harmless)

**Warning:**
```
warning: (arm64) skipping debug map object with duplicate name and timestamp: 1970-01-01
```

**Solution:**
- These warnings are harmless and can be ignored
- They occur when combining many static libraries
- They do not affect app functionality

---

## Complete Workflow Example

### From Scratch to Native App Integration

```bash
# 1. Start Verdaccio
npm run verdaccio:start  # Keep running in separate terminal

# 2. Configure npm and publish packages
npm config set @app:registry http://localhost:4873
npm config set @pkg:registry http://localhost:4873
npm adduser --registry http://localhost:4873
npm run publish:verdaccio

# 3. Generate React Native Runtime SPM package
npm run framework:ios:spm:runtime

# 4. Generate all module SPM packages
npm run framework:ios:spm:all

# 5. In Xcode, add packages (see Step 1 above)
# 6. Import and use in ViewControllers (see Step 3 above)
# 7. Build and run
```

---

## Distribution Options

### Option 1: Local Distribution (Development)

Maintain the directory structure and add packages as local packages in Xcode:

```
frameworks/ios/
├── MKDReactNativeRuntime/          ← Required base package
├── MKDRNModuleProductsSPM/         ← Depends on ../MKDReactNativeRuntime
├── MKDRNModuleCartSPM/             ← Depends on ../MKDReactNativeRuntime
└── MKDRNModulePDPSPM/              ← Depends on ../MKDReactNativeRuntime
```

**Pros:**
- ✅ Works immediately with current Package.swift files
- ✅ Simple for local/team distribution
- ✅ No Git repositories needed

**Cons:**
- ❌ Requires distributing all packages together
- ❌ Directory structure must be maintained

### Option 2: Git Repository Distribution (Production)

Publish each package to a Git repository and use URL-based dependencies:

1. Create Git repositories for each package
2. Update `Package.swift` to use Git URLs:
   ```swift
   dependencies: [
       .package(url: "https://github.com/yourorg/MKDReactNativeRuntime.git", from: "1.0.0")
   ]
   ```
3. Tag releases with semantic versions
4. Add packages via Xcode: **File → Add Package Dependencies...**

**Pros:**
- ✅ Independent distribution of each package
- ✅ Version control and semantic versioning
- ✅ Works with Xcode's remote package support

**Cons:**
- ❌ Requires Git repositories for each package
- ❌ Need to manage versions and tags

---

## Important Notes

- **First build takes time** - Building React Native from source (20-30 minutes)
- **Subsequent builds are faster** - Scripts skip already-built schemes
- **Package dependencies** - Module packages depend on `MKDReactNativeRuntime` - add it first
- **Directory structure** - For local distribution, maintain relative paths between packages
- **Version management** - SPM packages use semantic versioning

---

## Related Documentation

- **[Android AAR Integration](./ANDROID_AAR_INTEGRATION.md)** - Android AAR integration guide
- **[Local Registry Guide](./LOCAL_REGISTRY.md)** - Setting up and using Verdaccio
- **[Packages Documentation](./PACKAGES.md)** - Package API reference

