# React Native Runtime SPM Package

This package provides React Native 0.81.5 runtime as a Swift Package Manager (SPM) package.

## Usage

### Add to Xcode Project

1. Open your Xcode project
2. Go to **File → Add Package Dependencies...**
3. Click **Add Local...**
4. Navigate to this directory: `frameworks/ios/ReactNativeRuntime`
5. Select your target and add the package

### In Your Code

```swift
import MKDReactNativeRuntime
import React

// Use React Native types
let bridge = RCTBridge(bundleURL: url, moduleProvider: nil, launchOptions: nil)
let rootView = RCTRootView(bridge: bridge, moduleName: "YourModule", initialProperties: nil)
```

## Included Frameworks

This package includes the following React Native frameworks:


## Requirements

- iOS 14.0+
- Xcode 14+
- Swift 5.9+

## Version

React Native 0.81.5

## Header Coverage for Brownfield Integration

This package includes **160 public headers** covering all essential React Native APIs for Brownfield integration with React Native 0.81.5.

### ✅ Complete Header Coverage

All critical headers required for RN 0.81.5 Brownfield integration are included:

#### Core Brownfield Headers
- `RCTRootView.h` - Embedding RN components in native views
- `RCTBridge.h` - JS-Native bridge communication
- `RCTBridgeModule.h` - Creating native modules
- `RCTViewManager.h` - Custom view managers
- `RCTShadowView.h` - Layout system
- `RCTComponent.h` - Component protocol
- `RCTEventEmitter.h` - Event communication
- `RCTTurboModuleRegistry.h` - TurboModules support (RN 0.81.5)

#### Core Modules
- `RCTEventDispatcher.h` - Event dispatching
- `RCTUIManager.h` - UI management
- `RCTBundleURLProvider.h` - Bundle loading
- `RCTJavaScriptLoader.h` - JavaScript loading
- All CoreModules (Accessibility, AppState, Clipboard, DeviceInfo, etc.)

#### UI Components
- `RCTView.h`, `RCTScrollView.h`, `RCTSafeAreaView.h`
- `RCTModalHostView.h`, `RCTActivityIndicatorView.h`
- All view managers for built-in components

#### Advanced Features
- `RCTSurface.h` - Surface API for advanced rendering
- `RCTTurboModuleRegistry.h` - TurboModules (New Architecture support)
- `RCTCallInvokerModule.h` - Call invoker for async operations
- Dev support headers (for development tools)

### What You Can Do

With these headers, you can:

- ✅ Create `RCTRootView` instances to embed React Native components
- ✅ Create native modules using `RCTBridgeModule` protocol
- ✅ Create custom view managers using `RCTViewManager`
- ✅ Use TurboModules via `RCTTurboModuleRegistry` (RN 0.81.5)
- ✅ Handle events and communicate between JS and Native
- ✅ Use all CoreModules (Accessibility, AppState, Clipboard, etc.)
- ✅ Use all UI components (View, ScrollView, Modal, etc.)
- ✅ Use Surface API for advanced rendering scenarios

### Usage Example

```swift
import UIKit
import React

class ProductsViewController: UIViewController {
    var reactRootView: RCTRootView?
    var bridge: RCTBridge?

    override func viewDidLoad() {
        super.viewDidLoad()
        loadReactNativeModule()
    }

    func loadReactNativeModule() {
        guard let bundleURL = Bundle.main.url(
            forResource: "module-products",
            withExtension: "bundle"
        ) else {
            print("Bundle not found")
            return
        }

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

    deinit {
        bridge?.invalidate()
    }
}
```

## Notes

- Headers are available via `import React` (umbrella header includes all 160 headers)
- All React Native static libraries are linked via xcframeworks
- Hermes engine is included for JavaScript execution
- This package is **complete and sufficient** for RN 0.81.5 Brownfield integration
- No additional headers are required beyond what's included in this package
