# Android Integration Guide

This guide explains how to integrate React Native modules from this monorepo into existing Android applications using the **Verdaccio npm registry approach**.

> **Note:** This guide provides a high-level overview. For detailed step-by-step instructions, see [NATIVE_APP_CONSUMPTION.md](./NATIVE_APP_CONSUMPTION.md).

## Prerequisites

- Existing Android app with React Native installed
- React Native version >= 0.81.5
- Android Studio installed
- Node.js >= 20
- Verdaccio running locally (see [LOCAL_REGISTRY.md](./LOCAL_REGISTRY.md))

## ⚠️ Important: First-Time Build (30+ Minutes)

**Before integrating modules, you must build React Native from source.** This is a **one-time setup** that takes 20-30+ minutes on first run.

### Why Build from Source?

React Native 0.81.5 pre-built AARs don't include `libhermes_executor.so`, which is required for Hermes to work. Building from source ensures:

- ✅ Hermes executor library is included
- ✅ Full control over React Native build
- ✅ Better long-term maintainability

### What Gets Built?

The source build compiles:

1. **Hermes Engine** - The JavaScript engine (C++/native code)
2. **React Native Native Libraries** - Android native code
3. **Hermes Executor Library** - `libhermes_executor.so` (missing from pre-built AARs)

### When to Run

- **First time setup** - Required before integrating any modules
- **After React Native version updates** - If you upgrade React Native
- **After cleaning build artifacts** - If you run `./gradlew clean`

### How to Run

```bash
cd native-android  # or your Android project root
./scripts/build-react-native.sh
```

**Note:** This is a **one-time infrastructure setup**, not needed for each module. Once complete, module integration (Products, Cart, PDP) only requires fast JavaScript bundling (seconds), not native compilation.

### Module Integration vs Source Build

- **30-minute build**: One-time React Native source build (native C++/Java compilation)
- **Module builds**: Fast JavaScript bundling (seconds) - Products, Cart, PDP are just JS bundles
- **Why modules don't need it**: They're JavaScript that runs in the same React Native instance

> **For detailed build documentation**, see the native Android project's `docs/BUILD_FROM_SOURCE.md` file (if available) or refer to the React Native source build process in your Android project.

## Overview

The recommended approach is to:

1. Install modules as npm packages from Verdaccio
2. Bundle modules using Metro inside your native project
3. Load bundles via React Native bridge

This is more maintainable than manually copying bundle files.

## Quick Start

1. **Configure npm to use Verdaccio**

   Create `.npmrc` in your native project:

   ```ini
   @pkg:registry=http://localhost:4873
   @app:registry=http://localhost:4873
   ```

2. **Install modules**

   ```bash
   cd js  # or wherever you keep your JS workspace
   npm install @app/module-products
   ```

3. **Create entry point**

   `js/index.js`:

   ```javascript
   import { AppRegistry } from "react-native";
   import "@app/module-products"; // Registers "ModuleProducts"
   ```

4. **Bundle for Android**

   ```bash
   npm run bundle:products
   ```

5. **Load in Android Activity**

   See [NATIVE_APP_CONSUMPTION.md](./NATIVE_APP_CONSUMPTION.md) for complete Activity implementation.

## Detailed Integration

For complete integration instructions including:

- Directory structure
- Gradle configuration
- Activity implementation
- Bundle loading
- Native module bridges

See **[NATIVE_APP_CONSUMPTION.md](./NATIVE_APP_CONSUMPTION.md)** - Section 2: Android Project Template.

## Alternative: Manual Bundle Approach

If you prefer to manually copy bundles (not recommended for development):

1. Build bundle from this monorepo
2. Copy `index.android.bundle` to `android/app/src/main/assets/`
3. Copy assets to `android/app/src/main/res/`
4. Load bundle in your Activity

This approach is less flexible and harder to maintain. Use Verdaccio for better workflow.

## React Native Activity Example

Basic Activity to host a module:

```kotlin
class ProductsActivity : AppCompatActivity(), DefaultHardwareBackBtnHandler {
    private var reactRootView: ReactRootView? = null
    private val reactInstanceManager get() =
        (application as ReactApplication).reactNativeHost.reactInstanceManager

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        reactRootView = ReactRootView(this).also {
            it.startReactApplication(reactInstanceManager, "ModuleProducts", null)
            setContentView(it)
        }
    }

    override fun onResume() {
        super.onResume()
        reactInstanceManager.onHostResume(this, this)
    }

    override fun onPause() {
        reactInstanceManager.onHostPause(this)
        super.onPause()
    }

    override fun onDestroy() {
        reactRootView?.unmountReactApplication()
        reactRootView = null
        super.onDestroy()
    }

    override fun onBackPressed() {
        reactInstanceManager.onBackPressed()
    }

    override fun invokeDefaultOnBackPressed() {
        super.onBackPressed()
    }
}
```

## Native Module Bridge (Optional)

If you need to communicate between React Native and native Android:

See [NATIVE_APP_CONSUMPTION.md](./NATIVE_APP_CONSUMPTION.md) for bridge implementation examples.

## Dependencies

Your `app/build.gradle` should include:

```gradle
dependencies {
    implementation("com.facebook.react:react-android:0.81.5")
    // Add other React Native dependencies as needed
}
```

## Troubleshooting

### Bundle Not Found

- Verify bundle was generated: `ls android/app/src/main/assets/index.android.bundle`
- Check bundle script output for errors
- Ensure Metro can resolve `@app/*` packages (check `.npmrc`)

### Module Not Registered

- Verify module is imported in `js/index.js`
- Check module name matches: `"ModuleProducts"` (case-sensitive)
- Ensure `AppRegistry.registerComponent` is called in the module

### Package Resolution Errors

- Verify Verdaccio is running: `curl http://localhost:4873`
- Check `.npmrc` configuration
- Run `npm install` again in the JS workspace

### Hermes Issues

- See [NATIVE_APP_CONSUMPTION.md](./NATIVE_APP_CONSUMPTION.md) for Hermes configuration
- Consider using JSC if Hermes causes issues

## Related Documentation

- **[NATIVE_APP_CONSUMPTION.md](./NATIVE_APP_CONSUMPTION.md)** - Complete Android/iOS integration guide
- **[LOCAL_REGISTRY.md](./LOCAL_REGISTRY.md)** - Setting up and using Verdaccio
- **[MODULE_DISTRIBUTION.md](./MODULE_DISTRIBUTION.md)** - How modules are published
- **[PACKAGES.md](./PACKAGES.md)** - Package API documentation
