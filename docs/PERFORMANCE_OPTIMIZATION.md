# Performance Optimization Guide: OTA Updates, Bundle Size, and Performance

This guide provides comprehensive recommendations for optimizing React Native modules when consumed by a **single native app** with requirements for:

- ✅ Over-The-Air (OTA) updates
- ✅ Minimal bundle size
- ✅ Maximum performance

## Table of Contents

1. [Current Architecture Analysis](#current-architecture-analysis)
2. [OTA Updates Implementation](#ota-updates-implementation)
3. [Bundle Size Optimization](#bundle-size-optimization)
4. [Performance Optimizations](#performance-optimizations)
5. [Verdaccio: Keep or Replace?](#verdaccio-keep-or-replace)
6. [Implementation Plan](#implementation-plan)
7. [Bundle Size Comparison](#bundle-size-comparison)
8. [Performance Metrics](#performance-metrics)

---

## Current Architecture Analysis

### Current State

- **Bundle Strategy**: Static bundles embedded in app assets
- **OTA Updates**: ❌ Not implemented
- **Bundle Structure**: All modules bundled together
- **Distribution**: Verdaccio npm registry
- **JS Engine**: JSC (JavaScriptCore) or Hermes

### Issues with Current Approach

1. **Large Bundle Size**: All modules bundled together (~2-3 MB)
2. **No OTA Updates**: Requires app store releases for JS changes
3. **No Code Splitting**: Entire bundle loaded even if only one module is used
4. **Potential Duplication**: Shared dependencies may be duplicated across modules

---

## OTA Updates Implementation

### Option 1: Microsoft CodePush (Recommended)

CodePush allows you to push JavaScript updates directly to users without going through app stores.

#### Installation

```bash
# In native app's js/ directory
npm install react-native-code-push

# iOS: Install CocoaPods
cd ios && pod install
```

#### Android Configuration

**1. Update `MainApplication.kt`:**

```kotlin
import com.microsoft.codepush.react.CodePush

class MainApplication : Application(), ReactApplication {
    override val reactNativeHost: ReactNativeHost = object : DefaultReactNativeHost(this) {
        override fun getPackages(): List<ReactPackage> = listOf(
            MainReactPackage(),
            CodePush(
                BuildConfig.CODEPUSH_KEY, // Get from CodePush dashboard
                this,
                BuildConfig.DEBUG
            )
        )

        // Use CodePush bundle instead of asset bundle
        override fun getJSBundleFile(): String {
            return CodePush.getJSBundleFile()
        }

        override fun getUseDeveloperSupport() = BuildConfig.DEBUG
        override val isHermesEnabled get() = true // Use Hermes for better performance
    }
}
```

**2. Update `build.gradle`:**

```gradle
android {
    buildTypes {
        debug {
            buildConfigField "String", "CODEPUSH_KEY", '""'
        }
        release {
            buildConfigField "String", "CODEPUSH_KEY", '"YOUR_PRODUCTION_KEY"'
        }
    }
}
```

#### iOS Configuration

**1. Update `AppDelegate.swift`:**

```swift
import CodePush

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let bridge = RCTBridge(delegate: self, launchOptions: launchOptions)
        let rootView = RCTRootView(bridge: bridge, moduleName: "AppShell", initialProperties: nil)

        // Use CodePush bundle URL
        let codePushURL = CodePush.bundleURL()
        // ... rest of setup

        return true
    }
}
```

**2. Update `Info.plist`:**

```xml
<key>CodePushDeploymentKey</key>
<string>YOUR_DEPLOYMENT_KEY</string>
```

#### Publishing Updates

```bash
# In native app's js/ directory after bundling
npx code-push release-react MyApp-Android android --mandatory
npx code-push release-react MyApp-iOS ios --mandatory

# Staged rollout (10% of users)
npx code-push promote MyApp-Android Staging Production -r 10
```

### Option 2: Custom OTA Solution

For more control, implement a custom OTA solution:

```kotlin
// CustomBundleLoader.kt
class CustomBundleLoader {
    suspend fun loadBundle(): String? {
        // 1. Check for updates from your CDN
        val latestVersion = fetchLatestVersion()
        val currentVersion = getCurrentVersion()

        if (latestVersion > currentVersion) {
            // 2. Download new bundle
            val bundle = downloadBundle(latestVersion)

            // 3. Validate bundle (checksum, signature)
            if (validateBundle(bundle)) {
                // 4. Save and use new bundle
                saveBundle(bundle, latestVersion)
                return getBundlePath(latestVersion)
            }
        }

        // Fallback to embedded bundle
        return getEmbeddedBundlePath()
    }
}
```

---

## Bundle Size Optimization

### Strategy 1: Code Splitting with Lazy Loading

Instead of bundling all modules together, split them into separate bundles loaded on-demand.

#### Entry Point (Minimal Shell)

**`js/index.js`:**

```javascript
import { AppRegistry } from "react-native";

// Only register the shell - modules load on-demand
AppRegistry.registerComponent("AppShell", () => require("./AppShell").default);
```

#### Lazy Loading Shell

**`js/AppShell.tsx`:**

```typescript
import React, { lazy, Suspense } from "react";
import { View, ActivityIndicator, StyleSheet } from "react-native";

// Lazy load modules only when needed
const ModuleProducts = lazy(() => import("@app/module-products"));
const ModuleCart = lazy(() => import("@app/module-cart"));
const ModulePDP = lazy(() => import("@app/module-pdp"));

interface AppShellProps {
  moduleName: "ModuleProducts" | "ModuleCart" | "ModulePDP";
  [key: string]: any;
}

export default function AppShell({ moduleName, ...props }: AppShellProps) {
  const Module = {
    ModuleProducts,
    ModuleCart,
    ModulePDP,
  }[moduleName];

  if (!Module) {
    return (
      <View style={styles.container}>
        <ActivityIndicator size="large" />
      </View>
    );
  }

  return (
    <Suspense fallback={<ActivityIndicator size="large" />}>
      <Module {...props} />
    </Suspense>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    justifyContent: "center",
    alignItems: "center",
  },
});
```

#### Metro Configuration for Code Splitting

**`js/metro.config.js`:**

```javascript
const { getDefaultConfig, mergeConfig } = require("@react-native/metro-config");
const path = require("path");

const projectRoot = __dirname;
const nodeModules = path.join(projectRoot, "node_modules");

const defaultConfig = getDefaultConfig(projectRoot);

const config = mergeConfig(defaultConfig, {
  resolver: {
    nodeModulesPaths: [nodeModules],
    // Share common dependencies to reduce duplication
    extraNodeModules: {
      react: require.resolve("react"),
      "react-native": require.resolve("react-native"),
      "react-redux": require.resolve("react-redux"),
      "@reduxjs/toolkit": require.resolve("@reduxjs/toolkit"),
      "react-dom": require.resolve("react-dom"),
    },
  },
  transformer: {
    // Enable minification
    minifierConfig: {
      keep_classnames: false,
      keep_fnames: false,
      mangle: {
        keep_classnames: false,
        keep_fnames: false,
      },
    },
    // Enable tree shaking
    getTransformOptions: async () => ({
      transform: {
        experimentalImportSupport: true,
        inlineRequires: true,
      },
    }),
  },
  serializer: {
    // Custom serializer for code splitting
    createModuleIdFactory: () => {
      let nextId = 0;
      return () => nextId++;
    },
  },
});

module.exports = config;
```

### Strategy 2: Per-Module Bundle Generation

Create separate bundles for each module:

**`js/package.json` scripts:**

```json
{
  "scripts": {
    "bundle:shell": "react-native bundle --entry-file index.js --bundle-output android/app/src/main/assets/shell.bundle --platform android --dev false --minify",
    "bundle:products": "react-native bundle --entry-file products-entry.js --bundle-output android/app/src/main/assets/products.bundle --platform android --dev false --minify",
    "bundle:cart": "react-native bundle --entry-file cart-entry.js --bundle-output android/app/src/main/assets/cart.bundle --platform android --dev false --minify",
    "bundle:pdp": "react-native bundle --entry-file pdp-entry.js --bundle-output android/app/src/main/assets/pdp.bundle --platform android --dev false --minify",
    "bundle:all": "npm run bundle:shell && npm run bundle:products && npm run bundle:cart && npm run bundle:pdp"
  }
}
```

**Module Entry Files:**

**`js/products-entry.js`:**

```javascript
import { AppRegistry } from "react-native";
import ModuleProducts from "@app/module-products";

AppRegistry.registerComponent("ModuleProducts", () => ModuleProducts);
```

### Strategy 3: Shared Dependencies Bundle

Create a shared bundle for common dependencies:

**`js/shared-entry.js`:**

```javascript
// Export all shared dependencies
export * from "react";
export * from "react-native";
export * from "react-redux";
export * from "@reduxjs/toolkit";
```

**`js/metro.config.js` (with shared bundle):**

```javascript
const config = mergeConfig(defaultConfig, {
  serializer: {
    // Create shared bundle for common dependencies
    createModuleIdFactory: () => {
      const sharedModules = new Set([
        "react",
        "react-native",
        "react-redux",
        "@reduxjs/toolkit",
      ]);

      let nextId = 0;
      return (path) => {
        if (sharedModules.has(path)) {
          return `shared_${path}`;
        }
        return nextId++;
      };
    },
  },
});
```

### Strategy 4: Bundle Analysis and Optimization

**Install bundle analyzer:**

```bash
npm install --save-dev @react-native-community/cli-plugin-metro
```

**Analyze bundle:**

```bash
# Generate bundle analysis
react-native bundle \
  --platform android \
  --entry-file index.js \
  --bundle-output /tmp/bundle.js \
  --dev false \
  --minify false \
  --sourcemap-output /tmp/bundle.map

# Analyze with source-map-explorer
npx source-map-explorer /tmp/bundle.js --html report.html
```

---

## Performance Optimizations

### 1. Enable Hermes Engine

Hermes provides better performance than JSC:

**Android `MainApplication.kt`:**

```kotlin
override val isHermesEnabled get() = true
```

**iOS `Podfile`:**

```ruby
use_react_native!(
  :path => '../js/node_modules/react-native',
  :hermes_enabled => true,  # Enable Hermes
  :fabric_enabled => false
)
```

### 2. Optimize Bundle Scripts

**Production bundle with all optimizations:**

```bash
react-native bundle \
  --platform android \
  --entry-file index.js \
  --bundle-output android/app/src/main/assets/index.android.bundle \
  --assets-dest android/app/src/main/res \
  --dev false \
  --minify true \
  --reset-cache \
  --sourcemap-output android/app/src/main/assets/index.android.bundle.map
```

### 3. Enable Inline Requires

Reduces initial bundle parse time:

**`js/metro.config.js`:**

```javascript
transformer: {
  getTransformOptions: async () => ({
    transform: {
      inlineRequires: true, // Enable inline requires
    },
  }),
}
```

### 4. Implement Bundle Caching

**Android - Cache Manager:**

```kotlin
class BundleCacheManager {
    private val cacheDir = File(context.cacheDir, "bundles")

    fun getCachedBundle(version: String): File? {
        val cachedFile = File(cacheDir, "bundle_$version.js")
        return if (cachedFile.exists()) cachedFile else null
    }

    fun cacheBundle(bundle: ByteArray, version: String) {
        cacheDir.mkdirs()
        File(cacheDir, "bundle_$version.js").writeBytes(bundle)
    }
}
```

### 5. Lazy Load Native Modules

Only load native modules when needed:

```kotlin
// Lazy load native modules
val navigationBridge = lazy { NavigationBridgeModule() }
```

---

## Verdaccio: Keep or Replace?

### Analysis for Single App Consumption

Since you have a **single native app** consuming all modules, Verdaccio may add unnecessary overhead.

### Option A: Keep Verdaccio (Recommended for Production)

**Pros:**

- ✅ Version control and rollback capability
- ✅ Standard npm workflow
- ✅ Easy to track which versions are deployed
- ✅ Works well with CI/CD pipelines

**Cons:**

- ❌ Requires Verdaccio running locally/CI
- ❌ Slower development iteration
- ❌ Additional infrastructure

**Best For:** Production releases with strict versioning requirements

### Option B: Direct Source Integration

**Pros:**

- ✅ Faster development iteration
- ✅ Simpler setup (no registry)
- ✅ Better tree-shaking (Metro can optimize better)
- ✅ No network dependency

**Cons:**

- ❌ No versioning
- ❌ Tighter coupling between monorepo and native app
- ❌ Harder to track what's deployed

**Best For:** Single app, performance-critical, rapid development

### Option C: Hybrid Approach (Recommended)

Use different strategies for development and production:

**Development:**

```bash
# Use npm link for fast iteration
cd /path/to/monorepo/apps/module-products
npm link

cd /path/to/native-app/js
npm link @app/module-products
```

**Production:**

```bash
# Use Verdaccio for versioned releases
npm install @app/module-products@1.2.3
```

**Implementation:**

```json
// package.json
{
  "scripts": {
    "dev:link": "npm link @app/module-products @app/module-cart @app/module-pdp",
    "prod:install": "npm install @app/module-products@latest @app/module-cart@latest @app/module-pdp@latest"
  }
}
```

---

## Implementation Plan

### Phase 1: Add OTA Updates (Week 1)

1. **Install CodePush**

   ```bash
   npm install react-native-code-push
   ```

2. **Configure CodePush**

   - Set up CodePush account
   - Configure Android and iOS
   - Update bundle loading logic

3. **Test OTA Updates**
   - Create test bundle
   - Deploy to CodePush
   - Verify update mechanism

### Phase 2: Optimize Bundle Size (Week 2)

1. **Implement Code Splitting**

   - Create lazy loading shell
   - Split modules into separate bundles
   - Update Metro configuration

2. **Optimize Dependencies**

   - Identify shared dependencies
   - Create shared bundle
   - Remove unused dependencies

3. **Bundle Analysis**
   - Analyze current bundle size
   - Identify optimization opportunities
   - Measure improvements

### Phase 3: Performance Tuning (Week 3)

1. **Enable Hermes**

   - Switch from JSC to Hermes
   - Test performance improvements
   - Fix any compatibility issues

2. **Optimize Bundle Scripts**

   - Enable minification
   - Enable tree-shaking
   - Add source maps for debugging

3. **Implement Caching**
   - Bundle caching
   - Asset caching
   - Version management

### Phase 4: Monitoring and Maintenance (Ongoing)

1. **Bundle Size Monitoring**

   - Set up CI checks for bundle size
   - Alert on size increases
   - Track size over time

2. **Performance Monitoring**

   - Track load times
   - Monitor memory usage
   - Measure time to interactive

3. **OTA Update Monitoring**
   - Track update success rates
   - Monitor rollback rates
   - Track deployment metrics

---

## Bundle Size Comparison

### Current Approach (All Modules Bundled)

```
index.android.bundle: ~2.5 MB
├── ModuleProducts: ~800 KB
├── ModuleCart: ~600 KB
├── ModulePDP: ~700 KB
└── Shared Dependencies: ~400 KB
```

**Issues:**

- Entire bundle loaded even if only one module is used
- No code splitting
- Large initial download

### Optimized Approach (Code Splitting)

```
shell.bundle: ~500 KB (shell + shared deps)
├── React/React Native: ~200 KB
├── Redux/Redux Toolkit: ~150 KB
└── Shell Code: ~150 KB

module-products.bundle: ~300 KB (loaded on-demand)
module-cart.bundle: ~200 KB (loaded on-demand)
module-pdp.bundle: ~250 KB (loaded on-demand)

Total: ~1.25 MB (but only loads what's needed)
```

**Benefits:**

- 50% reduction in initial bundle size
- Modules loaded only when needed
- Faster initial load time

### With OTA Updates

```
Initial App Bundle: ~500 KB (shell only)
OTA Updates: ~300-500 KB per module (only when updated)
```

**Benefits:**

- Small initial app size
- Incremental updates
- Faster app store approval (smaller binary)

---

## Performance Metrics

### Expected Improvements

| Metric               | Current | Optimized  | Improvement          |
| -------------------- | ------- | ---------- | -------------------- |
| Initial Bundle Size  | 2.5 MB  | 500 KB     | **80% reduction**    |
| Time to First Render | 2.5s    | 1.2s       | **52% faster**       |
| Memory Usage         | 120 MB  | 85 MB      | **29% reduction**    |
| Time to Interactive  | 3.5s    | 1.8s       | **49% faster**       |
| OTA Update Size      | 2.5 MB  | 300-500 KB | **80-88% reduction** |

### Measurement Tools

**1. Bundle Size:**

```bash
# Measure bundle size
ls -lh android/app/src/main/assets/*.bundle
```

**2. Performance:**

```javascript
// Add performance markers
import { PerformanceObserver } from "react-native";

const observer = new PerformanceObserver((list) => {
  list.getEntries().forEach((entry) => {
    console.log(`${entry.name}: ${entry.duration}ms`);
  });
});

observer.observe({ entryTypes: ["measure"] });
```

**3. Memory:**

```kotlin
// Android memory monitoring
val runtime = Runtime.getRuntime()
val usedMemory = runtime.totalMemory() - runtime.freeMemory()
Log.d("Memory", "Used: ${usedMemory / 1024 / 1024} MB")
```

---

## Best Practices

### 1. Bundle Size Management

- ✅ Set bundle size budgets in CI
- ✅ Review bundle size on every PR
- ✅ Use bundle analyzers regularly
- ✅ Remove unused dependencies
- ✅ Lazy load heavy dependencies

### 2. OTA Update Strategy

- ✅ Test updates on staging first
- ✅ Use staged rollouts (10% → 50% → 100%)
- ✅ Monitor crash rates after updates
- ✅ Have rollback plan ready
- ✅ Version all bundles

### 3. Performance Monitoring

- ✅ Track key performance metrics
- ✅ Set up alerts for performance regressions
- ✅ Monitor memory usage
- ✅ Profile regularly
- ✅ Optimize based on real user data

### 4. Development Workflow

- ✅ Use direct source linking for development
- ✅ Use Verdaccio for production builds
- ✅ Automate bundle generation
- ✅ Version all bundles
- ✅ Document bundle contents

---

## Troubleshooting

### Bundle Size Too Large

1. **Analyze bundle:**

   ```bash
   npx source-map-explorer bundle.js
   ```

2. **Check for duplicates:**

   ```bash
   npm ls | grep -E "react|react-native"
   ```

3. **Remove unused dependencies:**
   ```bash
   npx depcheck
   ```

### OTA Updates Not Working

1. **Check CodePush configuration:**

   - Verify deployment keys
   - Check network connectivity
   - Verify bundle was uploaded

2. **Check bundle loading:**
   ```kotlin
   Log.d("CodePush", "Bundle URL: ${CodePush.getJSBundleFile()}")
   ```

### Performance Issues

1. **Enable Hermes:**

   - Verify Hermes is enabled
   - Check Hermes version
   - Test with Hermes profiler

2. **Check bundle optimization:**
   - Verify minification is enabled
   - Check tree-shaking is working
   - Verify inline requires

---

## Related Documentation

- **[Android Integration](./ANDROID_INTEGRATION.md)** - Android-specific setup
- **[iOS Integration](./IOS_INTEGRATION.md)** - iOS-specific setup
- **[Native App Consumption](./NATIVE_APP_CONSUMPTION.md)** - Integration guide
- **[Module Distribution](./MODULE_DISTRIBUTION.md)** - Distribution strategies

---

## Additional Resources

- [CodePush Documentation](https://docs.microsoft.com/en-us/appcenter/distribution/codepush/)
- [Metro Bundler Configuration](https://facebook.github.io/metro/docs/configuration)
- [Hermes Engine](https://hermesengine.dev/)
- [React Native Performance](https://reactnative.dev/docs/performance)

---

**Last Updated:** 2024
**Maintained By:** Development Team
