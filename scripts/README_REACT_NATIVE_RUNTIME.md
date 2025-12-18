# React Native Runtime Generation Scripts

This guide explains how to generate React Native runtime packages for both iOS (SPM) and Android (AAR) platforms.

## Overview

These scripts generate platform-specific runtime packages that can be consumed by native iOS and Android applications:

- **iOS**: Swift Package Manager (SPM) package with React Native xcframeworks
- **Android**: Android Archive (AAR) with React Native dependencies

Both packages provide the React Native 0.81.5 runtime needed to embed React Native modules in native applications.

---

## Prerequisites

### Common Requirements
- **Node.js** >= 20
- **npm** (comes with Node.js)
- **Git** (for cloning React Native source if needed)

### iOS Requirements
- **macOS** (required for iOS builds)
- **Xcode** 14+ with Command Line Tools
- **CocoaPods** (`sudo gem install cocoapods`)
- **React Native 0.81.5** source project

### Android Requirements
- **Java Development Kit (JDK)** 11 or 17
- **Android SDK** (via Android Studio or standalone)
- **Gradle** (included with Android projects)
- **Android NDK** (if building native modules)

---

## Setup

### 1. iOS: Prepare React Native Source Project

The iOS script requires a React Native 0.81.5 project with CocoaPods installed.

#### Option A: Use Existing `rn-runtime-source` Directory

If you already have `rn-runtime-source/RnRuntimeSource` in the monorepo root:

```bash
cd rn-runtime-source/RnRuntimeSource
npm install
cd ios
pod install
```

#### Option B: Create New React Native Project

If `rn-runtime-source` doesn't exist, create it:

```bash
# From monorepo root
mkdir -p rn-runtime-source
cd rn-runtime-source

# Create React Native 0.81.5 project
npx react-native@0.81.5 init RnRuntimeSource --version 0.81.5

# Install dependencies
cd RnRuntimeSource
npm install

# Install iOS pods
cd ios
pod install
cd ../..
```

**Important**: The script expects the project at:
```
monorepo-root/
└── rn-runtime-source/
    └── RnRuntimeSource/
        ├── ios/
        │   ├── Podfile
        │   └── Pods/          ← Must exist (run pod install)
        └── package.json
```

### 2. Android: Verify Host Project Setup

The Android script uses an existing Gradle project. Verify it exists:

```bash
# Check if host project exists
ls -la frameworks/android/vsco-rn-host

# If missing, the script will fail with a clear error
```

The host project should have:
- `build.gradle` or `build.gradle.kts`
- `gradlew` (Gradle wrapper)
- `settings.gradle` or `settings.gradle.kts`
- `local.properties` (or it will be copied from `android-props/`)

### 3. Configure Android SDK (if needed)

If `local.properties` is missing, create it:

```bash
# From monorepo root
mkdir -p android-props
cat > android-props/local.properties <<EOF
sdk.dir=/Users/YOUR_USERNAME/Library/Android/sdk
EOF
```

Replace `/Users/YOUR_USERNAME/Library/Android/sdk` with your actual Android SDK path.

---

## Usage

### Generate iOS SPM Package

```bash
# From monorepo root
./scripts/generate-react-native-runtime-spm.sh
```

**Or using npm script:**
```bash
npm run framework:ios:spm:runtime
```

**What it does:**
1. Validates `rn-runtime-source/RnRuntimeSource` exists
2. Discovers React Native schemes from CocoaPods project
3. Builds xcframeworks for device and simulator
4. Collects React Native headers
5. Creates unified `VSCOReactNativeRuntime.xcframework`
6. Generates `Package.swift` with binary targets
7. Creates `Sources/React` target with React headers

**Output:**
```
frameworks/ios/VSCOReactNativeRuntime/
├── Package.swift
├── VSCOReactNativeRuntime.xcframework/
├── hermes.xcframework/
└── Sources/
    ├── VSCOReactNativeRuntime/
    │   ├── Headers/          ← React Native headers
    │   └── VSCOReactNativeRuntime.m
    └── React/
        ├── Headers/          ← React headers (for import React)
        └── React.m
```

**Build artifacts:**
- `build-rn-runtime/` - Temporary build files (can be cleaned)
- `dist-rn-runtime/` - Final xcframeworks and static libraries

### Generate Android AAR

```bash
# From monorepo root
./scripts/generate-react-native-runtime-host-aar.sh
```

**Or using npm script:**
```bash
npm run framework:android:aar:host
```

**What it does:**
1. Copies `local.properties` from `android-props/` if available
2. Builds `vsco-rn-host` AAR using Gradle
3. Publishes to Maven Local to generate POM file
4. Copies AAR and POM to distribution directory

**Output:**
```
frameworks/android/distribution/aars/
├── vsco-rn-host-release.aar
└── vsco-rn-host-release.pom

frameworks/android/vsco-rn-host/build/outputs/aar/
├── vsco-rn-host-release.aar
└── vsco-rn-host-release.pom
```

**What's included:**
- React Native runtime (`com.facebook.react:react-android:0.81.5`)
- Hermes engine (`com.facebook.react:hermes-android:0.81.5`)
- All transitive dependencies (fbjni, soloader, fresco, okhttp, okio, etc.)
- RNHost utilities

---

## Using Generated Packages

### iOS: Add SPM Package to Xcode

1. **Open your Xcode project**
2. **File → Add Package Dependencies...**
3. **Click "Add Local..."**
4. **Navigate to:** `frameworks/ios/VSCOReactNativeRuntime`
5. **Select your target** and add the package
6. **Wait for package resolution** (progress indicator in top bar)

**In your Swift code:**
```swift
import VSCOReactNativeRuntime
import React

// Create React Native bridge
let bundleURL = Bundle.main.url(forResource: "module-products", withExtension: "bundle")
let bridge = RCTBridge(bundleURL: bundleURL, moduleProvider: nil, launchOptions: nil)
let rootView = RCTRootView(bridge: bridge!, moduleName: "ModuleProducts", initialProperties: nil)
```

### Android: Add AAR to Gradle Project

**Option 1: Maven Local (Recommended)**

The AAR is automatically published to Maven Local. Add to your `app/build.gradle`:

```gradle
repositories {
    mavenLocal()
    // ... other repositories
}

dependencies {
    implementation 'com.vscorp:vsco-rn-host-sdk:1.0.0'
    // ... other dependencies
}
```

**Option 2: Local AAR File**

```gradle
dependencies {
    implementation files('libs/vsco-rn-host-release.aar')
    // Note: You'll also need to manually add transitive dependencies
}
```

**In your Kotlin/Java code:**
```kotlin
import com.facebook.react.ReactInstanceManager
import com.facebook.react.ReactRootView
import com.facebook.react.common.LifecycleState

// Create React Native instance
val reactInstanceManager = ReactInstanceManager.builder()
    .setApplication(application)
    .setCurrentActivity(this)
    .setBundleAssetName("module-products.bundle")
    .setJSMainModulePath("index")
    .addPackage(MainReactPackage())
    .setUseDeveloperSupport(BuildConfig.DEBUG)
    .setInitialLifecycleState(LifecycleState.RESUMED)
    .build()

val rootView = ReactRootView(this)
rootView.startReactApplication(reactInstanceManager, "ModuleProducts", null)
```

---

## Troubleshooting

### iOS Issues

#### Error: "RN runtime source dir not found"
**Solution:** Ensure `rn-runtime-source/RnRuntimeSource` exists. See [Setup](#1-ios-prepare-react-native-source-project).

#### Error: "Pods directory missing — run 'pod install'"
**Solution:**
```bash
cd rn-runtime-source/RnRuntimeSource/ios
pod install
```

#### Error: "No schemes detected in Pods.xcodeproj"
**Solution:** 
- Verify `pod install` completed successfully
- Check that `Pods.xcodeproj` exists
- Try cleaning: `rm -rf Pods Podfile.lock && pod install`

#### Error: "xcodebuild not found"
**Solution:** Install Xcode Command Line Tools:
```bash
xcode-select --install
```

#### Build Failures for Specific Schemes
**Note:** Some schemes may fail to build (e.g., due to signing issues). The script will continue with successfully built frameworks. Check build logs in `build-rn-runtime/` for details.

#### Package Resolution Issues in Xcode
**Solution:**
1. Close Xcode
2. Clear caches:
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData/*
   rm -rf ~/Library/Caches/org.swift.swiftpm
   ```
3. Open Xcode and wait for package resolution

### Android Issues

#### Error: "gradlew not found"
**Solution:** Ensure `frameworks/android/vsco-rn-host` exists with a valid Gradle project structure.

#### Error: "SDK location not found"
**Solution:** Create `android-props/local.properties` with your Android SDK path:
```properties
sdk.dir=/path/to/Android/sdk
```

#### Error: "POM file not found"
**Solution:** The script automatically publishes to Maven Local. If POM is missing:
1. Check that `./gradlew publishReleasePublicationToMavenLocal` succeeded
2. Verify Maven Local path: `~/.m2/repository/com/vscorp/vsco-rn-host-sdk/1.0.0/`

#### Build Failures
**Solution:**
- Check `frameworks/android/vsco-rn-host/build.gradle` for configuration issues
- Verify Android SDK and NDK are properly configured
- Check Gradle version compatibility

---

## Advanced Configuration

### Custom React Native Source Location (iOS)

Set `RN_RUNTIME_SOURCE_DIR` environment variable:

```bash
RN_RUNTIME_SOURCE_DIR=/path/to/custom/rn-project ./scripts/generate-react-native-runtime-spm.sh
```

### Parallel Build Jobs (iOS)

Control number of parallel builds:

```bash
MAX_PARALLEL_JOBS=4 ./scripts/generate-react-native-runtime-spm.sh
```

Default: Uses CPU count (max 8)

### Incremental Builds (iOS)

The script automatically skips already-built schemes. To force rebuild:

```bash
rm -rf build-rn-runtime dist-rn-runtime
./scripts/generate-react-native-runtime-spm.sh
```

---

## Output Structure

### iOS SPM Package

```
frameworks/ios/VSCOReactNativeRuntime/
├── Package.swift                    ← SPM package definition
├── VSCOReactNativeRuntime.xcframework/  ← Unified React Native runtime
├── hermes.xcframework/              ← Hermes JavaScript engine
├── Sources/
│   ├── VSCOReactNativeRuntime/
│   │   ├── Headers/                 ← React Native headers (non-React)
│   │   │   ├── ReactCommon/
│   │   │   ├── yoga/
│   │   │   └── ...
│   │   └── VSCOReactNativeRuntime.m
│   └── React/
│       ├── Headers/                 ← React headers (for import React)
│       │   ├── React/
│       │   ├── ReactCommon/
│       │   ├── yoga/
│       │   └── ...
│       └── React.m
└── README.md
```

### Android AAR

```
frameworks/android/distribution/aars/
├── vsco-rn-host-release.aar         ← Unified React Native host AAR
└── vsco-rn-host-release.pom         ← Maven POM with dependencies

frameworks/android/vsco-rn-host/build/outputs/aar/
├── vsco-rn-host-release.aar         ← Build output
└── vsco-rn-host-release.pom         ← Generated POM
```

---

## What's Included

### iOS Package

**Products:**
- `VSCOReactNativeRuntime` - Main runtime library
- `React` - React Native headers (for `import React`)

**Frameworks:**
- All React Native core frameworks (React, React-Core, React-jsi, etc.)
- Hermes engine
- Yoga layout engine
- Supporting libraries (RCT-Folly, DoubleConversion, glog)

**Headers:**
- 159+ public React Native headers
- Complete Brownfield integration support
- TurboModules support (RN 0.81.5)

### Android AAR

**Dependencies:**
- `com.facebook.react:react-android:0.81.5`
- `com.facebook.react:hermes-android:0.81.5`
- All transitive dependencies (fbjni, soloader, fresco, okhttp, okio, infer-annotation)

**Features:**
- Single AAR includes everything
- No need for separate runtime AARs
- Uses Maven dependencies directly

---

## Version Information

- **React Native Version:** 0.81.5
- **iOS Minimum Version:** iOS 14.0+
- **Android Minimum SDK:** Defined in host project (typically API 21+)
- **Swift Tools Version:** 5.9
- **Xcode Version:** 14+ (recommended)

---

## Cleanup

### Remove Build Artifacts

**iOS:**
```bash
rm -rf build-rn-runtime dist-rn-runtime
```

**Android:**
```bash
cd frameworks/android/vsco-rn-host
./gradlew clean
```

### Remove Generated Packages

**iOS:**
```bash
rm -rf frameworks/ios/VSCOReactNativeRuntime
```

**Android:**
```bash
rm -rf frameworks/android/distribution/aars/vsco-rn-host-release.*
```

---

## Related Scripts

- `generate-native-kit-ios.sh` - Generates native kit SPM package (includes Expo modules)
- `generate-native-kit-android.sh` - Generates native kit AAR (includes Expo modules)
- `generate-module-framework-spm.sh` - Generates individual module SPM packages
- `generate-module-framework-aar.sh` - Generates individual module AARs

---

## Support

For issues or questions:
1. Check build logs in `build-rn-runtime/` (iOS) or `frameworks/android/vsco-rn-host/build/` (Android)
2. Verify all prerequisites are installed
3. Ensure React Native 0.81.5 source project is properly set up
4. Check that CocoaPods (iOS) or Gradle (Android) are working correctly

---

## Quick Reference

### Generate Both Runtimes

```bash
# iOS
npm run framework:ios:spm:runtime

# Android
npm run framework:android:aar:host
```

### Publish to Maven Local

```bash
# Android AAR
npm run framework:android:aar:host:publish:local
```

### Clean and Rebuild

```bash
# iOS
rm -rf build-rn-runtime dist-rn-runtime
npm run framework:ios:spm:runtime

# Android
cd frameworks/android/vsco-rn-host
./gradlew clean
cd ../../..
npm run framework:android:aar:host
```

