# iOS Integration Guide

This guide explains how to integrate React Native bundles (like `module-products`) into existing iOS applications.

## Prerequisites

- Existing iOS app with React Native installed
- React Native version >= 0.81.5
- Xcode installed

## Step 1: Add Bundle to Project

1. Copy `module-products.bundle` to your iOS project:

   ```
   ios/
   └── Products/
       └── module-products.bundle
   ```

2. Copy assets folder:

   ```
   ios/
   └── Products/
       └── assets/
           ├── images/
           └── fonts/
   ```

3. In Xcode, add files to project:
   - Right-click project → "Add Files to [Project]"
   - Select `module-products.bundle` and `assets` folder
   - Ensure "Copy items if needed" is checked
   - Add to target

## Step 2: Create React Native View Controller

Create `ProductsViewController.swift`:

```swift
import UIKit
import React

class ProductsViewController: UIViewController {
  var reactRootView: RCTRootView?

  override func viewDidLoad() {
    super.viewDidLoad()
    loadReactNativeModule()
  }

  func loadReactNativeModule() {
    // Path to bundle
    guard let jsCodeLocation = Bundle.main.url(
      forResource: "module-products",
      withExtension: "bundle"
    ) else {
      print("Bundle not found")
      return
    }

    // Create React root view
    let rootView = RCTRootView(
      bundleURL: jsCodeLocation,
      moduleName: "ModuleProducts",
      initialProperties: [
        // Add any props here
        "onProductPress": true
      ],
      launchOptions: nil
    )

    rootView?.backgroundColor = .white
    self.view = rootView
    self.reactRootView = rootView
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    // Cleanup if needed
  }
}
```

## Step 3: Bridge Event Handlers (Optional)

If you need to handle events from React Native:

Create `ProductsBridge.swift`:

```swift
import Foundation
import React

@objc(ProductsBridge)
class ProductsBridge: NSObject {

  @objc static func requiresMainQueueSetup() -> Bool {
    return true
  }

  // Method called from React Native
  @objc func handleProductPress(_ productId: String) {
    DispatchQueue.main.async {
      // Handle product press event
      print("Product pressed: \(productId)")
      // Navigate or perform action in native app
    }
  }
}
```

Create `ProductsBridge.m` (Objective-C bridge):

```objc
#import <React/RCTBridgeModule.h>

@interface RCT_EXTERN_MODULE(ProductsBridge, NSObject)

RCT_EXTERN_METHOD(handleProductPress:(NSString *)productId)

@end
```

## Step 4: Update AppDelegate (if needed)

If using React Native bridge:

```swift
import React

class AppDelegate: UIResponder, UIApplicationDelegate {
  var reactBridge: RCTBridge?

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Initialize React Native bridge if not already done
    // Your existing React Native setup

    return true
  }
}
```

## Step 5: Navigate to Products View

In your existing iOS app:

```swift
// Push to products screen
let productsVC = ProductsViewController()
navigationController?.pushViewController(productsVC, animated: true)

// Or present modally
let productsVC = ProductsViewController()
let nav = UINavigationController(rootViewController: productsVC)
present(nav, animated: true)
```

## Testing

1. Build and run iOS app
2. Navigate to ProductsViewController
3. Verify bundle loads correctly
4. Test all functionality

## Troubleshooting

### Bundle Not Found

- Check bundle is included in "Copy Bundle Resources" build phase
- Verify bundle name matches exactly (case-sensitive)

### Module Not Registered

- Ensure `registerRootComponent` or `AppRegistry.registerComponent` is called in bundle
- Check module name matches in `RCTRootView` and bundle

### Assets Missing

- Verify assets folder is included in project
- Check asset paths in React Native code

## Dependencies

Ensure your iOS project includes:

- React Native framework
- React Native dependencies (from Podfile)
- Redux and React Redux (if using state management)
