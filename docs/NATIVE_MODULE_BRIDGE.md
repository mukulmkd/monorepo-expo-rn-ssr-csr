# Native Module Bridge: React Native ↔ Native Communication

This guide explains how React Native modules communicate with native Android and iOS code, enabling bidirectional data passing and method calls.

## Table of Contents

1. [Overview](#overview)
2. [Communication Patterns](#communication-patterns)
3. [Android Native Modules](#android-native-modules)
4. [iOS Native Modules](#ios-native-modules)
5. [Calling Native from React Native](#calling-native-from-react-native)
6. [Sending Events from Native to React Native](#sending-events-from-native-to-react-native)
7. [Data Type Mapping](#data-type-mapping)
8. [Complete Examples](#complete-examples)
9. [Best Practices](#best-practices)
10. [Troubleshooting](#troubleshooting)

---

## Overview

React Native provides a **bridge** that allows JavaScript code to communicate with native code (Java/Kotlin on Android, Objective-C/Swift on iOS). This enables:

- ✅ **JavaScript → Native**: Call native methods from React Native
- ✅ **Native → JavaScript**: Send events/data from native to React Native
- ✅ **Bidirectional**: Pass data in both directions

### How It Works

```
┌─────────────────┐         Bridge          ┌─────────────────┐
│  React Native   │ ◄─────────────────────► │  Native Code    │
│   (JavaScript)  │   Method Calls & Events │  (Kotlin/Swift) │
└─────────────────┘                         └─────────────────┘
```

The bridge is **asynchronous** by default, meaning:
- Method calls don't block the JavaScript thread
- Events are sent asynchronously
- Large data transfers are efficient

---

## Communication Patterns

### Pattern 1: JavaScript Calls Native Method

**Use Case**: React Native needs to trigger native functionality (navigation, native UI, device features)

```javascript
// React Native
import { NativeModules } from 'react-native';

const { MyNativeModule } = NativeModules;
MyNativeModule.doSomething('data');
```

```kotlin
// Android
@ReactMethod
fun doSomething(data: String) {
    // Native implementation
}
```

### Pattern 2: Native Sends Event to JavaScript

**Use Case**: Native code needs to notify React Native (user actions, system events, async callbacks)

```javascript
// React Native
import { NativeEventEmitter, NativeModules } from 'react-native';

const { MyNativeModule } = NativeModules;
const emitter = new NativeEventEmitter(MyNativeModule);

emitter.addListener('EventName', (data) => {
    console.log('Received:', data);
});
```

```kotlin
// Android
sendEvent(reactContext, "EventName", WritableMap().apply {
    putString("key", "value")
})
```

### Pattern 3: Promise-Based Calls

**Use Case**: Native method returns a result asynchronously

```javascript
// React Native
const result = await MyNativeModule.getDataAsync();
```

```kotlin
// Android
@ReactMethod
fun getDataAsync(promise: Promise) {
    promise.resolve("result")
}
```

---

## Android Native Modules

### Step 1: Create the Native Module Class

**`app/src/main/java/com/yourapp/bridge/MyNativeModule.kt`:**

```kotlin
package com.yourapp.bridge

import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.WritableMap
import com.facebook.react.bridge.Arguments
import com.facebook.react.modules.core.DeviceEventManagerModule

class MyNativeModule(reactContext: ReactApplicationContext) :
    ReactContextBaseJavaModule(reactContext) {

    override fun getName(): String {
        return "MyNativeModule"
    }

    // Simple method call
    @ReactMethod
    fun doSomething(data: String) {
        // Your native implementation
        println("Received from React Native: $data")
    }

    // Method with callback (Promise)
    @ReactMethod
    fun getDataAsync(promise: Promise) {
        try {
            val result = fetchDataFromNative()
            promise.resolve(result)
        } catch (e: Exception) {
            promise.reject("ERROR_CODE", e.message, e)
        }
    }

    // Method with multiple parameters
    @ReactMethod
    fun processData(
        userId: String,
        amount: Double,
        isActive: Boolean,
        promise: Promise
    ) {
        // Process data
        val result = processNativeData(userId, amount, isActive)
        promise.resolve(result)
    }

    // Send event to React Native
    private fun sendEvent(eventName: String, params: WritableMap?) {
        reactApplicationContext
            .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
            .emit(eventName, params)
    }

    // Helper method to send events
    fun notifyReactNative(data: String) {
        val params = Arguments.createMap().apply {
            putString("message", data)
            putDouble("timestamp", System.currentTimeMillis().toDouble())
        }
        sendEvent("NativeEvent", params)
    }

    private fun fetchDataFromNative(): String {
        // Your native logic
        return "Data from native"
    }

    private fun processNativeData(
        userId: String,
        amount: Double,
        isActive: Boolean
    ): WritableMap {
        return Arguments.createMap().apply {
            putString("userId", userId)
            putDouble("processedAmount", amount * 1.1)
            putBoolean("status", isActive)
        }
    }
}
```

### Step 2: Create the Package

**`app/src/main/java/com/yourapp/bridge/MyNativePackage.kt`:**

```kotlin
package com.yourapp.bridge

import com.facebook.react.ReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.uimanager.ViewManager

class MyNativePackage : ReactPackage {
    override fun createNativeModules(
        reactContext: ReactApplicationContext
    ): List<NativeModule> {
        return listOf(MyNativeModule(reactContext))
    }

    override fun createViewManagers(
        reactContext: ReactApplicationContext
    ): List<ViewManager<*, *>> {
        return emptyList()
    }
}
```

### Step 3: Register the Package

**`app/src/main/java/com/yourapp/MainApplication.kt`:**

```kotlin
import com.yourapp.bridge.MyNativePackage

class MainApplication : Application(), ReactApplication {
    override val reactNativeHost: ReactNativeHost = object : DefaultReactNativeHost(this) {
        override fun getPackages(): List<ReactPackage> = listOf(
            MainReactPackage(),
            MyNativePackage() // Add your package here
        )
    }
}
```

### Example: Navigation Bridge (Real Implementation)

Based on the existing `NavigationBridge` in your codebase:

**`app/src/main/java/com/yourapp/bridge/NavigationBridgeModule.kt`:**

```kotlin
package com.yourapp.bridge

import android.app.Activity
import android.content.Intent
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod

class NavigationBridgeModule(reactContext: ReactApplicationContext) :
    ReactContextBaseJavaModule(reactContext) {

    override fun getName(): String {
        return "NavigationBridge"
    }

    @ReactMethod
    fun navigateToPDP(productId: String) {
        val activity = currentActivity
        activity?.runOnUiThread {
            val intent = Intent(activity, PDPActivity::class.java).apply {
                putExtra("productId", productId)
            }
            activity.startActivity(intent)
        }
    }

    @ReactMethod
    fun navigateToCart() {
        val activity = currentActivity
        activity?.runOnUiThread {
            val intent = Intent(activity, CartActivity::class.java)
            activity.startActivity(intent)
        }
    }

    @ReactMethod
    fun navigateToProducts() {
        val activity = currentActivity
        activity?.runOnUiThread {
            val intent = Intent(activity, ProductsActivity::class.java)
            activity.startActivity(intent)
        }
    }
}
```

---

## iOS Native Modules

### Step 1: Create the Native Module (Swift)

**`ios/YourApp/Bridge/MyNativeModule.swift`:**

```swift
import Foundation
import React

@objc(MyNativeModule)
class MyNativeModule: NSObject, RCTBridgeModule {
    
    static func moduleName() -> String! {
        return "MyNativeModule"
    }
    
    static func requiresMainQueueSetup() -> Bool {
        return true
    }
    
    // Simple method call
    @objc
    func doSomething(_ data: String) {
        print("Received from React Native: \(data)")
        // Your native implementation
    }
    
    // Method with Promise
    @objc
    func getDataAsync(_ resolve: @escaping RCTPromiseResolveBlock,
                      rejecter reject: @escaping RCTPromiseRejectBlock) {
        // Your async operation
        DispatchQueue.global(qos: .background).async {
            let result = self.fetchDataFromNative()
            resolve(result)
        }
    }
    
    // Method with multiple parameters
    @objc
    func processData(_ userId: String,
                     amount: NSNumber,
                     isActive: Bool,
                     resolver resolve: @escaping RCTPromiseResolveBlock,
                     rejecter reject: @escaping RCTPromiseRejectBlock) {
        // Process data
        let result: [String: Any] = [
            "userId": userId,
            "processedAmount": amount.doubleValue * 1.1,
            "status": isActive
        ]
        resolve(result)
    }
    
    // Send event to React Native
    @objc
    func notifyReactNative(_ data: String) {
        let params: [String: Any] = [
            "message": data,
            "timestamp": Date().timeIntervalSince1970 * 1000
        ]
        sendEvent(withName: "NativeEvent", body: params)
    }
    
    private func fetchDataFromNative() -> String {
        // Your native logic
        return "Data from native"
    }
    
    // Required for events
    func supportedEvents() -> [String]! {
        return ["NativeEvent"]
    }
    
    private func sendEvent(withName name: String, body: Any?) {
        guard let bridge = bridge else { return }
        bridge.eventDispatcher().sendAppEvent(withName: name, body: body)
    }
}
```

### Step 2: Create Objective-C Bridge Header

**`ios/YourApp/Bridge/MyNativeModule.m`:**

```objc
#import <React/RCTBridgeModule.h>

@interface RCT_EXTERN_MODULE(MyNativeModule, NSObject)

RCT_EXTERN_METHOD(doSomething:(NSString *)data)
RCT_EXTERN_METHOD(getDataAsync:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
RCT_EXTERN_METHOD(processData:(NSString *)userId
                  amount:(NSNumber *)amount
                  isActive:(BOOL)isActive
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
RCT_EXTERN_METHOD(notifyReactNative:(NSString *)data)

@end
```

### Step 3: Update Bridging Header

**`ios/YourApp/YourApp-Bridging-Header.h`:**

```objc
#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>
```

### Example: Navigation Bridge (Real Implementation)

**`ios/YourApp/Bridge/NavigationBridge.swift`:**

```swift
import Foundation
import React
import UIKit

@objc(NavigationBridge)
class NavigationBridge: NSObject, RCTBridgeModule {
    
    static func moduleName() -> String! {
        return "NavigationBridge"
    }
    
    static func requiresMainQueueSetup() -> Bool {
        return true
    }
    
    @objc
    func navigateToPDP(_ productId: String) {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let delegate = windowScene.delegate as? SceneDelegate,
                  let navigationController = delegate.window?.rootViewController as? UINavigationController else {
                print("Error: Could not get navigation controller for PDP.")
                return
            }
            let pdpVC = PDPViewController(productId: productId)
            navigationController.pushViewController(pdpVC, animated: true)
        }
    }
    
    @objc
    func navigateToCart() {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let delegate = windowScene.delegate as? SceneDelegate,
                  let navigationController = delegate.window?.rootViewController as? UINavigationController else {
                print("Error: Could not get navigation controller for Cart.")
                return
            }
            let cartVC = CartViewController()
            navigationController.pushViewController(cartVC, animated: true)
        }
    }
    
    @objc
    func navigateToProducts() {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let delegate = windowScene.delegate as? SceneDelegate,
                  let navigationController = delegate.window?.rootViewController as? UINavigationController else {
                print("Error: Could not get navigation controller for Products.")
                return
            }
            navigationController.popToRootViewController(animated: true)
        }
    }
}
```

**`ios/YourApp/Bridge/NavigationBridge.m`:**

```objc
#import <React/RCTBridgeModule.h>

@interface RCT_EXTERN_MODULE(NavigationBridge, NSObject)

RCT_EXTERN_METHOD(navigateToPDP:(NSString *)productId)
RCT_EXTERN_METHOD(navigateToCart)
RCT_EXTERN_METHOD(navigateToProducts)

@end
```

---

## Calling Native from React Native

### Basic Method Call

```typescript
import { NativeModules, Platform } from 'react-native';

const { MyNativeModule } = NativeModules;

// Check if module exists (may be null on web)
if (Platform.OS !== 'web' && MyNativeModule) {
    MyNativeModule.doSomething('Hello from React Native');
}
```

### With Promise (Async/Await)

```typescript
import { NativeModules } from 'react-native';

const { MyNativeModule } = NativeModules;

async function fetchData() {
    try {
        const result = await MyNativeModule.getDataAsync();
        console.log('Result:', result);
    } catch (error) {
        console.error('Error:', error);
    }
}
```

### With Multiple Parameters

```typescript
const { MyNativeModule } = NativeModules;

async function processData() {
    try {
        const result = await MyNativeModule.processData(
            'user123',
            99.99,
            true
        );
        console.log('Processed:', result);
    } catch (error) {
        console.error('Error:', error);
    }
}
```

### Real Example: Navigation Bridge

```typescript
// From your existing codebase
import { NativeModules, Platform } from 'react-native';

const NavigationBridge = NativeModules.NavigationBridge;

// Navigate to PDP
if (Platform.OS !== 'web' && NavigationBridge) {
    NavigationBridge.navigateToPDP(productId);
}

// Navigate to Cart
if (Platform.OS !== 'web' && NavigationBridge) {
    NavigationBridge.navigateToCart();
}
```

---

## Sending Events from Native to React Native

### React Native Side

```typescript
import { NativeEventEmitter, NativeModules } from 'react-native';

const { MyNativeModule } = NativeModules;
const emitter = new NativeEventEmitter(MyNativeModule);

// Subscribe to events
useEffect(() => {
    const subscription = emitter.addListener('NativeEvent', (data) => {
        console.log('Received event:', data);
        // Handle the event
    });

    // Cleanup
    return () => {
        subscription.remove();
    };
}, []);
```

### Android Side

```kotlin
// Send event from native
private fun sendEvent(eventName: String, params: WritableMap?) {
    reactApplicationContext
        .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
        .emit(eventName, params)
}

// Usage
fun notifySomething() {
    val params = Arguments.createMap().apply {
        putString("message", "Hello from native")
        putInt("count", 42)
    }
    sendEvent("NativeEvent", params)
}
```

### iOS Side

```swift
// Send event from native
private func sendEvent(withName name: String, body: Any?) {
    guard let bridge = bridge else { return }
    bridge.eventDispatcher().sendAppEvent(withName: name, body: body)
}

// Usage
func notifySomething() {
    let params: [String: Any] = [
        "message": "Hello from native",
        "count": 42
    ]
    sendEvent(withName: "NativeEvent", body: params)
}
```

---

## Data Type Mapping

### JavaScript → Native

| JavaScript Type | Android Type | iOS Type |
|----------------|--------------|----------|
| `string` | `String` | `NSString` |
| `number` | `Double` / `Int` | `NSNumber` |
| `boolean` | `Boolean` | `BOOL` |
| `object` | `ReadableMap` | `NSDictionary` |
| `array` | `ReadableArray` | `NSArray` |
| `null` | `null` | `nil` |

### Native → JavaScript

| Native Type | JavaScript Type |
|-------------|----------------|
| `String` | `string` |
| `Int` / `Double` | `number` |
| `Boolean` | `boolean` |
| `WritableMap` | `object` |
| `WritableArray` | `array` |

### Complex Data Structures

**Android:**

```kotlin
// Create map
val params = Arguments.createMap().apply {
    putString("name", "John")
    putInt("age", 30)
    putBoolean("active", true)
    putArray("tags", Arguments.createArray().apply {
        pushString("tag1")
        pushString("tag2")
    })
}

// Create nested map
putMap("address", Arguments.createMap().apply {
    putString("street", "123 Main St")
    putString("city", "New York")
})
```

**iOS:**

```swift
// Create dictionary
let params: [String: Any] = [
    "name": "John",
    "age": 30,
    "active": true,
    "tags": ["tag1", "tag2"],
    "address": [
        "street": "123 Main St",
        "city": "New York"
    ]
]
```

**React Native:**

```typescript
// Receive complex data
const result = await MyNativeModule.getComplexData();
// result = {
//   name: "John",
//   age: 30,
//   active: true,
//   tags: ["tag1", "tag2"],
//   address: {
//     street: "123 Main St",
//     city: "New York"
//   }
// }
```

---

## Complete Examples

### Example 1: User Authentication Bridge

**Use Case**: Native app handles authentication, React Native needs to know auth status

**Android:**

```kotlin
class AuthBridgeModule(reactContext: ReactApplicationContext) :
    ReactContextBaseJavaModule(reactContext) {

    override fun getName() = "AuthBridge"

    @ReactMethod
    fun login(username: String, password: String, promise: Promise) {
        // Native authentication logic
        authenticateUser(username, password) { success, token ->
            if (success) {
                val result = Arguments.createMap().apply {
                    putString("token", token)
                    putBoolean("success", true)
                }
                promise.resolve(result)
            } else {
                promise.reject("AUTH_ERROR", "Invalid credentials")
            }
        }
    }

    @ReactMethod
    fun getCurrentUser(promise: Promise) {
        val user = getAuthenticatedUser()
        if (user != null) {
            val result = Arguments.createMap().apply {
                putString("id", user.id)
                putString("name", user.name)
                putString("email", user.email)
            }
            promise.resolve(result)
        } else {
            promise.reject("NO_USER", "No user logged in")
        }
    }

    // Send event when auth state changes
    fun notifyAuthStateChanged(isLoggedIn: Boolean, user: User?) {
        val params = Arguments.createMap().apply {
            putBoolean("isLoggedIn", isLoggedIn)
            if (user != null) {
                putMap("user", Arguments.createMap().apply {
                    putString("id", user.id)
                    putString("name", user.name)
                })
            }
        }
        sendEvent("AuthStateChanged", params)
    }
}
```

**React Native:**

```typescript
import { NativeModules, NativeEventEmitter } from 'react-native';

const { AuthBridge } = NativeModules;
const authEmitter = new NativeEventEmitter(AuthBridge);

// Login
async function login(username: string, password: string) {
    try {
        const result = await AuthBridge.login(username, password);
        console.log('Login successful:', result.token);
        return result;
    } catch (error) {
        console.error('Login failed:', error);
        throw error;
    }
}

// Listen for auth state changes
useEffect(() => {
    const subscription = authEmitter.addListener(
        'AuthStateChanged',
        (data) => {
            console.log('Auth state changed:', data);
            // Update your app state
        }
    );
    return () => subscription.remove();
}, []);
```

### Example 2: Device Information Bridge

**Use Case**: Get device-specific information from native

**Android:**

```kotlin
class DeviceInfoModule(reactContext: ReactApplicationContext) :
    ReactContextBaseJavaModule(reactContext) {

    override fun getName() = "DeviceInfo"

    @ReactMethod
    fun getDeviceInfo(promise: Promise) {
        val info = Arguments.createMap().apply {
            putString("model", android.os.Build.MODEL)
            putString("manufacturer", android.os.Build.MANUFACTURER)
            putString("osVersion", android.os.Build.VERSION.RELEASE)
            putInt("sdkVersion", android.os.Build.VERSION.SDK_INT)
            putString("deviceId", getDeviceId())
        }
        promise.resolve(info)
    }

    @ReactMethod
    fun getBatteryLevel(promise: Promise) {
        val batteryManager = reactContext.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        val level = batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        promise.resolve(level)
    }
}
```

**React Native:**

```typescript
const { DeviceInfo } = NativeModules;

async function getDeviceInfo() {
    const info = await DeviceInfo.getDeviceInfo();
    console.log('Device:', info.model);
    console.log('OS:', info.osVersion);
    return info;
}

async function getBatteryLevel() {
    const level = await DeviceInfo.getBatteryLevel();
    console.log('Battery:', level + '%');
    return level;
}
```

---

## Best Practices

### 1. Always Check for Module Existence

```typescript
const { MyModule } = NativeModules;

if (Platform.OS !== 'web' && MyModule) {
    // Safe to use
    MyModule.doSomething();
}
```

### 2. Handle Errors Gracefully

```typescript
try {
    const result = await MyModule.riskyOperation();
} catch (error) {
    console.error('Operation failed:', error);
    // Fallback behavior
}
```

### 3. Use TypeScript Types

```typescript
interface NativeModuleInterface {
    doSomething(data: string): void;
    getDataAsync(): Promise<string>;
    processData(
        userId: string,
        amount: number,
        isActive: boolean
    ): Promise<{ userId: string; processedAmount: number; status: boolean }>;
}

const MyModule = NativeModules.MyNativeModule as NativeModuleInterface;
```

### 4. Clean Up Event Listeners

```typescript
useEffect(() => {
    const subscription = emitter.addListener('Event', handler);
    return () => subscription.remove(); // Always cleanup
}, []);
```

### 5. Run Native Code on UI Thread (Android)

```kotlin
@ReactMethod
fun updateUI() {
    val activity = currentActivity
    activity?.runOnUiThread {
        // UI updates here
    }
}
```

### 6. Use Main Queue for UI (iOS)

```swift
@objc
func updateUI() {
    DispatchQueue.main.async {
        // UI updates here
    }
}
```

### 7. Avoid Blocking Operations

```kotlin
// ❌ Bad: Blocks JavaScript thread
@ReactMethod
fun blockingOperation() {
    Thread.sleep(5000) // Don't do this!
}

// ✅ Good: Use background thread
@ReactMethod
fun asyncOperation(promise: Promise) {
    Thread {
        val result = doLongRunningTask()
        promise.resolve(result)
    }.start()
}
```

---

## Troubleshooting

### Module Not Found

**Problem**: `NativeModules.MyModule` is `undefined`

**Solutions:**
1. Verify module is registered in `MainApplication.kt` (Android) or `AppDelegate.swift` (iOS)
2. Check module name matches exactly (case-sensitive)
3. Rebuild the native app
4. Check if module is available: `console.log(NativeModules)`

### Method Not Found

**Problem**: Method call fails or returns `undefined`

**Solutions:**
1. Verify `@ReactMethod` annotation (Android) or `@objc` (iOS)
2. Check method name matches exactly
3. Verify parameter types match expected types
4. Check console for error messages

### Events Not Received

**Problem**: Event listeners don't receive events

**Solutions:**
1. Verify `supportedEvents()` returns event name (iOS)
2. Check event name matches exactly
3. Ensure listener is added before event is sent
4. Verify `sendEvent` is called correctly

### Type Mismatch Errors

**Problem**: Data type errors when passing parameters

**Solutions:**
1. Check data type mapping table
2. Use correct wrapper types (e.g., `NSNumber` for numbers in iOS)
3. Verify complex objects are properly serialized
4. Check console for type error messages

### Thread Issues

**Problem**: UI updates don't work or app crashes

**Solutions:**
1. Always run UI updates on main thread
2. Use `runOnUiThread` (Android) or `DispatchQueue.main.async` (iOS)
3. Avoid blocking operations in `@ReactMethod`

---

## Related Documentation

- **[Android Integration](./ANDROID_INTEGRATION.md)** - Android setup guide
- **[iOS Integration](./IOS_INTEGRATION.md)** - iOS setup guide
- **[Native App Consumption](./NATIVE_APP_CONSUMPTION.md)** - Integration overview
- [React Native Native Modules](https://reactnative.dev/docs/native-modules-android) - Official Android docs
- [React Native Native Modules iOS](https://reactnative.dev/docs/native-modules-ios) - Official iOS docs

---

**Last Updated:** 2024
**Maintained By:** Development Team

