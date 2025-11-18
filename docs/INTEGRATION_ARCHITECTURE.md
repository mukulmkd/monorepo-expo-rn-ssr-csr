# Native App Integration with React Native Modules

## Architecture Overview

This document explains how native Android and iOS apps integrate with React Native modules published from the monorepo. The integration uses a **hybrid architecture** where native apps host React Native modules as embedded components.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         MONOREPO                                │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Module Source Code                                       │  │
│  │  - @app/module-products                                   │  │
│  │  - @app/module-cart                                       │  │
│  │  - @app/module-pdp                                        │  │
│  │  - @pkg/ui, @pkg/state, etc.                             │  │
│  └──────────────────────────────────────────────────────────┘  │
│                            │                                    │
│                            │ npm publish                        │
│                            ▼                                    │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Verdaccio (Local Registry)                              │  │
│  │  http://localhost:4873                                   │  │
│  │  - Stores published @app/* and @pkg/* packages          │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                            │
                            │ npm install
                            │
        ┌───────────────────┴───────────────────┐
        │                                         │
        ▼                                         ▼
┌──────────────────────┐              ┌──────────────────────┐
│  NATIVE ANDROID APP  │              │   NATIVE iOS APP     │
│                      │              │                      │
│  ┌────────────────┐  │              │  ┌────────────────┐  │
│  │  js/           │  │              │  │  js/           │  │
│  │  - package.json│  │              │  │  - package.json│  │
│  │  - index.js    │  │              │  │  - index.js    │  │
│  │  - node_modules│  │              │  │  - node_modules│  │
│  └────────────────┘  │              │  └────────────────┘  │
│         │             │              │         │             │
│         │ Metro       │              │         │ Metro       │
│         │ Bundle      │              │         │ Bundle      │
│         ▼             │              │         ▼             │
│  ┌────────────────┐  │              │  ┌────────────────┐  │
│  │ index.android  │  │              │  │  main.jsbundle│  │
│  │ .bundle        │  │              │  │                │  │
│  └────────────────┘  │              │  └────────────────┘  │
│         │             │              │         │             │
│         │ Load        │              │         │ Load        │
│         ▼             │              │         ▼             │
│  ┌────────────────┐  │              │  ┌────────────────┐  │
│  │ ReactInstance  │  │              │  │  RCTBridge     │  │
│  │ Manager        │  │              │  │                │  │
│  └────────────────┘  │              │  └────────────────┘  │
│         │             │              │         │             │
│         │ Create      │              │         │ Create      │
│         ▼             │              │         ▼             │
│  ┌────────────────┐  │              │  ┌────────────────┐  │
│  │ ReactRootView  │  │              │  │  RCTRootView    │  │
│  │ (ModuleProducts)│  │              │  │ (ModuleProducts)│  │
│  └────────────────┘  │              │  └────────────────┘  │
│         │             │              │         │             │
│         │ Render      │              │         │ Render      │
│         ▼             │              │         ▼             │
│  ┌────────────────┐  │              │  ┌────────────────┐  │
│  │ ProductsActivity│  │              │  │ ProductsVC     │  │
│  │ (Native UI)    │  │              │  │ (Native UI)    │  │
│  └────────────────┘  │              │  └────────────────┘  │
│                      │              │                      │
│  ┌────────────────┐  │              │  ┌────────────────┐  │
│  │ NavigationBridge│ │              │  │ NavigationBridge│ │
│  │ (Native Module) │ │              │  │ (Native Module) │ │
│  └────────────────┘  │              │  └────────────────┘  │
│         ▲             │              │         ▲             │
│         │             │              │         │             │
│         └─────────────┴──────────────┴─────────┘             │
│                    JavaScript Bridge                         │
│              (NativeModules.NavigationBridge)                │
└──────────────────────────────────────────────────────────────┘
```

## Component Flow

```
Monorepo (Source)
    ↓
Verdaccio (Local Registry)
    ↓
Native Apps (Consumers)
    ↓
Metro Bundler (Creates JS Bundle)
    ↓
Native App Runtime (Loads Bundle)
    ↓
React Native Components (Rendered in Native Views)
```

## 1. Module Publishing System (Verdaccio)

### Overview

- **Local npm registry** running on `localhost:4873`
- **Scoped packages**: `@app/*` (modules), `@pkg/*` (shared packages)
- **Publishing command**: `npm run publish:verdaccio` from monorepo root

### Module Structure

Each module (e.g., `@app/module-products`) includes:

- `index.js` - Entry point with dual registration
- `App.native.tsx` - React Native component for native apps
- `App.tsx` - Web/Expo variant
- `package.json` - Metadata and dependencies

### Dual Registration Pattern

```javascript
// index.js - Registers for both Expo and Native apps
AppRegistry.registerComponent("ModuleProducts", () => App);  // For native apps

// Register with Expo for development (Expo Go, web via Expo, etc.)
// expo is a peerDependency, so it may not be available in native app bundles
let registerRootComponent;
try {
  registerRootComponent = require("expo").registerRootComponent;
  if (registerRootComponent) {
    registerRootComponent(App);
  }
} catch (e) {
  // Expo not available - AppRegistry is sufficient for native apps
}
```

**Why this pattern?** Modules need to work in:
- **Expo development** (requires `registerRootComponent`)
- **Native app bundles** (only needs `AppRegistry.registerComponent`)

## 2. Native App Setup

### Android (`native-android`)

#### JavaScript Dependencies (`js/package.json`)

```json
{
  "dependencies": {
    "@app/module-products": "^0.1.5",
    "@app/module-cart": "^0.1.5",
    "@app/module-pdp": "^0.1.5",
    "react": "19.1.0",
    "react-native": "0.81.5",
    "react-redux": "^9.2.0"
  },
  "devDependencies": {
    "expo": "^54.0.0"  // Only for Metro bundling, not runtime
  }
}
```

#### Entry Point (`js/index.js`)

```javascript
import { AppRegistry } from "react-native";

// Import modules to trigger their AppRegistry registration
import "@app/module-products"; // Registers "ModuleProducts"
import "@app/module-cart";     // Registers "ModuleCart"
import "@app/module-pdp";      // Registers "ModulePDP"

// Each module package already registers itself with AppRegistry
// We just need to ensure they're imported so the registration happens
```

#### Metro Configuration

- Resolves scoped packages from `node_modules`
- Handles optional `expo` dependency gracefully
- Bundles all modules into a single JS bundle

### iOS (`native-ios-app`)

- Similar structure with iOS-specific paths
- Bundle output: `ios/NativeIOSApp/NativeIOSApp/main.jsbundle`
- CocoaPods for native dependencies

## 3. Module Registration System

### How Modules Register

1. Module's `index.js` calls `AppRegistry.registerComponent("ModuleProducts", () => App)`
2. Native app imports the module, triggering registration
3. Native code references the registered name when creating React Native views

### Android Registration Flow

```kotlin
// ProductsActivity.kt
reactRootView = ReactRootView(this).also { view ->
    view.startReactApplication(instanceManager, "ModuleProducts", null)
    // "ModuleProducts" matches AppRegistry.registerComponent name
    setContentView(view)
}
```

### iOS Registration Flow

```swift
// AppDelegate.swift - Bridge loads bundle
bridge = RCTBridge(bundleURL: jsCodeLocation, moduleProvider: nil, launchOptions: nil)

// Individual ViewControllers create RCTRootView with module name
let rootView = RCTRootView(
    bridge: bridge,
    moduleName: "ModuleProducts",  // Matches AppRegistry name
    initialProperties: nil
)
```

## 4. Bridge Communication (NavigationBridge)

### Purpose

Enable JavaScript to trigger native navigation (e.g., navigate to PDP, Cart, Products screens).

### Android Implementation

#### NavigationBridgeModule.kt

```kotlin
class NavigationBridgeModule(reactContext: ReactApplicationContext) :
    ReactContextBaseJavaModule(reactContext) {
    
    override fun getName(): String = "NavigationBridge"
    
    @ReactMethod
    fun navigateToPDP(productId: String) {
        val activity = reactApplicationContext.currentActivity
        activity?.runOnUiThread {
            val intent = PdpActivity.createIntent(activity, productId)
            activity.startActivity(intent)
        }
    }
    
    @ReactMethod
    fun navigateToCart() {
        // Similar implementation
    }
    
    @ReactMethod
    fun navigateToProducts() {
        // Similar implementation
    }
}
```

#### Registration

```kotlin
// MainApplication.kt
override fun getPackages(): List<ReactPackage> {
    val packageList = PackageList(this)
    val autolinkedPackages = ArrayList(packageList.getPackages())
    autolinkedPackages.add(NavigationBridgePackage())  // Custom bridge
    return autolinkedPackages
}
```

### iOS Implementation

#### NavigationBridge.swift

```swift
@objc(NavigationBridge)
class NavigationBridge: NSObject, RCTBridgeModule {
    static func moduleName() -> String! { return "NavigationBridge" }
    
    @objc func navigateToPDP(_ productId: String) {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first,
                  let navigationController = window.rootViewController as? UINavigationController else {
                return
            }
            
            let pdpVC = PDPViewController(productId: productId)
            navigationController.pushViewController(pdpVC, animated: true)
        }
    }
    
    @objc func navigateToCart() {
        // Similar implementation
    }
    
    @objc func navigateToProducts() {
        // Similar implementation
    }
}
```

#### Objective-C Bridge (`NavigationBridge.m`)

```objc
#import <React/RCTBridgeModule.h>

@interface RCT_EXTERN_MODULE(NavigationBridge, NSObject)

RCT_EXTERN_METHOD(navigateToPDP:(NSString *)productId)
RCT_EXTERN_METHOD(navigateToCart)
RCT_EXTERN_METHOD(navigateToProducts)

@end
```

### JavaScript Usage

```typescript
// App.native.tsx
let NavigationBridge: any = undefined;
try {
  NavigationBridge = NativeModules.NavigationBridge;
} catch (e) {
  NavigationBridge = undefined;  // Graceful fallback for Expo Go
}

const handleProductPress = (productId: string) => {
  if (Platform.OS === "web") {
    console.log("Navigate to PDP:", productId);
  } else if (NavigationBridge) {
    NavigationBridge.navigateToPDP(productId);  // Calls native code
  } else {
    // Expo Go - just log for now
    console.log("Navigate to PDP:", productId, "(Expo Go - NavigationBridge not available)");
  }
};
```

## 5. Bundle Generation Process

### Android Bundle

```bash
cd native-android/js
npm run bundle
# Creates: app/src/main/assets/index.android.bundle
```

### iOS Bundle

```bash
cd native-ios-app/js
npm run bundle
# Creates: ios/NativeIOSApp/NativeIOSApp/main.jsbundle
```

### What Gets Bundled

- All imported modules (`@app/module-products`, etc.)
- Shared packages (`@pkg/ui`, `@pkg/state`, etc.)
- React Native core
- Redux store configuration
- NavigationBridge integration code

### Bundle Loading

#### Android

```kotlin
// MainApplication.kt
override fun getBundleAssetName(): String = "index.android.bundle"
override fun getJSMainModuleName(): String = "index"
```

#### iOS

```swift
// AppDelegate.swift
if let bundleURL = Bundle.main.url(forResource: "main", withExtension: "jsbundle") {
    jsCodeLocation = bundleURL  // Production: from app bundle
} else {
    jsCodeLocation = RCTBundleURLProvider.sharedSettings().jsBundleURL(...)  // Dev: Metro
}
```

## 6. State Management Integration

### Redux Store Initialization

```typescript
// App.native.tsx
const [appStore, setAppStore] = React.useState<AppStore>(
  store || configureStore()  // Synchronous initialization
);

// Load persisted state in background (native apps only)
React.useEffect(() => {
  if (store) {
    return; // Store already provided
  }

  // Skip persisted state loading for web or Expo Go
  if (Platform.OS === "web") {
    return;
  }

  // Only load persisted state if NavigationBridge exists (real native app)
  if (!NavigationBridge) {
    return; // Skip in Expo Go
  }

  // Load persisted state asynchronously for native apps only
  loadPersistedState()
    .then((persistedState) => {
      if (persistedState) {
        setAppStore(configureStore(persistedState));
      }
    })
    .catch((error) => {
      console.warn("Failed to load persisted state, using fresh store:", error);
    });
}, [store]);
```

### Why Synchronous Initialization

- Prevents blank screens during store creation
- Works across Expo, native apps, and web
- Persisted state loads in the background without blocking render

## 7. Build Configuration

### Android Build Setup

#### React Native Host Configuration

```kotlin
// MainApplication.kt
override val reactNativeHost: ReactNativeHost = object : DefaultReactNativeHost(this) {
    override fun getUseDeveloperSupport(): Boolean = false  // Production bundle
    override fun getBundleAssetName(): String = "index.android.bundle"
    override fun getJSMainModuleName(): String = "index"
    
    override fun getPackages(): List<ReactPackage> {
        val packageList = PackageList(this)
        val autolinkedPackages = ArrayList(packageList.getPackages())
        autolinkedPackages.add(NavigationBridgePackage())
        return autolinkedPackages
    }
}
```

#### Hermes Engine

```kotlin
override fun onCreate() {
    super.onCreate()
    System.setProperty("react_native_hermes_enabled", "true")
    SoLoader.init(this, OpenSourceMergedSoMapping)  // For hermes_executor
}
```

#### Autolinking Exclusions

```gradle
// app/build.gradle
tasks.named('generateAutolinkingPackageList').configure {
    doLast {
        // Remove ExpoModulesPackage (expo only in devDependencies)
        def packageListFile = file("${project.buildDir}/generated/autolinking/src/main/java/com/facebook/react/PackageList.java")
        if (packageListFile.exists()) {
            def content = packageListFile.text
            // Remove ExpoModulesPackage import
            content = content.replaceAll('import expo\\.modules\\.ExpoModulesPackage;', '// ExpoModulesPackage removed')
            // Remove ExpoModulesPackage() from the list
            content = content.replaceAll(',\\s*new ExpoModulesPackage\\(\\)', '')
            packageListFile.text = content
        }
    }
}
```

### iOS Build Setup

#### Podfile Configuration

```ruby
platform :ios, '16.0'
use_frameworks!

target 'NativeIOSApp' do
  config = use_native_modules!
  use_react_native!(
    :hermes_enabled => true,  # Enable Hermes
    :fabric_enabled => true
  )
end
```

#### Xcode Configuration

- `ENABLE_USER_SCRIPT_SANDBOXING = NO` (for build scripts)
- Bundle added to "Copy Bundle Resources" build phase
- Hermes headers configured via postinstall script

## 8. Key Configuration Fixes

### Fix 1: Expo Compatibility

**Problem**: `registerRootComponent` needed for Expo, but `expo` not available in native bundles.

**Solution**: Try-catch wrapped registration that gracefully handles missing `expo`:

```javascript
let registerRootComponent;
try {
  registerRootComponent = require("expo").registerRootComponent;
  if (registerRootComponent) {
    registerRootComponent(App);
  }
} catch (e) {
  // Expo not available - AppRegistry is sufficient for native apps
}
```

### Fix 2: Autolinking Expo Modules

**Problem**: React Native autolinking tried to link `ExpoModulesPackage` from `devDependencies`.

**Solution**: Post-build script removes `ExpoModulesPackage` from generated `PackageList.java`.

### Fix 3: Metro Resolver Configuration

**Problem**: Metro couldn't resolve scoped packages (`@app/*`, `@pkg/*`).

**Solution**:

```javascript
// metro.config.js
resolver: {
  nodeModulesPaths: [nodeModules],  // Explicit path
  unstable_enablePackageExports: true,  // Handle optional deps
}
```

### Fix 4: SDK Path Detection

**Problem**: React Native couldn't find Android SDK during build.

**Solution**: Postinstall script patches `hermes-engine/build.gradle.kts` to read from `local.properties` files.

## 9. Development Workflow

### For Module Developers (Monorepo)

1. Make changes to modules in monorepo
2. Bump version in `package.json`
3. Publish: `npm run publish:verdaccio`
4. Native apps pull updates: `npm install @app/module-products@latest`

### For Native App Developers

1. **Start Verdaccio**: `cd monorepo && npm run verdaccio:start`
2. **Install dependencies**: `cd native-android/js && npm install --legacy-peer-deps`
3. **Generate bundle**: `npm run bundle`
4. **Build native app**: 
   - Android: `./gradlew :app:assembleDebug`
   - iOS: Build in Xcode

## 10. Current Module Versions

- `@app/module-products`: 0.1.5
- `@app/module-cart`: 0.1.6
- `@app/module-pdp`: 0.1.6

All published to Verdaccio and working in both native apps.

## 11. Architecture Benefits

1. **Code Sharing**: Modules written once, used in native apps and Expo
2. **Independent Deployment**: Update modules without rebuilding native apps
3. **Native Integration**: Full access to native APIs via bridges
4. **Development Flexibility**: Test in Expo, deploy to native apps
5. **State Persistence**: Redux store persists across app sessions

## 12. Communication Flow

### JavaScript → Native (Navigation)

```
React Component
    ↓
NavigationBridge.navigateToPDP(productId)
    ↓
NativeModules.NavigationBridge (React Native Bridge)
    ↓
NavigationBridgeModule (Android) / NavigationBridge (iOS)
    ↓
Native Activity/ViewController
```

### Native → JavaScript (Events)

```
Native Code
    ↓
DeviceEventEmitter.emit('eventName', data)
    ↓
React Native Event System
    ↓
React Component (Event Listener)
```

## Summary

The integration enables native Android and iOS apps to embed React Native modules published from the monorepo. Modules are consumed via Verdaccio, bundled with Metro, and loaded at runtime. The NavigationBridge enables JavaScript-to-native communication, and the dual registration pattern supports both Expo development and native app deployment. The system is production-ready with proper configuration for build systems, module resolution, and cross-platform compatibility.

