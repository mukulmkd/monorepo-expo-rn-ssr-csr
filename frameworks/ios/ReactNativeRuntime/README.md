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
import ReactNativeRuntime
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

## Notes

- Headers are available via `import React` and `import ReactCommon`
- All React Native static libraries are linked via xcframeworks
- Hermes engine is included for JavaScript execution
