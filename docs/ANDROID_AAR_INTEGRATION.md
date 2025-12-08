# Android AAR Integration Guide

Complete guide for generating Android AAR files from this monorepo and integrating them into native Android applications.

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Monorepo Setup](#monorepo-setup)
4. [Generating AAR Files](#generating-aar-files)
5. [Publishing AAR Files](#publishing-aar-files)
6. [Integrating into Native Android App](#integrating-into-native-android-app)
7. [Troubleshooting](#troubleshooting)

---

## Overview

This monorepo generates Android Archive (AAR) files that can be integrated into any native Android application:

- **`mkd-rn-host-sdk`** - Complete React Native runtime with all dependencies
- **`mkd-rn-module-products`** - Products listing module
- **`mkd-rn-module-cart`** - Shopping cart module
- **`mkd-rn-module-pdp`** - Product detail page module

All AARs are published to Maven Local (for development) or Artifactory (for production distribution).

---

## Prerequisites

### Required Software

1. **Node.js LTS** (>=20) - [Download](https://nodejs.org/)
2. **Java Development Kit (JDK)** - Version 17 or higher
   - **macOS**: `brew install openjdk@17`
   - **Linux**: `sudo apt-get install openjdk-17-jdk`
   - **Windows**: Download from [Oracle](https://www.oracle.com/java/technologies/downloads/)
3. **Android SDK** - Required for building AAR files
   - Install via [Android Studio](https://developer.android.com/studio) (recommended)
   - Or install via command line tools
4. **Gradle** - Included via Gradle Wrapper (no separate installation needed)

### Android SDK Setup

**Step 1: Install Android Studio**

1. Download and install [Android Studio](https://developer.android.com/studio)
2. Complete the setup wizard
3. SDK will be installed to:
   - **macOS/Linux**: `~/Library/Android/sdk` or `~/Android/Sdk`
   - **Windows**: `%LOCALAPPDATA%\Android\Sdk`

**Step 2: Configure Android SDK Path**

Create `android-props/local.properties` in the monorepo root:

```properties
sdk.dir=/path/to/your/android/sdk
```

**Example (macOS):**

```properties
sdk.dir=/Users/username/Library/Android/sdk
```

**Example (Windows):**

```properties
sdk.dir=C:\\Users\\username\\AppData\\Local\\Android\\Sdk
```

**Step 3: Install Required SDK Components**

```bash
# Install Android SDK Platform 34
sdkmanager "platforms;android-34"

# Install build tools
sdkmanager "build-tools;34.0.0"
```

---

## Monorepo Setup

### Step 1: Start Verdaccio (Required for Module AARs)

Module AARs fetch JavaScript bundles from Verdaccio, so it must be running:

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

## Generating AAR Files

### Configuration

All Android configuration is centralized in the `android-props/` folder:

- **`android-props/local.properties`** - Android SDK location (copied to all generated projects)
- **`android-props/artifactory.properties`** - Artifactory credentials (for publishing to central repo)

### Generate Host AAR (React Native Runtime)

```bash
npm run framework:android:aar:host
```

**What it does:**

1. Builds the React Native host AAR with all dependencies
2. Copies AAR to `frameworks/android/distribution/aars/mkd-rn-host-release.aar`
3. Automatically copies `local.properties` from `android-props/`

**Expected output:**

```
✅ mkd-rn-host AAR built successfully
  Location: frameworks/android/distribution/aars/mkd-rn-host-release.aar
  Size: 7.4K
```

### Generate Module AARs

```bash
# Generate individual module AARs
npm run framework:android:aar:products
npm run framework:android:aar:cart
npm run framework:android:aar:pdp

# Or generate all modules at once
npm run framework:android:aar:all
```

**What it does (for each module):**

1. Fetches module from Verdaccio
2. Creates JavaScript bundle for Android
3. Creates Android Library project structure
4. Builds AAR file
5. Copies AAR to `frameworks/android/distribution/aars/`
6. Automatically copies `local.properties` from `android-props/`

**Expected output for each module:**

```
✅ Framework ready for distribution!
  • AAR file: frameworks/android/distribution/aars/mkd-rn-module-products-release.aar
  • Size: ~493K
```

### Verify Generated AARs

```bash
# Check distribution directory
ls -lh frameworks/android/distribution/aars/

# Expected files:
# - mkd-rn-host-release.aar (7.4K)
# - mkd-rn-module-products-release.aar (~493K)
# - mkd-rn-module-cart-release.aar (~492K)
# - mkd-rn-module-pdp-release.aar (~493K)
```

---

## Publishing AAR Files

### Publishing to Local Maven Repository

Publish AARs to your local Maven repository (`~/.m2/repository`) for development:

```bash
# Publish host AAR
npm run framework:android:aar:host:publish:local

# Publish module AARs
npm run framework:android:aar:products:publish:local
npm run framework:android:aar:cart:publish:local
npm run framework:android:aar:pdp:publish:local
```

**Location:** `~/.m2/repository/com/mkdcorp/` (macOS/Linux) or `%USERPROFILE%\.m2\repository\com\mkdcorp\` (Windows)

**Version:** Uses version from `package.json` (currently `0.1.0`) or can be specified via `VERSION` environment variable.

### Publishing to Central Artifactory

**Prerequisites:**

1. Create `android-props/artifactory.properties` from `android-props/artifactory.properties.example`
2. Fill in your Artifactory credentials

```bash
# Copy example file
cp android-props/artifactory.properties.example android-props/artifactory.properties

# Edit with your credentials
# artifactory_contextUrl=https://your-artifactory.com/artifactory/mobile-apps-artifacts
# mobileRepo=mobile
# artifactory_user=your-username
# artifactory_password=your-password
```

**Publish to Artifactory:**

```bash
# Publish with version (defaults to package.json version if not specified)
npm run framework:android:aar:host:publish:central
npm run framework:android:aar:products:publish:central
npm run framework:android:aar:cart:publish:central
npm run framework:android:aar:pdp:publish:central

# Or specify version explicitly
VERSION=1.0.0 npm run framework:android:aar:host:publish:central
```

---

## Integrating into Native Android App

### Step 1: Configure Maven Local Repository

In your native Android app's `settings.gradle`:

```gradle
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()

        // Add Maven Local for development
        mavenLocal()  // ~/.m2/repository

        // For production, add Artifactory repository:
        // maven {
        //     url = uri("https://your-artifactory.com/artifactory/mobile-apps-artifacts/mobile")
        //     credentials {
        //         username = project.findProperty("artifactory_user") ?: ""
        //         password = project.findProperty("artifactory_password") ?: ""
        //     }
        // }
    }
}
```

### Step 2: Add AAR Dependencies

In your app's `app/build.gradle`:

```gradle
dependencies {
    // AndroidX dependencies
    implementation 'androidx.core:core-ktx:1.12.0'
    implementation 'androidx.appcompat:appcompat:1.6.1'
    // ... other dependencies

    // ============================================
    // React Native Host SDK (from Maven Local)
    // ============================================
    // Single unified AAR with all React Native dependencies
    implementation 'com.mkdcorp:mkd-rn-host-sdk:0.1.0'

    // ============================================
    // Module Framework AARs (from Maven Local)
    // ============================================
    implementation 'com.mkdcorp:mkd-rn-module-products:0.1.0'
    implementation 'com.mkdcorp:mkd-rn-module-cart:0.1.0'
    implementation 'com.mkdcorp:mkd-rn-module-pdp:0.1.0'
}
```

### Step 3: Configure Android Build

Ensure your `app/build.gradle` has:

```gradle
android {
    namespace 'com.yourapp'
    compileSdk 34

    defaultConfig {
        minSdk 24  // React Native 0.81.5 requires minSdk 24
        targetSdk 34
        // ...
    }

    // Handle native library conflicts
    packagingOptions {
        pickFirst '**/*.so'
    }
}
```

### Step 4: Use in Your Activity

Create an Activity to host a React Native module:

```kotlin
import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import com.facebook.react.ReactRootView
import com.facebook.react.ReactInstanceManager
import com.facebook.react.ReactApplication
import com.facebook.react.common.LifecycleState
import com.facebook.react.shell.MainReactPackage
import com.mkdcorp.rnhost.RNHost

class ProductsActivity : AppCompatActivity() {
    private var reactRootView: ReactRootView? = null
    private var reactInstanceManager: ReactInstanceManager? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Initialize React Native
        reactInstanceManager = ReactInstanceManager.builder()
            .setApplication(application as ReactApplication)
            .setCurrentActivity(this)
            .setBundleAssetName("index.android.bundle")
            .setJSMainModulePath("index")
            .addPackage(MainReactPackage())
            .setUseDeveloperSupport(BuildConfig.DEBUG)
            .setInitialLifecycleState(LifecycleState.RESUMED)
            .build()

        // Create React Root View
        reactRootView = ReactRootView(this).also {
            it.startReactApplication(reactInstanceManager, "ModuleProducts", null)
            setContentView(it)
        }
    }

    override fun onPause() {
        super.onPause()
        reactInstanceManager?.onHostPause(this)
    }

    override fun onResume() {
        super.onResume()
        reactInstanceManager?.onHostResume(this, this)
    }

    override fun onDestroy() {
        super.onDestroy()
        reactRootView?.unmountReactApplication()
        reactRootView = null
        reactInstanceManager = null
    }
}
```

### Step 5: Sync and Build

```bash
# Sync Gradle files in Android Studio
# Or from command line:
cd /path/to/native-android-app
./gradlew build
```

---

## Troubleshooting

### Issue 1: "SDK location not found"

**Error:**

```
SDK location not found. Define a valid SDK location with an ANDROID_HOME environment variable or by setting the sdk.dir path in your project's local.properties file.
```

**Solution:**

1. Ensure `android-props/local.properties` exists with correct SDK path
2. The script automatically copies it to generated projects
3. If issue persists, manually create `local.properties` in the AAR project:
   ```bash
   cd frameworks/android/mkd-rn-host
   echo "sdk.dir=/path/to/android/sdk" > local.properties
   ```

### Issue 2: "Verdaccio is not running"

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

### Issue 3: "Module not found in Verdaccio"

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

### Issue 4: "AAR not found in distribution folder"

**Error:**

```
AAR not found in distribution folder!
Expected location: frameworks/android/distribution/aars/mkd-rn-host-release.aar
```

**Solution:**

```bash
# Generate the AAR first
npm run framework:android:aar:host
```

### Issue 5: "Could not find com.mkdcorp:mkd-rn-host-sdk:0.1.0"

**Error:**

```
Could not find com.mkdcorp:mkd-rn-host-sdk:0.1.0
```

**Solution:**

```bash
# Publish AARs to local Maven first
npm run framework:android:aar:host:publish:local
npm run framework:android:aar:products:publish:local
npm run framework:android:aar:cart:publish:local
npm run framework:android:aar:pdp:publish:local

# Verify AARs are in Maven Local
ls ~/.m2/repository/com/mkdcorp/
```

### Issue 6: "Java version mismatch"

**Error:**

```
Unsupported class file major version 61
```

**Solution:**

- Ensure JDK 17+ is installed and in PATH:
  ```bash
  java -version  # Should show version 17 or higher
  ```

### Issue 7: "Permission denied" on gradlew

**Error:**

```
Permission denied: ./gradlew
```

**Solution:**

```bash
# Make gradlew executable
chmod +x frameworks/android/*/gradlew
```

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

# 3. Generate all AARs
npm run framework:android:aar:host
npm run framework:android:aar:products
npm run framework:android:aar:cart
npm run framework:android:aar:pdp

# 4. Publish all AARs to local Maven
npm run framework:android:aar:host:publish:local
npm run framework:android:aar:products:publish:local
npm run framework:android:aar:cart:publish:local
npm run framework:android:aar:pdp:publish:local

# 5. In native Android app, add dependencies (see Step 2 above)
# 6. Sync Gradle and build
```

---

## Important Notes

- **First build takes time** - Gradle downloads dependencies (5-10 minutes)
- **Subsequent builds are faster** - Gradle caches dependencies
- **AAR files are platform-independent** - Generated AARs work on any Android system
- **Version management** - AAR versions are controlled via `package.json` or `VERSION` environment variable
- **Centralized configuration** - All Android properties in `android-props/` folder
- **frameworks/android can be deleted** - Everything can be regenerated from `android-props/` configuration

---

## Related Documentation

- **[iOS SPM Integration](./IOS_SPM_INTEGRATION.md)** - iOS Swift Package Manager integration
- **[Local Registry Guide](./LOCAL_REGISTRY.md)** - Setting up and using Verdaccio
- **[Packages Documentation](./PACKAGES.md)** - Package API reference
