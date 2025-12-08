# ModulePDPFramework

Android AAR framework for ModulePDP React Native module.

## Overview

This framework contains:
- Pre-bundled JavaScript code (module-pdp.bundle)
- Kotlin wrapper API for easy integration
- No Verdaccio or npm required at runtime

## Prerequisites

- **mkd-rn-host SDK must be added to the consuming app first** (provides React Native runtime)
- Android minSdkVersion: 23
- Android targetSdkVersion: 34
- Kotlin support

## Usage

### 1. Add mkd-rn-host SDK First (Required)

**Important:** The mkd-rn-host SDK must be added before this framework.

1. Publish mkd-rn-host to local Maven:
   ```bash
   npm run framework:android:aar:host:publish:local
   ```

2. Add to your app's `build.gradle`:
   ```gradle
   dependencies {
       implementation 'com.mkdcorp:mkd-rn-host-sdk:1.0.0'
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

**Note:** This framework automatically depends on React Native via mkd-rn-host SDK, which resolves dependencies from Maven Central.

### 2. Add This AAR

**Option A: Local AAR file**

```gradle
dependencies {
    implementation files('libs/mkd-rn-module-pdp-release.aar')
}
```

**Option B: Maven Local (if published)**

```gradle
repositories {
    mavenLocal()
}

dependencies {
    implementation 'com.yourorg.pdp:ModulePDPFramework:1.0.0'
}
```

### 3. Use in Code

```kotlin
import com.yourorg.pdp.ModulePDPFramework

class ProductsActivity : AppCompatActivity() {
    private lateinit var reactRootView: ReactRootView
    private val reactInstanceManager get() =
        (application as ReactApplication).reactNativeHost.reactInstanceManager
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        val framework = ModulePDPFramework.getInstance()
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
val framework = ModulePDPFramework.getInstance()
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

- `getInstance(): ModulePDPFramework` - Get singleton instance
- `getBundlePath(context: Context): String?` - Returns bundle file path
- `getModuleName(): String` - Returns registered module name
- `createView(context: Context, reactInstanceManager: ReactInstanceManager, initialProperties: Bundle?): ReactRootView?` - Creates React Native view

## Bundle

The JavaScript bundle is embedded in:
`src/main/assets/module-pdp.bundle`

This bundle was created from the latest version published to Verdaccio.

## Version

Generated from: @app/module-pdp
Source: Verdaccio registry
