# ModulePDPFramework

iOS SPM framework for ModulePDP React Native module.

## Overview

This framework contains:
- Pre-bundled JavaScript code (module-pdp.bundle)
- Swift wrapper API for easy integration
- No Verdaccio or npm required at runtime

## Prerequisites

- ReactNativeRuntime SPM package must be added to the consuming app first
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
2. Navigate to: `frameworks/ios/ModulePDPFramework`
3. Add to target

**Note:** This framework automatically depends on ReactNativeRuntime, so Xcode will resolve it automatically if ReactNativeRuntime is already added.

### 3. Use in Code

```swift
import ModulePDPFramework
// React types are automatically available via ReactNativeRuntime dependency

// Option 1: Use convenience method (recommended)
if let rootView = ModulePDPFramework.shared.createView() {
    view.addSubview(rootView)
    rootView.frame = view.bounds
    rootView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
}

// Option 2: Manual setup (if you need more control)
let bundleURL = ModulePDPFramework.shared.getBundleURL()
let moduleName = ModulePDPFramework.shared.getModuleName()
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
`Resources/module-pdp.bundle`

This bundle was created from the latest version published to Verdaccio.

## Version

Generated from: @app/module-pdp
Source: Verdaccio registry
