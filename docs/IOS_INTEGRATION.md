# iOS Integration Guide

This guide explains how to integrate React Native modules from this monorepo into existing iOS applications using the **Verdaccio npm registry approach**.

> **Note:** This guide provides a high-level overview. For detailed step-by-step instructions, see [NATIVE_APP_CONSUMPTION.md](./NATIVE_APP_CONSUMPTION.md).

## Prerequisites

- Existing iOS app with React Native installed
- React Native version >= 0.81.5
- Xcode installed
- Node.js >= 20
- CocoaPods installed
- Verdaccio running locally (see [LOCAL_REGISTRY.md](./LOCAL_REGISTRY.md))

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

4. **Bundle for iOS**

   ```bash
   npm run bundle:ios:products
   ```

5. **Load in iOS ViewController**

   See [NATIVE_APP_CONSUMPTION.md](./NATIVE_APP_CONSUMPTION.md) for complete ViewController implementation.

## Detailed Integration

For complete integration instructions including:
- Directory structure
- CocoaPods configuration
- ViewController implementation
- Bundle loading
- Native module bridges

See **[NATIVE_APP_CONSUMPTION.md](./NATIVE_APP_CONSUMPTION.md)** - Section 3: iOS Project Template.

## Alternative: Manual Bundle Approach

If you prefer to manually copy bundles (not recommended for development):

1. Build bundle from this monorepo
2. Copy `main.jsbundle` to your iOS project
3. Copy assets to the project
4. Load bundle in your ViewController

This approach is less flexible and harder to maintain. Use Verdaccio for better workflow.

## React Native ViewController Example

Basic ViewController to host a module:

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
        guard let jsCodeLocation = Bundle.main.url(
            forResource: "main",
            withExtension: "jsbundle",
            subdirectory: "ModuleProducts"
        ) else {
            print("Bundle not found")
            return
        }

        bridge = RCTBridge(bundleURL: jsCodeLocation, moduleProvider: nil, launchOptions: nil)
        let rootView = RCTRootView(
            bridge: bridge!,
            moduleName: "ModuleProducts",
            initialProperties: nil
        )

        rootView.backgroundColor = .white
        self.view = rootView
        self.reactRootView = rootView
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Cleanup if needed
    }

    deinit {
        bridge?.invalidate()
    }
}
```

## CocoaPods Configuration

Your `Podfile` should include:

```ruby
require_relative '../js/node_modules/react-native/scripts/autolink-ios'

platform :ios, '14.0'

target 'YourApp' do
  config = use_native_modules!

  use_react_native!(
    :path => '../js/node_modules/react-native',
    :hermes_enabled => false,
    :fabric_enabled => false
  )
end
```

Run `pod install` after configuration.

## Native Module Bridge (Optional)

If you need to communicate between React Native and native iOS:

See [NATIVE_APP_CONSUMPTION.md](./NATIVE_APP_CONSUMPTION.md) for bridge implementation examples.

## Troubleshooting

### Bundle Not Found
- Verify bundle was generated: `ls ios/ModuleProducts/main.jsbundle`
- Check bundle script output for errors
- Ensure bundle is included in "Copy Bundle Resources" build phase
- Verify Metro can resolve `@app/*` packages (check `.npmrc`)

### Module Not Registered
- Verify module is imported in `js/index.js`
- Check module name matches: `"ModuleProducts"` (case-sensitive)
- Ensure `AppRegistry.registerComponent` is called in the module

### Package Resolution Errors
- Verify Verdaccio is running: `curl http://localhost:4873`
- Check `.npmrc` configuration
- Run `npm install` again in the JS workspace

### CocoaPods Issues
- Run `pod deintegrate && pod install`
- Clear derived data: `rm -rf ~/Library/Developer/Xcode/DerivedData`
- Check Podfile syntax

### Hermes Issues
- See [NATIVE_APP_CONSUMPTION.md](./NATIVE_APP_CONSUMPTION.md) for Hermes configuration
- Consider using JSC if Hermes causes issues

## Related Documentation

- **[NATIVE_APP_CONSUMPTION.md](./NATIVE_APP_CONSUMPTION.md)** - Complete Android/iOS integration guide
- **[LOCAL_REGISTRY.md](./LOCAL_REGISTRY.md)** - Setting up and using Verdaccio
- **[MODULE_DISTRIBUTION.md](./MODULE_DISTRIBUTION.md)** - How modules are published
- **[PACKAGES.md](./PACKAGES.md)** - Package API documentation
