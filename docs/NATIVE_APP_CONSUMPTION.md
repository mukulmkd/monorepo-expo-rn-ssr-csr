# Consuming Verdaccio Modules in Standalone Native Apps

The native Android and iOS apps are maintained in **separate repositories**. Use this guide to wire those projects to the local Verdaccio registry and bundle the React Native modules published from this monorepo.

---

## 1. Shared Prerequisites

- Verdaccio is running locally (`npm run verdaccio:start` inside the module repo)
- Modules have been published (`npm run publish:verdaccio`)
- Node.js ≥20 installed on the native project machine
- Metro CLI available (via project `devDependencies`)
- Access to the local Verdaccio credentials (`npm login --registry http://localhost:4873`)

### Configure npm scopes (per project)

Create `.npmrc` in the native project root:

```ini
@pkg:registry=http://localhost:4873
@app:registry=http://localhost:4873
```

Then install the packages you need:

```bash
npm install @app/module-products @app/module-cart @app/module-pdp
```

> Tip: keep the package versions in sync with the ones published from the module repo. Run `npm view @app/module-products --registry http://localhost:4873 version` if you need to inspect Verdaccio versions.

---

## 2. Android Project Template

### Directory Layout

```
your-native-android-app/
  android/                     # Gradle project
  js/                          # React Native entry point & Metro config
    index.js
    metro.config.js
    package.json
    .npmrc
```

### `js/package.json`

```json
{
  "name": "native-android-js",
  "private": true,
  "dependencies": {
    "@app/module-products": "^0.1.0",
    "react": "19.1.0",
    "react-native": "0.81.5"
  },
  "devDependencies": {
    "@react-native-community/cli": "^14.1.0",
    "@react-native-community/cli-platform-android": "^14.1.0"
  },
  "scripts": {
    "bundle:products": "react-native bundle --config metro.config.js --entry-file index.js --bundle-output ../android/app/src/main/assets/index.android.bundle --assets-dest ../android/app/src/main/res --platform android --dev false"
  }
}
```

### `js/index.js`

```javascript
import { AppRegistry } from "react-native";
import ModuleProducts from "@app/module-products";

AppRegistry.registerComponent("ModuleProducts", () => ModuleProducts);
```

### `js/metro.config.js`

```javascript
const path = require("path");
const { getDefaultConfig, mergeConfig } = require("@react-native/metro-config");

const projectRoot = __dirname;
const nodeModules = path.resolve(projectRoot, "node_modules");

const defaultConfig = getDefaultConfig(projectRoot);

module.exports = mergeConfig(defaultConfig, {
  resolver: {
    nodeModulesPaths: [nodeModules],
  },
  watchFolders: [nodeModules],
});
```

> Adjust `extraNodeModules` if you want to alias packages.

### Android `build.gradle` Snippets

In `android/app/build.gradle`:

```gradle
android {
    packagingOptions {
        jniLibs {
            useLegacyPackaging = true // keeps JSC .so files accessible
        }
    }
}

dependencies {
    implementation("com.facebook.react:react-android:0.81.5") {
        exclude group: "com.facebook.react", module: "hermes-android"
    }
    implementation "org.webkit:android-jsc:+"
}
```

In your `Application` class:

```kotlin
class MainApplication : Application(), ReactApplication {
    override val reactNativeHost: ReactNativeHost = object : DefaultReactNativeHost(this) {
        override fun getPackages(): List<ReactPackage> = listOf(MainReactPackage())
        override fun getUseDeveloperSupport() = false
        override val isHermesEnabled get() = false
        override fun getBundleAssetName() = "index.android.bundle"
    }

    override fun onCreate() {
        super.onCreate()
        System.setProperty("react_native_hermes_enabled", "false")
        SoLoader.init(this, false)
    }
}
```

In the Activity that hosts the React view (pure Kotlin example):

```kotlin
class ProductsActivity : AppCompatActivity(), DefaultHardwareBackBtnHandler {
    private var reactRootView: ReactRootView? = null
    private val reactInstanceManager get() = (application as ReactApplication).reactNativeHost.reactInstanceManager

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        reactRootView = ReactRootView(this).also {
            it.startReactApplication(reactInstanceManager, "ModuleProducts", null)
            setContentView(it)
        }
    }

    override fun onResume() {
        super.onResume()
        reactInstanceManager.onHostResume(this, this)
    }

    override fun onPause() {
        reactInstanceManager.onHostPause(this)
        super.onPause()
    }

    override fun onDestroy() {
        reactRootView?.unmountReactApplication()
        reactRootView = null
        super.onDestroy()
    }

    override fun onBackPressed() {
        reactInstanceManager.onBackPressed()
    }

    override fun invokeDefaultOnBackPressed() {
        super.onBackPressed()
    }
}
```

### Build Flow

1. `cd js && npm install`
2. `npm run bundle:products`
3. Build/run the Android app from Android Studio or Gradle (`./gradlew assembleDebug`)
4. Repeat bundling whenever the Verdaccio packages change

---

## 3. iOS Project Template

### Directory Layout

```
your-native-ios-app/
  ios/
  js/
    index.js
    metro.config.js
    package.json
    .npmrc
```

Reuse the same `js/` configuration as Android (Metro + entry point). Add the iOS bundle script:

```json
"scripts": {
  "bundle:ios:products": "react-native bundle --config metro.config.js --entry-file index.js --bundle-output ../ios/ModuleProducts/main.jsbundle --assets-dest ../ios/ModuleProducts --platform ios --dev false"
}
```

### CocoaPods

In `ios/Podfile`:

```ruby
require_relative '../node_modules/react-native/scripts/autolink-ios'

platform :ios, '14.0'

target 'YourApp' do
  config = use_native_modules!

  use_react_native!(
    :path => '../js/node_modules/react-native',
    :hermes_enabled => false,
    :fabric_enabled => false
  )

  pod 'yoga', :modular_headers => true
end
```

Run `cd ios && pod install` after installing node modules.

### Objective-C / Swift Bridge Example

```objc
#import <React/RCTBridge.h>
#import <React/RCTRootView.h>

@interface ProductsViewController ()
@property(nonatomic, strong) RCTBridge *bridge;
@end

@implementation ProductsViewController

- (void)viewDidLoad {
  [super viewDidLoad];

  NSURL *bundleURL = [[NSBundle mainBundle] URLForResource:@"main" withExtension:@"jsbundle" subdirectory:@"ModuleProducts"];

  self.bridge = [[RCTBridge alloc] initWithBundleURL:bundleURL moduleProvider:nil launchOptions:nil];
  RCTRootView *rootView = [[RCTRootView alloc] initWithBridge:self.bridge moduleName:@"ModuleProducts" initialProperties:nil];

  self.view = rootView;
}

- (void)dealloc {
  [self.bridge invalidate];
}

@end
```

### Build Flow

1. `cd js && npm install`
2. `npm run bundle:ios:products`
3. `cd ios && pod install`
4. Open the Xcode workspace and build/run
5. Re-run the bundling script whenever the Verdaccio packages change

---

## 4. Updating Modules

When a new version of a module is published:

1. Bump the dependency in each native project (`npm install @app/module-products@latest`)
2. Re-run the bundling scripts for each platform
3. Rebuild the native apps

For repeatable upgrades, consider scripting the steps above in the native repositories (e.g. `npm run sync:verdaccio`).

---

## 5. Troubleshooting

| Symptom | Suggested Fix |
| --- | --- |
| `Unable to load Hermes` or missing `libreact_*` | Ensure Hermes is disabled (see Android/iOS configs) or include Hermes native libs |
| Metro cannot resolve packages | Verify `.npmrc` points to Verdaccio and rerun `npm install` |
| Native app still shows an older version | Bundles may be stale. Delete generated assets and rerun bundle scripts |
| Autolinking errors | Disable autolinking (`enableAutolinking: false`) and include packages manually if necessary |

---

## 6. Reference Scripts

- `npm run verdaccio:start` – start local registry (module repo)
- `npm run publish:verdaccio` – publish all workspace packages (module repo)
- `npm run bundle:products` – example Android bundle script (native repo)
- `npm run bundle:ios:products` – example iOS bundle script (native repo)

Keep a copy of this guide in each native repository (or add a link) so engineers know how to refresh the React Native modules.

## Related Documentation

- **[LOCAL_REGISTRY.md](./LOCAL_REGISTRY.md)** – Setting up Verdaccio
- **[MODULE_DISTRIBUTION.md](./MODULE_DISTRIBUTION.md)** – How modules are published
- **[PACKAGES.md](./PACKAGES.md)** – Package API documentation
- **[ANDROID_INTEGRATION.md](./ANDROID_INTEGRATION.md)** – Android-specific integration overview
- **[IOS_INTEGRATION.md](./IOS_INTEGRATION.md)** – iOS-specific integration overview


