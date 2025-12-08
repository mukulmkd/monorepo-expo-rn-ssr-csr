# Native Integration Guide

This document covers the complete workflow for generating Android AAR files and iOS SPM packages from this monorepo and integrating them into native Android and iOS applications.

> **Note:** This guide assumes you have already set up the monorepo and Verdaccio is running. See the main [README.md](./README.md) for monorepo setup.

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Quick Start](#quick-start)
4. [Android AAR Integration](#android-aar-integration)
5. [iOS SPM Integration](#ios-spm-integration)
6. [Complete Workflow](#complete-workflow)

---

## Overview

This monorepo generates native frameworks for both Android and iOS:

### Android AAR Files
- **`mkd-rn-host-sdk`** - Complete React Native runtime with all dependencies
- **`mkd-rn-module-products`** - Products listing module
- **`mkd-rn-module-cart`** - Shopping cart module
- **`mkd-rn-module-pdp`** - Product detail page module

### iOS SPM Packages
- **`MKDReactNativeRuntime`** - Complete React Native runtime with Hermes engine
- **`MKDRNModuleProductsSPM`** - Products listing module
- **`MKDRNModuleCartSPM`** - Shopping cart module
- **`MKDRNModulePDPSPM`** - Product detail page module

---

## Prerequisites

### Common Prerequisites

1. **Node.js LTS** (>=20) - [Download](https://nodejs.org/)
2. **Verdaccio Running** - Local npm registry (see [docs/LOCAL_REGISTRY.md](./docs/LOCAL_REGISTRY.md))
3. **Packages Published** - All packages published to Verdaccio

### Android-Specific Prerequisites

1. **Java Development Kit (JDK)** - Version 17 or higher
2. **Android SDK** - Required for building AAR files
3. **Android SDK Path** - Configured in `android-props/local.properties`

### iOS-Specific Prerequisites

1. **Xcode** - Version 14.0 or higher
2. **CocoaPods** - For building React Native dependencies (if using source build)

---

## Quick Start

### 1. Start Verdaccio

```bash
# Start Verdaccio in a separate terminal (keep it running)
npm run verdaccio:start
```

### 2. Configure npm and Publish Packages

```bash
# Configure npm scopes
npm config set @app:registry http://localhost:4873
npm config set @pkg:registry http://localhost:4873

# Login to Verdaccio (first time only)
npm adduser --registry http://localhost:4873

# Publish all packages
npm run publish:verdaccio
```

### 3. Generate Frameworks

**Android AARs:**
```bash
npm run framework:android:aar:host
npm run framework:android:aar:all
```

**iOS SPM Packages:**
```bash
npm run framework:ios:spm:runtime
npm run framework:ios:spm:all
```

### 4. Publish to Local Repositories

**Android (Maven Local):**
```bash
npm run framework:android:aar:host:publish:local
npm run framework:android:aar:products:publish:local
npm run framework:android:aar:cart:publish:local
npm run framework:android:aar:pdp:publish:local
```

**iOS (Local Packages):**
- Add packages directly in Xcode as local packages (see iOS integration guide)

---

## Android AAR Integration

### Generating AAR Files

#### Prerequisites

1. **Android SDK Setup**
   - Install Android Studio or Android SDK
   - Create `android-props/local.properties`:
     ```properties
     sdk.dir=/path/to/android/sdk
     ```

#### Generate Host AAR

```bash
npm run framework:android:aar:host
```

**Output:** `frameworks/android/distribution/aars/mkd-rn-host-release.aar`

#### Generate Module AARs

```bash
# Individual modules
npm run framework:android:aar:products
npm run framework:android:aar:cart
npm run framework:android:aar:pdp

# Or all at once
npm run framework:android:aar:all
```

**Output:** AARs in `frameworks/android/distribution/aars/`

### Publishing AAR Files

#### To Local Maven Repository

```bash
npm run framework:android:aar:host:publish:local
npm run framework:android:aar:products:publish:local
npm run framework:android:aar:cart:publish:local
npm run framework:android:aar:pdp:publish:local
```

**Location:** `~/.m2/repository/com/mkdcorp/`

#### To Central Artifactory

1. Configure Artifactory credentials:
   ```bash
   cp android-props/artifactory.properties.example android-props/artifactory.properties
   # Edit android-props/artifactory.properties with your credentials
   ```

2. Publish:
   ```bash
   npm run framework:android:aar:host:publish:central
   npm run framework:android:aar:products:publish:central
   npm run framework:android:aar:cart:publish:central
   npm run framework:android:aar:pdp:publish:central
   ```

### Integrating into Native Android App

#### Step 1: Configure Maven Repository

In `settings.gradle`:
```gradle
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        mavenLocal()  // For local Maven repository
    }
}
```

#### Step 2: Add Dependencies

In `app/build.gradle`:
```gradle
dependencies {
    // React Native Host SDK
    implementation 'com.mkdcorp:mkd-rn-host-sdk:0.1.0'
    
    // Module AARs
    implementation 'com.mkdcorp:mkd-rn-module-products:0.1.0'
    implementation 'com.mkdcorp:mkd-rn-module-cart:0.1.0'
    implementation 'com.mkdcorp:mkd-rn-module-pdp:0.1.0'
}
```

#### Step 3: Use in Activity

See [Android AAR Integration Guide](./docs/ANDROID_AAR_INTEGRATION.md#integrating-into-native-android-app) for complete Activity implementation.

---

## iOS SPM Integration

### Generating SPM Packages

#### Generate Runtime SPM Package

```bash
npm run framework:ios:spm:runtime
```

**Output:** `frameworks/ios/MKDReactNativeRuntime/`

#### Generate Module SPM Packages

```bash
# Individual modules
npm run framework:ios:spm:products
npm run framework:ios:spm:cart
npm run framework:ios:spm:pdp

# Or all at once
npm run framework:ios:spm:all
```

**Output:** SPM packages in `frameworks/ios/`

### Integrating into Native iOS App

#### Step 1: Add SPM Packages in Xcode

**Important:** Add packages in this order:
1. `MKDReactNativeRuntime` (base package - must be added first)
2. Module packages (Products, Cart, PDP)

**Method: Add Local Packages**

1. Open Xcode project
2. Select project → Package Dependencies tab
3. Click **+** → **Add Local...**
4. Navigate to `frameworks/ios/MKDReactNativeRuntime` → **Add Package**
5. Repeat for each module package

#### Step 2: Import and Use

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
        guard let bundleURL = Bundle.module.url(
            forResource: "module-products",
            withExtension: "bundle"
        ) else { return }

        bridge = RCTBridge(bundleURL: bundleURL, moduleProvider: nil, launchOptions: nil)
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
}
```

---

## Complete Workflow

### From Monorepo to Native Apps

**1. In Monorepo:**
```bash
# Start Verdaccio
npm run verdaccio:start

# Publish packages
npm run publish:verdaccio

# Generate Android AARs
npm run framework:android:aar:host
npm run framework:android:aar:all

# Publish AARs to Maven Local
npm run framework:android:aar:host:publish:local
npm run framework:android:aar:products:publish:local
npm run framework:android:aar:cart:publish:local
npm run framework:android:aar:pdp:publish:local

# Generate iOS SPM packages
npm run framework:ios:spm:runtime
npm run framework:ios:spm:all
```

**2. In Native Android App:**
- Add `mavenLocal()` to `settings.gradle`
- Add dependencies in `app/build.gradle`
- See [Android AAR Integration Guide](./docs/ANDROID_AAR_INTEGRATION.md) for details

**3. In Native iOS App:**
- Add SPM packages in Xcode (local packages)
- Import and use in ViewControllers
- See [iOS SPM Integration Guide](./docs/IOS_SPM_INTEGRATION.md) for details

---

## Available Scripts

### Android AAR Generation

- `npm run framework:android:aar:host` - Generate React Native runtime host AAR
- `npm run framework:android:aar:products` - Generate products module AAR
- `npm run framework:android:aar:cart` - Generate cart module AAR
- `npm run framework:android:aar:pdp` - Generate PDP module AAR
- `npm run framework:android:aar:all` - Generate all module AARs at once

### Android AAR Publishing

**Local Maven:**
- `npm run framework:android:aar:host:publish:local`
- `npm run framework:android:aar:products:publish:local`
- `npm run framework:android:aar:cart:publish:local`
- `npm run framework:android:aar:pdp:publish:local`

**Central Artifactory:**
- `npm run framework:android:aar:host:publish:central`
- `npm run framework:android:aar:products:publish:central`
- `npm run framework:android:aar:cart:publish:central`
- `npm run framework:android:aar:pdp:publish:central`

### iOS SPM Generation

- `npm run framework:ios:spm:runtime` - Generate React Native runtime SPM package
- `npm run framework:ios:spm:products` - Generate products module SPM package
- `npm run framework:ios:spm:cart` - Generate cart module SPM package
- `npm run framework:ios:spm:pdp` - Generate PDP module SPM package
- `npm run framework:ios:spm:all` - Generate all module SPM packages at once

---

## Configuration

### Android Properties

All Android configuration is centralized in `android-props/`:

- **`android-props/local.properties`** - Android SDK location (required)
  ```properties
  sdk.dir=/path/to/android/sdk
  ```

- **`android-props/artifactory.properties`** - Artifactory credentials (optional)
  - Copy from `android-props/artifactory.properties.example`
  - Fill in your Artifactory credentials

The scripts automatically copy `local.properties` to all generated AAR projects.

---

## Troubleshooting

### Common Issues

| Issue | Quick Fix |
|-------|-----------|
| **"SDK location not found"** | Create `android-props/local.properties` with `sdk.dir=/path/to/android/sdk` |
| **"Verdaccio is not running"** | Run `npm run verdaccio:start` in a separate terminal |
| **"Module not found in Verdaccio"** | Run `npm run publish:verdaccio` to publish packages |
| **"AAR not found in distribution"** | Generate AARs first: `npm run framework:android:aar:host` |
| **"Could not find com.mkdcorp:mkd-rn-host-sdk"** | Publish to Maven Local: `npm run framework:android:aar:host:publish:local` |
| **"Missing package product 'MKDReactNativeRuntime'"** | Add `MKDReactNativeRuntime` package first in Xcode |

For detailed troubleshooting, see:
- [Android AAR Integration Guide](./docs/ANDROID_AAR_INTEGRATION.md#troubleshooting)
- [iOS SPM Integration Guide](./docs/IOS_SPM_INTEGRATION.md#troubleshooting)

---

## Distribution Architecture

### Current Structure

```
monorepo-expo-rn-ssr-csr/
├── frameworks/
│   ├── android/          # Android AAR projects
│   │   ├── mkd-rn-host/  # Runtime host (tracked in git)
│   │   └── mkd-rn-module-*/  # Module projects (generated)
│   └── ios/              # iOS SPM packages
│       ├── MKDReactNativeRuntime/
│       └── MKDRNModule*SPM/
└── android-props/        # Centralized Android configuration
```

### Future Structure (Planned)

- **Runtime Repository** - Contains `mkd-rn-host` AAR and `MKDReactNativeRuntime` SPM
- **Module Repository** - Contains module AARs and SPM packages
- **This Monorepo** - Contains source code, Verdaccio, and generation scripts

---

## Related Documentation

- **[Android AAR Integration Guide](./docs/ANDROID_AAR_INTEGRATION.md)** - Complete Android integration guide
- **[iOS SPM Integration Guide](./docs/IOS_SPM_INTEGRATION.md)** - Complete iOS integration guide
- **[3-Repository Architecture Guide](./docs/3_REPO_ARCHITECTURE.md)** - Step-by-step guide for splitting into 3 repositories
- **[3-Repository Quick Reference](./docs/3_REPO_QUICK_REFERENCE.md)** - Quick answers to common questions
- **[Local Registry Guide](./docs/LOCAL_REGISTRY.md)** - Setting up and using Verdaccio
- **[Packages Documentation](./docs/PACKAGES.md)** - Package API reference
- **[Main README](./README.md)** - Monorepo setup and development guide

