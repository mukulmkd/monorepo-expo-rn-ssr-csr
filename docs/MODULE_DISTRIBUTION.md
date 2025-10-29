# Distributing Expo Modules to Existing Native Apps

This guide explains how to build and distribute Expo-based React Native modules (like `module-products`) for integration into existing Android and iOS native applications.

## Table of Contents

1. [Overview](#overview)
2. [Distribution Options](#distribution-options)
3. [Step-by-Step Guide](#step-by-step-guide)
4. [Build Process](#build-process)
5. [Integration Guide](#integration-guide)
6. [Troubleshooting](#troubleshooting)

## Overview

Each module (`module-products`, `module-cart`, `module-pdp`) can be:

- Built as standalone React Native bundles
- Distributed to existing native Android/iOS apps
- Integrated using React Native's bridge system

## Distribution Options

### Option 1: Metro Bundles (Recommended)

- Build JS bundle + assets using Metro bundler
- Existing apps load bundle via React Native bridge
- Best for: Quick integration without native code changes

### Option 2: npm Package Distribution

- Package as npm package with peer dependencies
- Apps install via npm and import directly
- Best for: Reusable modules across multiple projects

### Option 3: EAS Build (Expo Application Services)

- Build native apps with Expo tooling
- Best for: Full Expo feature support

## Step-by-Step Guide

### Step 1: Create Module Export Component

Create `apps/module-products/ModuleExport.tsx`:

```typescript
import * as React from "react";
import { Provider } from "react-redux";
import { View, StyleSheet } from "react-native";
import { ProductsScreen } from "@pkg/products-ui";
import { configureStore, AppStore } from "@pkg/state";
import { Header, Footer, Navigation } from "@pkg/ui";

export type ModuleProductsProps = {
  store?: AppStore;
  onProductPress?: (productId: string) => void;
  hideHeader?: boolean;
  hideNavigation?: boolean;
  hideFooter?: boolean;
};

export function ModuleProducts({
  store,
  onProductPress,
  hideHeader = false,
  hideNavigation = false,
  hideFooter = false,
}: ModuleProductsProps) {
  const appStore = store || configureStore();

  return (
    <Provider store={appStore}>
      <View style={styles.container}>
        {!hideHeader && <Header />}
        {!hideNavigation && <Navigation />}
        <View style={styles.content}>
          <ProductsScreen onProductPress={onProductPress} />
        </View>
        {!hideFooter && <Footer />}
      </View>
    </Provider>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  content: { flex: 1 },
});

export default ModuleProducts;
```

### Step 2: Update Entry Point

Update `apps/module-products/index.js`:

```javascript
import { ModuleProducts } from "./ModuleExport";

// Default export for Expo app
export { ModuleProducts };
export default ModuleProducts;
```

### Step 3: Add Build Scripts

Add to `apps/module-products/package.json`:

```json
{
  "scripts": {
    "build:bundle:ios": "npx react-native bundle --platform ios --dev false --entry-file ./index.js --bundle-output ./dist/ios/module-products.bundle --assets-dest ./dist/ios/assets",
    "build:bundle:android": "npx react-native bundle --platform android --dev false --entry-file ./index.js --bundle-output ./dist/android/module-products.bundle --assets-dest ./dist/android/assets",
    "build:bundles": "npm run build:bundle:ios && npm run build:bundle:android",
    "prebuild:ios": "npx expo prebuild --platform ios --clean",
    "prebuild:android": "npx expo prebuild --platform android --clean"
  }
}
```

### Step 4: Build Bundles

```bash
cd apps/module-products
npm run build:bundles
```

Output will be in:

- `dist/ios/module-products.bundle` + `dist/ios/assets/`
- `dist/android/module-products.bundle` + `dist/android/assets/`

## Build Process

### Using Metro Bundler

1. **Build iOS Bundle:**

```bash
npx react-native bundle \
  --platform ios \
  --dev false \
  --entry-file index.js \
  --bundle-output dist/ios/module-products.bundle \
  --assets-dest dist/ios/assets \
  --reset-cache
```

2. **Build Android Bundle:**

```bash
npx react-native bundle \
  --platform android \
  --dev false \
  --entry-file index.js \
  --bundle-output dist/android/module-products.bundle \
  --assets-dest dist/android/assets \
  --reset-cache
```

### Using Expo Prebuild (Optional)

If you need native projects for testing:

```bash
# Generate iOS project
npx expo prebuild --platform ios --clean

# Generate Android project
npx expo prebuild --platform android --clean

# Build bundles after prebuild
npm run build:bundles
```

## Integration Guide

### iOS Integration

See `docs/IOS_INTEGRATION.md` for detailed iOS integration steps.

### Android Integration

See `docs/ANDROID_INTEGRATION.md` for detailed Android integration steps.

## Dependencies & Requirements

**Existing apps must have:**

- React Native >= 0.81.5
- React >= 19.1.0
- React Redux >= 9.2.0
- @reduxjs/toolkit >= 2.9.2
- Expo SDK (compatible version)

**Module requires:**

- All packages from `@pkg/*` (core, state, ui, products-ui, etc.)

## Troubleshooting

### Bundle Not Loading

- Check bundle path in native code
- Verify assets are included
- Ensure React Native version compatibility

### Dependency Conflicts

- Use `peerDependencies` in package.json
- Ensure existing apps have required dependencies
- Check for version mismatches

### Assets Not Showing

- Verify assets folder is copied to app bundle
- Check asset paths in Metro bundle output
- Ensure native app includes asset files

## Versioning

Recommended bundle naming:

- `module-products-v1.0.0.bundle`
- Include version in file/directory name for easy rollback

## Next Steps

After building bundles:

1. Copy bundles + assets to native app projects
2. Follow integration guides for iOS/Android
3. Test in development environment
4. Deploy to staging/production
