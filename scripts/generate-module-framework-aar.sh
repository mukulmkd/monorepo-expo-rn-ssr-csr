#!/usr/bin/env bash
set -euo pipefail

########################################
# Module Framework AAR Generator
#
# Generates Android AAR files for React Native modules
# that are published to Verdaccio.
#
# Usage:
#   ./scripts/generate-module-framework-aar.sh <module-name>
#   Example: ./scripts/generate-module-framework-aar.sh products
#
# Module names: products, cart, pdp
#
# Workflow:
#   1. Fetch latest module from Verdaccio
#   2. Create JavaScript bundle for Android
#   3. Create Android Library project structure
#   4. Create Kotlin wrapper class
#   5. Build AAR file using Gradle
#
########################################

MONOREPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Module name parameter
MODULE_NAME="${1:-}"
if [ -z "$MODULE_NAME" ]; then
  echo "Usage: $0 <module-name>"
  echo "Module names: products, cart, pdp"
  exit 1
fi

# Normalize module name
case "$MODULE_NAME" in
  products|Products|PRODUCTS)
    MODULE_NAME="products"
    MODULE_PACKAGE="@app/module-products"
    MODULE_COMPONENT="ModuleProducts"
    ;;
  cart|Cart|CART)
    MODULE_NAME="cart"
    MODULE_PACKAGE="@app/module-cart"
    MODULE_COMPONENT="ModuleCart"
    ;;
  pdp|PDP|Pdp)
    MODULE_NAME="pdp"
    MODULE_PACKAGE="@app/module-pdp"
    MODULE_COMPONENT="ModulePDP"
    ;;
  *)
    echo "Error: Unknown module name: $MODULE_NAME"
    echo "Valid module names: products, cart, pdp"
    exit 1
    ;;
esac

# Configuration
FRAMEWORK_NAME="${MODULE_COMPONENT}Framework"  # ModuleProductsFramework, ModuleCartFramework, etc.
FRAMEWORK_DIR="${MONOREPO_ROOT}/frameworks/android/${FRAMEWORK_NAME}"
BUILD_DIR="${FRAMEWORK_DIR}/build"
DIST_DIR="${FRAMEWORK_DIR}/dist"
SOURCES_DIR="${FRAMEWORK_DIR}/src/main"
ASSETS_DIR="${SOURCES_DIR}/assets"

# Convert module name to lowercase (bash 3.2 compatible)
MODULE_NAME_LOWER=$(echo "$MODULE_NAME" | tr '[:upper:]' '[:lower:]')
JAVA_DIR="${SOURCES_DIR}/java/com/yourorg/${MODULE_NAME_LOWER}"
BUNDLE_FILE="${ASSETS_DIR}/module-${MODULE_NAME}.bundle"

# Temporary npm environment for bundling (only used if module not in monorepo)
TEMP_NPM_DIR="${BUILD_DIR}/npm-env"

# Verdaccio configuration
VERDACCIO_URL="http://localhost:4873"

# Package name for Java/Kotlin (lowercase, no hyphens)
PACKAGE_NAME="com.yourorg.${MODULE_NAME_LOWER}"

########################################
# Helpers
########################################
log(){ echo -e "\n==> $*\n"; }
err(){ echo -e "\n‼️ ERROR: $*\n" >&2; }
warn(){ echo -e "\n⚠️  WARNING: $*\n"; }

########################################
# Validate environment
########################################
log "Validating environment..."

# Check Verdaccio is running
log "  Checking Verdaccio..."
if ! curl -s "$VERDACCIO_URL" > /dev/null; then
  err "Verdaccio is not running on $VERDACCIO_URL"
  echo "   Please start Verdaccio: npm run verdaccio:start"
  exit 1
fi
log "✅ Verdaccio is accessible"

# Check module exists in Verdaccio
log "  Checking module in Verdaccio..."
if ! npm view "$MODULE_PACKAGE" --registry "$VERDACCIO_URL" > /dev/null 2>&1; then
  err "Module $MODULE_PACKAGE not found in Verdaccio"
  echo "   Please publish the module: npm run verdaccio:publish-all"
  exit 1
fi
log "✅ Module $MODULE_PACKAGE found in Verdaccio"

# Check required tools
if ! command -v npx &> /dev/null; then
  err "npx not found. Please install Node.js."
  exit 1
fi

# Check for Android SDK (Gradle will check more thoroughly)
if [ -z "${ANDROID_HOME:-}" ] && [ -z "${ANDROID_SDK_ROOT:-}" ]; then
  warn "ANDROID_HOME or ANDROID_SDK_ROOT not set. Gradle may fail if Android SDK is not found."
  warn "   Set ANDROID_HOME to your Android SDK path, or ensure it's in your PATH."
fi

########################################
# Ensure directory structure
########################################
log "Setting up directory structure..."

# Ensure frameworks/android exists
FRAMEWORKS_DIR="${MONOREPO_ROOT}/frameworks"
FRAMEWORKS_ANDROID_DIR="${MONOREPO_ROOT}/frameworks/android"

if [ ! -d "$FRAMEWORKS_DIR" ]; then
  log "Creating frameworks directory..."
  mkdir -p "$FRAMEWORKS_DIR"
fi

if [ ! -d "$FRAMEWORKS_ANDROID_DIR" ]; then
  log "Creating frameworks/android directory..."
  mkdir -p "$FRAMEWORKS_ANDROID_DIR"
fi

# Create framework directory structure
mkdir -p "$FRAMEWORK_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$DIST_DIR"
mkdir -p "$ASSETS_DIR"
mkdir -p "$JAVA_DIR"

# Clean previous builds
rm -rf "$BUILD_DIR"/*
rm -rf "$DIST_DIR"/*

########################################
# Step 1: Fetch from Verdaccio and Bundle
########################################
log "Step 1: Fetching from Verdaccio and creating bundle..."

# Use monorepo's node_modules to avoid reinstalling everything
MONOREPO_NODE_MODULES="${MONOREPO_ROOT}/node_modules"
MODULE_APP_DIR="${MONOREPO_ROOT}/apps/module-${MODULE_NAME}"

# Check if module exists in monorepo (faster path)
if [ -d "$MODULE_APP_DIR" ] && [ -f "${MODULE_APP_DIR}/index.js" ]; then
  log "  Using module from monorepo (fast path - no npm install needed)..."
  MODULE_ENTRY="${MODULE_APP_DIR}/index.js"
  MODULE_DIR="$MODULE_APP_DIR"
  
  # Use monorepo's react-native directly
  if [ ! -d "$MONOREPO_NODE_MODULES/react-native" ]; then
    err "react-native not found in monorepo node_modules"
    err "Please run: npm install"
    exit 1
  fi
else
  # Fallback: Install from Verdaccio (slower)
  log "  Module not in monorepo, installing from Verdaccio..."
  rm -rf "$TEMP_NPM_DIR"
  mkdir -p "$TEMP_NPM_DIR"
  
  cat > "$TEMP_NPM_DIR/package.json" <<EOF
{
  "name": "framework-bundle-temp",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "$MODULE_PACKAGE": "*"
  }
}
EOF
  
  cat > "$TEMP_NPM_DIR/.npmrc" <<EOF
@app:registry=$VERDACCIO_URL
@pkg:registry=$VERDACCIO_URL
registry=$VERDACCIO_URL
EOF
  
  cd "$TEMP_NPM_DIR"
  npm install --legacy-peer-deps --no-save > /dev/null 2>&1
  
  if [ ! -d "node_modules/@app/module-${MODULE_NAME}" ]; then
    err "Failed to install $MODULE_PACKAGE from Verdaccio"
    exit 1
  fi
  
  MODULE_ENTRY="node_modules/@app/module-${MODULE_NAME}/index.js"
  MODULE_DIR="$TEMP_NPM_DIR/node_modules/@app/module-${MODULE_NAME}"
  
  if [ ! -f "$MODULE_ENTRY" ]; then
    err "Module entry point not found: $MODULE_ENTRY"
    exit 1
  fi
fi

# Ensure Assets directory exists
mkdir -p "$ASSETS_DIR"

# Bundle JavaScript
log "  Bundling JavaScript for Android..."
cd "$MONOREPO_ROOT"

# Find Metro config (use module's config if available)
METRO_CONFIG=""
if [ -f "${MODULE_DIR}/metro.config.js" ]; then
  METRO_CONFIG="--config ${MODULE_DIR}/metro.config.js"
elif [ -f "${MONOREPO_ROOT}/metro.config.js" ]; then
  METRO_CONFIG="--config ${MONOREPO_ROOT}/metro.config.js"
fi

# Use monorepo's react-native bundle command directly (faster than npx)
REACT_NATIVE_CLI="${MONOREPO_NODE_MODULES}/.bin/react-native"
if [ ! -f "$REACT_NATIVE_CLI" ]; then
  # Fallback to npx if not found
  REACT_NATIVE_CLI="npx --yes react-native"
fi

log "  Using entry point: $MODULE_ENTRY"

# Bundle with optimizations:
# - No --reset-cache: Uses Metro cache (much faster on subsequent runs)
# - Uses monorepo's node_modules for faster resolution
# - Reduced output for speed
log "  Bundling (this may take a minute, Metro cache will speed up subsequent runs)..."
$REACT_NATIVE_CLI bundle \
  --platform android \
  --entry-file "$MODULE_ENTRY" \
  --bundle-output "$BUNDLE_FILE" \
  --assets-dest "$ASSETS_DIR" \
  --dev false \
  --minify true \
  $METRO_CONFIG 2>&1 | grep -E "(error|Bundling|bundle)" || true

if [ ! -f "$BUNDLE_FILE" ]; then
  err "Bundle was not created: $BUNDLE_FILE"
  err "Check Metro bundler output above for errors"
  exit 1
fi

BUNDLE_SIZE=$(du -h "$BUNDLE_FILE" | cut -f1)
log "  ✅ Bundle created: $BUNDLE_FILE ($BUNDLE_SIZE)"

if [ ! -f "$BUNDLE_FILE" ]; then
  err "Bundle was not created: $BUNDLE_FILE"
  err "Check Metro bundler output above for errors"
  exit 1
fi

BUNDLE_SIZE=$(du -h "$BUNDLE_FILE" | cut -f1)
log "  ✅ Bundle created: $BUNDLE_FILE ($BUNDLE_SIZE)"

# Cleanup temp npm environment if used
if [ -d "$TEMP_NPM_DIR" ]; then
  rm -rf "$TEMP_NPM_DIR"
fi

########################################
# Step 2: Create Android Library Structure
########################################
log "Step 2: Creating Android Library structure..."

# Create AndroidManifest.xml
cat > "${SOURCES_DIR}/AndroidManifest.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="${PACKAGE_NAME}">
    
    <uses-sdk android:minSdkVersion="23" android:targetSdkVersion="34" />
    
    <!-- This is a library module, no application-level configuration needed -->
</manifest>
EOF

log "  ✅ Created AndroidManifest.xml"

# Create build.gradle
cat > "${FRAMEWORK_DIR}/build.gradle" <<EOF
plugins {
    id 'com.android.library'
    id 'org.jetbrains.kotlin.android'
}

android {
    namespace '${PACKAGE_NAME}'
    compileSdk 34

    defaultConfig {
        minSdk 23
        targetSdk 34
        
        consumerProguardFiles "consumer-rules.pro"
    }

    buildTypes {
        release {
            minifyEnabled false
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
        }
    }
    
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_1_8
        targetCompatibility JavaVersion.VERSION_1_8
    }
    
    kotlinOptions {
        jvmTarget = '1.8'
    }
}

dependencies {
    // React Native - consumers must add this dependency
    // Using provided scope so it's not bundled in the AAR
    compileOnly 'com.facebook.react:react-android:0.81.5'
    compileOnly 'com.facebook.react:react-native:0.81.5'
    
    // Kotlin standard library
    implementation 'org.jetbrains.kotlin:kotlin-stdlib:1.9.0'
}
EOF

log "  ✅ Created build.gradle"

# Create settings.gradle (if not exists at root)
if [ ! -f "${FRAMEWORKS_ANDROID_DIR}/settings.gradle" ]; then
  cat > "${FRAMEWORKS_ANDROID_DIR}/settings.gradle" <<EOF
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        maven { url 'https://www.jitpack.io' }
    }
}

rootProject.name = 'ModuleFrameworks'
EOF
  log "  ✅ Created settings.gradle"
fi

# Create gradle.properties (if not exists)
if [ ! -f "${FRAMEWORKS_ANDROID_DIR}/gradle.properties" ]; then
  cat > "${FRAMEWORKS_ANDROID_DIR}/gradle.properties" <<EOF
# Project-wide Gradle settings.
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
android.useAndroidX=true
android.enableJetifier=true
kotlin.code.style=official
EOF
  log "  ✅ Created gradle.properties"
fi

# Create proguard-rules.pro
cat > "${FRAMEWORK_DIR}/proguard-rules.pro" <<EOF
# Add project specific ProGuard rules here.
# You can control the set of applied configuration files using the
# proguardFiles setting in build.gradle.

# Keep React Native classes
-keep class com.facebook.react.** { *; }
-keep class com.facebook.hermes.** { *; }
-keep class com.facebook.jni.** { *; }

# Keep our framework classes
-keep class ${PACKAGE_NAME}.** { *; }
EOF

log "  ✅ Created proguard-rules.pro"

# Create consumer-rules.pro
cat > "${FRAMEWORK_DIR}/consumer-rules.pro" <<EOF
# ProGuard rules that will be applied to the consuming app
# This file is merged with the app's ProGuard rules

# Keep React Native classes
-keep class com.facebook.react.** { *; }
-keep class com.facebook.hermes.** { *; }
EOF

log "  ✅ Created consumer-rules.pro"

########################################
# Step 3: Create Kotlin Wrapper
########################################
log "Step 3: Creating Kotlin wrapper class..."

cat > "${JAVA_DIR}/${FRAMEWORK_NAME}.kt" <<EOF
package ${PACKAGE_NAME}

import android.content.Context
import android.util.Log
import com.facebook.react.ReactInstanceManager
import com.facebook.react.ReactRootView
import com.facebook.react.bridge.ReactApplicationContext
import java.io.File

/**
 * ${FRAMEWORK_NAME}
 * 
 * Android framework wrapper for ${MODULE_COMPONENT} React Native module.
 * 
 * This class provides a simple API to load and render the ${MODULE_COMPONENT} module
 * in any Android Activity or Fragment.
 * 
 * Usage:
 * ```kotlin
 * val framework = ${FRAMEWORK_NAME}.getInstance()
 * val bundlePath = framework.getBundlePath(context)
 * val moduleName = framework.getModuleName()
 * 
 * val rootView = ReactRootView(context)
 * rootView.startReactApplication(reactInstanceManager, moduleName, null)
 * ```
 */
class ${FRAMEWORK_NAME} private constructor() {
    
    companion object {
        private const val TAG = "${FRAMEWORK_NAME}"
        private const val BUNDLE_NAME = "module-${MODULE_NAME}.bundle"
        private const val MODULE_NAME = "${MODULE_COMPONENT}"
        
        @Volatile
        private var INSTANCE: ${FRAMEWORK_NAME}? = null
        
        /**
         * Get the singleton instance of ${FRAMEWORK_NAME}
         */
        fun getInstance(): ${FRAMEWORK_NAME} {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: ${FRAMEWORK_NAME}().also { INSTANCE = it }
            }
        }
    }
    
    /**
     * Gets the bundle file path for the ${MODULE_COMPONENT} module
     * 
     * @param context Android context
     * @return The absolute path to the module-${MODULE_NAME}.bundle file, or null if not found
     */
    fun getBundlePath(context: Context): String? {
        Log.d(TAG, "🔍 Looking for bundle: $BUNDLE_NAME")
        
        // Method 1: Try to find in assets directory (standard Android library location)
        try {
            val assets = context.assets
            assets.open(BUNDLE_NAME).use {
                // Bundle exists in assets
                val bundlePath = "file:///android_asset/$BUNDLE_NAME"
                Log.d(TAG, "✅ Found bundle in assets: $bundlePath")
                return bundlePath
            }
        } catch (e: Exception) {
            Log.d(TAG, "   Bundle not found in assets, trying other methods...")
        }
        
        // Method 2: Try to find in application's assets
        try {
            val appContext = context.applicationContext
            val assets = appContext.assets
            assets.open(BUNDLE_NAME).use {
                val bundlePath = "file:///android_asset/$BUNDLE_NAME"
                Log.d(TAG, "✅ Found bundle in application assets: $bundlePath")
                return bundlePath
            }
        } catch (e: Exception) {
            Log.d(TAG, "   Bundle not found in application assets")
        }
        
        // Method 3: Try to find in files directory (if copied there)
        val filesDir = context.filesDir
        val bundleFile = File(filesDir, BUNDLE_NAME)
        if (bundleFile.exists()) {
            val bundlePath = bundleFile.absolutePath
            Log.d(TAG, "✅ Found bundle in files directory: $bundlePath")
            return bundlePath
        }
        
        // Method 4: Try to find in external files directory
        val externalFilesDir = context.getExternalFilesDir(null)
        if (externalFilesDir != null) {
            val bundleFile = File(externalFilesDir, BUNDLE_NAME)
            if (bundleFile.exists()) {
                val bundlePath = bundleFile.absolutePath
                Log.d(TAG, "✅ Found bundle in external files directory: $bundlePath")
                return bundlePath
            }
        }
        
        Log.e(TAG, "❌ Bundle not found in any location")
        Log.e(TAG, "   Searched:")
        Log.e(TAG, "     - Assets: $BUNDLE_NAME")
        Log.e(TAG, "     - Files dir: ${filesDir.absolutePath}")
        if (externalFilesDir != null) {
            Log.e(TAG, "     - External files dir: ${externalFilesDir.absolutePath}")
        }
        
        return null
    }
    
    /**
     * Gets the module name for the ${MODULE_COMPONENT} module
     * 
     * @return The registered module name ("${MODULE_COMPONENT}")
     */
    fun getModuleName(): String {
        return MODULE_NAME
    }
    
    /**
     * Creates a React Native root view for the module
     * 
     * @param context Android context
     * @param reactInstanceManager The ReactInstanceManager from the consuming app
     * @param initialProperties Optional initial properties to pass to the module
     * @return A configured ReactRootView ready to be added to a view hierarchy, or null if bundle not found
     */
    fun createView(
        context: Context,
        reactInstanceManager: ReactInstanceManager,
        initialProperties: android.os.Bundle? = null
    ): ReactRootView? {
        val bundlePath = getBundlePath(context)
        if (bundlePath == null) {
            Log.e(TAG, "❌ Cannot create view: Bundle not found")
            return null
        }
        
        Log.d(TAG, "📦 Creating ReactRootView")
        Log.d(TAG, "   Bundle path: $bundlePath")
        Log.d(TAG, "   Module name: $MODULE_NAME")
        
        val rootView = ReactRootView(context)
        rootView.startReactApplication(reactInstanceManager, MODULE_NAME, initialProperties)
        
        return rootView
    }
}
EOF

log "  ✅ Created Kotlin wrapper: ${FRAMEWORK_NAME}.kt"

########################################
# Step 4: Build AAR
########################################
log "Step 4: Building AAR file..."

# Check if Gradle wrapper exists, if not create it
GRADLE_WRAPPER_DIR="${FRAMEWORKS_ANDROID_DIR}/gradle/wrapper"
if [ ! -f "${FRAMEWORKS_ANDROID_DIR}/gradlew" ]; then
  log "  Creating Gradle wrapper..."
  mkdir -p "$GRADLE_WRAPPER_DIR"
  
  # Create gradle-wrapper.properties
  cat > "${GRADLE_WRAPPER_DIR}/gradle-wrapper.properties" <<EOF
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-8.0-bin.zip
networkTimeout=10000
validateDistributionUrl=true
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
EOF
  
  # Note: gradlew script would need to be created, but for now we'll use system gradle
  log "  ⚠️  Gradle wrapper not created (requires gradle binary). Using system gradle if available."
fi

# Build AAR using Gradle
cd "$FRAMEWORK_DIR"

if command -v gradle &> /dev/null; then
  log "  Building with system Gradle..."
  gradle clean assembleRelease 2>&1 | grep -E "(BUILD|error|warning|AAR)" || true
elif [ -f "${FRAMEWORKS_ANDROID_DIR}/gradlew" ]; then
  log "  Building with Gradle wrapper..."
  "${FRAMEWORKS_ANDROID_DIR}/gradlew" -p "$FRAMEWORK_DIR" clean assembleRelease 2>&1 | grep -E "(BUILD|error|warning|AAR)" || true
else
  warn "Gradle not found. AAR will not be built automatically."
  warn "   To build the AAR:"
  warn "     1. Install Android Studio and Gradle"
  warn "     2. cd $FRAMEWORK_DIR"
  warn "     3. gradle clean assembleRelease"
  warn "   Or open the project in Android Studio and build from there."
fi

# Check if AAR was created
AAR_FILE="${FRAMEWORK_DIR}/build/outputs/aar/${FRAMEWORK_NAME}-release.aar"
if [ -f "$AAR_FILE" ]; then
  AAR_SIZE=$(du -h "$AAR_FILE" | cut -f1)
  log "  ✅ AAR created: $AAR_FILE ($AAR_SIZE)"
  
  # Copy to dist directory
  mkdir -p "$DIST_DIR"
  cp "$AAR_FILE" "$DIST_DIR/"
  log "  ✅ AAR copied to: $DIST_DIR"
else
  warn "AAR file not found. Build may have failed or Gradle is not available."
  warn "   AAR location expected: $AAR_FILE"
fi

########################################
# Step 5: Create README
########################################
log "Step 5: Creating README.md..."

cat > "${FRAMEWORK_DIR}/README.md" <<EOF
# ${FRAMEWORK_NAME}

Android AAR framework for ${MODULE_COMPONENT} React Native module.

## Overview

This framework contains:
- Pre-bundled JavaScript code (module-${MODULE_NAME}.bundle)
- Kotlin wrapper API for easy integration
- No Verdaccio or npm required at runtime

## Prerequisites

- React Native 0.81.5+ must be added to the consuming app
- Android minSdkVersion: 23
- Android targetSdkVersion: 34
- Kotlin support

## Usage

### 1. Add React Native Dependencies (Required)

In your app's \`build.gradle\`:

\`\`\`gradle
dependencies {
    implementation 'com.facebook.react:react-android:0.81.5'
    implementation 'com.facebook.react:react-native:0.81.5'
    // Add other React Native dependencies as needed
}
\`\`\`

### 2. Add This AAR

**Option A: Local AAR file**

\`\`\`gradle
dependencies {
    implementation files('libs/${FRAMEWORK_NAME}-release.aar')
}
\`\`\`

**Option B: Maven Local (if published)**

\`\`\`gradle
repositories {
    mavenLocal()
}

dependencies {
    implementation '${PACKAGE_NAME}:${FRAMEWORK_NAME}:1.0.0'
}
\`\`\`

### 3. Use in Code

\`\`\`kotlin
import ${PACKAGE_NAME}.${FRAMEWORK_NAME}

class ProductsActivity : AppCompatActivity() {
    private lateinit var reactRootView: ReactRootView
    private val reactInstanceManager get() =
        (application as ReactApplication).reactNativeHost.reactInstanceManager
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        val framework = ${FRAMEWORK_NAME}.getInstance()
        val bundlePath = framework.getBundlePath(this)
        val moduleName = framework.getModuleName()
        
        if (bundlePath != null) {
            reactRootView = ReactRootView(this)
            reactRootView.startReactApplication(reactInstanceManager, moduleName, null)
            setContentView(reactRootView)
        } else {
            // Handle error: bundle not found
            Log.e("ProductsActivity", "Bundle not found")
        }
    }
}
\`\`\`

**Or use the convenience method:**

\`\`\`kotlin
val framework = ${FRAMEWORK_NAME}.getInstance()
val rootView = framework.createView(
    context = this,
    reactInstanceManager = reactInstanceManager,
    initialProperties = null
)

if (rootView != null) {
    setContentView(rootView)
}
\`\`\`

## API

- \`getInstance(): ${FRAMEWORK_NAME}\` - Get singleton instance
- \`getBundlePath(context: Context): String?\` - Returns bundle file path
- \`getModuleName(): String\` - Returns registered module name
- \`createView(context: Context, reactInstanceManager: ReactInstanceManager, initialProperties: Bundle?): ReactRootView?\` - Creates React Native view

## Bundle

The JavaScript bundle is embedded in:
\`src/main/assets/module-${MODULE_NAME}.bundle\`

This bundle was created from the latest version published to Verdaccio.

## Version

Generated from: ${MODULE_PACKAGE}
Source: Verdaccio registry
EOF

########################################
# Summary
########################################
log "🎉 SUCCESS! ${FRAMEWORK_NAME} AAR framework generated"
echo ""
echo "📍 Location: $FRAMEWORK_DIR"
echo ""
echo "📦 Contents:"
echo "   • build.gradle"
echo "   • src/main/java/${PACKAGE_NAME//./\/}/${FRAMEWORK_NAME}.kt"
echo "   • src/main/assets/module-${MODULE_NAME}.bundle ($BUNDLE_SIZE)"
echo "   • README.md"
if [ -f "$AAR_FILE" ]; then
  echo "   • build/outputs/aar/${FRAMEWORK_NAME}-release.aar"
fi
echo ""
echo "📝 Next steps:"
echo "   1. Ensure React Native 0.81.5+ is added to your Android app"
echo "   2. Add this AAR to your app's dependencies:"
if [ -f "$AAR_FILE" ]; then
  echo "      implementation files('$AAR_FILE')"
else
  echo "      (Build the AAR first: cd $FRAMEWORK_DIR && gradle assembleRelease)"
fi
echo "   3. Use in code: import ${PACKAGE_NAME}.${FRAMEWORK_NAME}"
echo ""
echo "✅ Framework ready for distribution!"
echo "   • React Native types automatically available via dependency"
echo "   • No manual bundle copying needed"
echo ""

