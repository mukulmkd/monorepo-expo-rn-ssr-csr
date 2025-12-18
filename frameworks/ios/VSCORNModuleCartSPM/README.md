# ModuleCartFramework

iOS SPM framework for ModuleCart React Native module.

## Overview

This framework contains:
- Pre-bundled JavaScript code (module-cart.bundle)
- Swift wrapper API for easy integration
- No Verdaccio or npm required at runtime

## Prerequisites

- VSCOReactNativeRuntime SPM package must be added to the consuming app first
- iOS 14.0+
- Xcode 14+

## Usage

### 1. Add ReactNativeRuntime First (Required)

In Xcode:
1. File → Add Package Dependencies → Add Local...
2. Navigate to: `frameworks/ios/ReactNativeRuntime`
3. Add to target

**Important:** ReactNativeRuntime must be added before this framework.

### 2. Add This Framework

In Xcode:
1. File → Add Package Dependencies → Add Local...
2. Navigate to: `frameworks/ios/VSCORNModuleCartSPM`
3. Add to target

**Note:** This framework automatically depends on VSCOReactNativeRuntime, so Xcode will resolve it automatically if VSCOReactNativeRuntime is already added.

### 3. Use in Code

```swift
import VSCORNModuleCartSPM
// React types are automatically available via VSCOReactNativeRuntime dependency

// Option 1: Use convenience method (recommended)
if let rootView = ModuleCartFramework.shared.createView() {
    view.addSubview(rootView)
    rootView.frame = view.bounds
    rootView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
}

// Option 2: Manual setup (if you need more control)
let bundleURL = ModuleCartFramework.shared.getBundleURL()
let moduleName = ModuleCartFramework.shared.getModuleName()
let bridge = RCTBridge(bundleURL: bundleURL, moduleProvider: nil, launchOptions: nil)
let rootView = RCTRootView(bridge: bridge, moduleName: moduleName, initialProperties: nil)
view.addSubview(rootView)
```

## API

- `getBundleURL() -> URL?` - Returns bundle file URL
- `getModuleName() -> String` - Returns registered module name
- `createView(moduleName:initialProperties:) -> RCTRootView?` - Creates React Native view
- `invalidate()` - Cleans up bridge

## Bundle

The JavaScript bundle is embedded in:
`Resources/module-cart.bundle`

This bundle was created from the latest version published to Verdaccio.

## Version

Generated from: @app/module-cart
Source: Verdaccio registry
