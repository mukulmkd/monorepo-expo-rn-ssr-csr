# Android Integration Guide

This guide explains how to integrate React Native bundles (like `module-products`) into existing Android applications.

## Prerequisites

- Existing Android app with React Native installed
- React Native version >= 0.81.5
- Android Studio installed

## Step 1: Add Bundle to Project

1. Copy `module-products.bundle` to assets:

   ```
   android/app/src/main/assets/
   └── module-products.bundle
   ```

2. Copy assets folder:
   ```
   android/app/src/main/assets/
   └── assets/
       ├── images/
       └── fonts/
   ```

## Step 2: Create React Native Activity

Create `ProductsActivity.kt`:

```kotlin
package com.yourapp.products

import android.os.Bundle
import com.facebook.react.ReactActivity
import com.facebook.react.ReactActivityDelegate
import com.facebook.react.defaults.DefaultNewArchitectureEntryPoint.fabricEnabled
import com.facebook.react.defaults.DefaultReactActivityDelegate

class ProductsActivity : ReactActivity() {

  override fun getMainComponentName(): String {
    return "ModuleProducts"
  }

  override fun createReactActivityDelegate(): ReactActivityDelegate {
    return object : DefaultReactActivityDelegate(
      this,
      mainComponentName,
      fabricEnabled
    ) {
      override fun getLaunchOptions(): Bundle? {
        val initialProperties = Bundle()
        // Add any initial props here
        // initialProperties.putString("someKey", "someValue")
        return initialProperties
      }
    }
  }
}
```

## Step 3: Register Activity in AndroidManifest.xml

Add to `android/app/src/main/AndroidManifest.xml`:

```xml
<activity
  android:name=".products.ProductsActivity"
  android:label="Products"
  android:theme="@style/AppTheme"
  android:configChanges="keyboard|keyboardHidden|orientation|screenSize|uiMode"
  android:windowSoftInputMode="adjustResize" />
```

## Step 4: Create Native Module Bridge (Optional)

If you need to handle events from React Native:

Create `ProductsBridge.kt`:

```kotlin
package com.yourapp.products

import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.bridge.Promise
import android.os.Handler
import android.os.Looper

class ProductsBridge(reactContext: ReactApplicationContext) :
  ReactContextBaseJavaModule(reactContext) {

  override fun getName(): String {
    return "ProductsBridge"
  }

  @ReactMethod
  fun handleProductPress(productId: String) {
    // Handle product press event
    // Navigate or perform action in native app
    // Use Handler to run on main thread if needed
    Handler(Looper.getMainLooper()).post {
      // Your native code here
    }
  }
}
```

Create `ProductsPackage.kt`:

```kotlin
package com.yourapp.products

import com.facebook.react.ReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.uimanager.ViewManager

class ProductsPackage : ReactPackage {
  override fun createNativeModules(reactContext: ReactApplicationContext): List<NativeModule> {
    return listOf(ProductsBridge(reactContext))
  }

  override fun createViewManagers(reactContext: ReactApplicationContext): List<ViewManager<*, *>> {
    return emptyList()
  }
}
```

Register in `MainApplication.kt`:

```kotlin
override fun getPackages(): List<ReactPackage> {
  return listOf(
    MainReactPackage(),
    ProductsPackage() // Add your package
  )
}
```

## Step 5: Navigate to Products Activity

In your existing Android app:

```kotlin
// Start products activity
val intent = Intent(this, ProductsActivity::class.java)
startActivity(intent)
```

## Step 6: Load Bundle from Assets

If loading bundle from assets, ensure React Native is configured:

In `MainApplication.kt`:

```kotlin
override fun onCreate() {
  super.onCreate()

  // Your existing React Native initialization
  SoLoader.init(this, false)

  // Bundle will be loaded from assets automatically
  // when ProductsActivity starts
}
```

## Testing

1. Build and run Android app
2. Navigate to ProductsActivity
3. Verify bundle loads correctly
4. Test all functionality

## Troubleshooting

### Bundle Not Found

- Check bundle is in `assets/` folder
- Verify bundle name matches exactly (case-sensitive)
- Ensure assets are included in APK build

### Module Not Registered

- Check module name matches in Activity and bundle
- Verify `AppRegistry.registerComponent` is called in bundle

### Assets Missing

- Verify assets folder is in `assets/` directory
- Check asset paths in React Native code
- Ensure assets are included in APK

## Dependencies

Update `build.gradle` if needed:

```gradle
dependencies {
  implementation "com.facebook.react:react-native:+"
  // Add other React Native dependencies
}
```

Ensure `settings.gradle` includes React Native:

```gradle
include ':app'
include ':react-native-*'
// Your React Native modules
```
