# Expo Modules Setup Requirements for iOS

## Error: "Cannot read property 'EventEmitter' of undefined"

This error occurs when Expo modules are not properly initialized in the consuming iOS app's **main bridge**. 

**Important**: The module framework creates its own isolated bridge, but it relies on the consuming app's main bridge having Expo modules registered. The module framework's bridge can access Expo modules from the main app's bridge context.

## Required Dependencies in Consuming App

The consuming iOS app **MUST** include these SPM packages:

1. **VSCOReactNativeRuntime** - React Native runtime
   - Add via: File → Add Package Dependencies → Add Local...
   - Path: `frameworks/ios/VSCOReactNativeRuntime`

2. **VSCONativeKit** - Native dependencies including Expo modules
   - Add via: File → Add Package Dependencies → Add Local...
   - Path: `vsco-native-kit/ios/VSCONativeKit`
   - This provides `EXModuleRegistryAdapter` and all Expo modules

3. **VSCORNModuleProductsSPM** - Module framework
   - Add via: File → Add Package Dependencies → Add Local...
   - Path: `frameworks/ios/VSCORNModuleProductsSPM`

## Required Setup in AppDelegate

The consuming app's `AppDelegate.swift` or `AppDelegate.m` **MUST** register Expo modules in the main React Native bridge:

### Swift (AppDelegate.swift)

```swift
import UIKit
import React
import VSCONativeKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    var bridge: RCTBridge?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Create React Native bridge with Expo modules
        let jsCodeLocation = Bundle.main.url(forResource: "main", withExtension: "jsbundle") ?? 
                            URL(string: "http://localhost:8081/index.bundle?platform=ios")!
        
        // Module provider that registers Expo modules
        // EXNativeModulesProxy auto-initializes and discovers all Expo modules
        let moduleProvider: RCTBridgeModuleListProvider = { bridge in
            var modules: [RCTBridgeModule.Type] = []
            
            // Register EXNativeModulesProxy - auto-discovers and registers all Expo modules
            if let nativeModulesProxyClass = NSClassFromString("EXNativeModulesProxy") as? RCTBridgeModule.Type {
                modules.append(nativeModulesProxyClass)
            }
            
            // Register EXReactNativeEventEmitter - required for Expo EventEmitter
            if let eventEmitterClass = NSClassFromString("EXReactNativeEventEmitter") as? RCTBridgeModule.Type {
                modules.append(eventEmitterClass)
            }
            
            return modules
        }
        
        bridge = RCTBridge(bundleURL: jsCodeLocation, moduleProvider: moduleProvider, launchOptions: launchOptions)
        
        let rootView = RCTRootView(bridge: bridge!, moduleName: "YourApp", initialProperties: nil)
        
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = UIViewController()
        window?.rootViewController?.view = rootView
        window?.makeKeyAndVisible()
        
        return true
    }
}
```

### Objective-C (AppDelegate.m)

```objc
#import "AppDelegate.h"
#import <React/RCTBridge.h>
#import <React/RCTRootView.h>
#import <VSCONativeKit/VSCONativeKit.h>

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    NSURL *jsCodeLocation = [[NSBundle mainBundle] URLForResource:@"main" withExtension:@"jsbundle"] ?:
                            [NSURL URLWithString:@"http://localhost:8081/index.bundle?platform=ios"];
    
    // Module provider that registers Expo modules
    // EXNativeModulesProxy auto-initializes and discovers all Expo modules
    RCTBridgeModuleListProvider moduleProvider = ^NSArray<Class> *(RCTBridge *bridge) {
        NSMutableArray<Class> *moduleClasses = [NSMutableArray new];
        
        // Register EXNativeModulesProxy - auto-discovers and registers all Expo modules
        Class nativeModulesProxyClass = NSClassFromString(@"EXNativeModulesProxy");
        if (nativeModulesProxyClass) {
            [moduleClasses addObject:nativeModulesProxyClass];
        }
        
        // Register EXReactNativeEventEmitter - required for Expo EventEmitter
        Class eventEmitterClass = NSClassFromString(@"EXReactNativeEventEmitter");
        if (eventEmitterClass) {
            [moduleClasses addObject:eventEmitterClass];
        }
        
        return moduleClasses;
    };
    
    RCTBridge *bridge = [[RCTBridge alloc] initWithBundleURL:jsCodeLocation
                                                moduleProvider:moduleProvider
                                                 launchOptions:launchOptions];
    
    RCTRootView *rootView = [[RCTRootView alloc] initWithBridge:bridge
                                                      moduleName:@"YourApp"
                                               initialProperties:nil];
    
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    UIViewController *rootViewController = [UIViewController new];
    rootViewController.view = rootView;
    self.window.rootViewController = rootViewController;
    [self.window makeKeyAndVisible];
    
    return YES;
}

@end
```

## Verification Checklist

- [ ] `VSCONativeKit` SPM package is added to the project
- [ ] `VSCOReactNativeRuntime` SPM package is added to the project
- [ ] `VSCORNModuleProductsSPM` SPM package is added to the project
- [ ] `EXModuleRegistryAdapter` is registered in `AppDelegate`'s bridge
- [ ] `VSCONativeKit` is imported in `AppDelegate`

## Common Issues

### Issue 1: EXModuleRegistryAdapter not found
**Solution**: Ensure `VSCONativeKit` SPM package is added to the project and imported.

### Issue 2: EventEmitter undefined
**Solution**: This happens when `EXModuleRegistryAdapter` is not registered in the main app's bridge. Follow the AppDelegate setup above.

### Issue 3: ModuleProduct has not been registered
**Solution**: Ensure the module framework SPM package is added and the module is properly registered in your app's JavaScript entry point.

## Notes

- The module framework creates its own isolated bridge with `moduleProvider: nil`.
- The module framework's bridge can access Expo modules from the **main app's bridge** when they are registered there.
- **The consuming app's main bridge MUST register Expo modules** for the module framework to work with Expo modules (e.g., `expo-file-system`).
- If you get "EventEmitter undefined" errors, it means Expo modules are not registered in the main app's bridge.

