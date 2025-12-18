# ModuleCartFramework

Android AAR framework for ModuleCart React Native module.

## Overview

This framework contains:
- Pre-bundled JavaScript code (module-cart.bundle)
- Kotlin wrapper API for easy integration
- No Verdaccio or npm required at runtime

## Prerequisites

- **vsco-rn-host SDK must be added to the consuming app first** (provides React Native runtime)
- Android minSdkVersion: 23
- Android targetSdkVersion: 34
- Kotlin support

## Usage

### 1. Add vsco-rn-host SDK First (Required)

**Important:** The vsco-rn-host SDK must be added before this framework.

1. Publish vsco-rn-host to local Maven:
   ```bash
   npm run framework:android:aar:host:publish:local
   ```

2. Add to your app's `build.gradle`:
   ```gradle
   dependencies {
       implementation 'com.vscorp:vsco-rn-host-sdk:1.0.0'
   }
   ```

2. Add to your app's `build.gradle`:
   ```gradle
   repositories {
       flatDir {
           dirs 'libs'
       }
   }
   
   dependencies {
       implementation(name: 'react-android-0.81.5-release', ext: 'aar')
       implementation(name: 'hermes-android-0.81.5-release', ext: 'aar')
   }
   ```

**Note:** This framework automatically depends on React Native via vsco-rn-host SDK, which resolves dependencies from Maven Central.

### 2. Add This AAR

**Option A: Local AAR file**

```gradle
dependencies {
    implementation files('libs/vsco-rn-module-cart-release.aar')
}
```

**Option B: Maven Local (if published)**

```gradle
repositories {
    mavenLocal()
}

dependencies {
    implementation 'com.vscorp.cart:ModuleCartFramework:1.0.0'
}
```

### 3. Use in Code

```kotlin
import com.vscorp.cart.ModuleCartFramework

class ProductsActivity : AppCompatActivity() {
    private lateinit var reactRootView: ReactRootView
    private val reactInstanceManager get() =
        (application as ReactApplication).reactNativeHost.reactInstanceManager
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        val framework = ModuleCartFramework.getInstance()
        val bundlePath = framework.getBundlePath(this)
        val moduleName = framework.getModuleName()
        
        if (bundlePath != null) {
            reactRootView = ReactRootView(this)
            reactRootView.startReactApplication(reactInstanceManager, moduleName, null)
            setContentView(reactRootView)
        } else {
            // Handle error: bundle not found
            Log.e("ProductsActivity", "Bundle not found")
        }
    }
}
```

**Or use the convenience method:**

```kotlin
val framework = ModuleCartFramework.getInstance()
val rootView = framework.createView(
    context = this,
    reactInstanceManager = reactInstanceManager,
    initialProperties = null
)

if (rootView != null) {
    setContentView(rootView)
}
```

## API

- `getInstance(): ModuleCartFramework` - Get singleton instance
- `getBundlePath(context: Context): String?` - Returns bundle file path
- `getModuleName(): String` - Returns registered module name
- `createView(context: Context, reactInstanceManager: ReactInstanceManager, initialProperties: Bundle?): ReactRootView?` - Creates React Native view

## Bundle

The JavaScript bundle is embedded in:
`src/main/assets/module-cart.bundle`

This bundle was created from the latest version published to Verdaccio.

## Version

Generated from: @app/module-cart
Source: Verdaccio registry
