# Distributing Expo Modules to Standalone Native Apps

This document explains how the Expo-based modules in this repository (`module-products`, `module-cart`, `module-pdp`) are built and published so that **separate** native Android and iOS projects can consume them via Verdaccio.

Native apps now live outside this monorepo. This repo only owns the shared JS/TS modules plus the Verdaccio tooling.

---

## Overview

1. Develop features inside the Expo modules located under `apps/`
2. Publish modules to the local Verdaccio registry (`docs/LOCAL_REGISTRY.md`)
3. In each native app repository, install the published packages and run Metro locally to create platform bundles

---

## Distribution Options

| Option | Description | When to use |
| --- | --- | --- |
| **Verdaccio npm packages (recommended)** | Publish modules as npm packages (`@app/*`, `@pkg/*`) and install them in any native project. Bundles are created inside each native repo. | Daily development, multi-app sharing |
| Metro bundle export | Build a standalone JS bundle directly from the module repo (`dist/android`, `dist/ios`) and drop it into a native project. | Offline distribution, one-off integrations |

The rest of this doc focuses on the Verdaccio workflow.

---

## Publishing Modules (from this monorepo)

1. **Start Verdaccio**
   ```bash
   npm run verdaccio:start
   ```

2. **Log in / map scopes**
   Follow the steps in `docs/LOCAL_REGISTRY.md` to authenticate and map the `@app` and `@pkg` scopes.

3. **Publish every package**
   ```bash
   npm run verdaccio:publish-all
   ```
   The helper verifies existing versions and skips re-publishing duplicates.

4. **Version bumping**
   - Increment the `version` field inside each package when behaviour changes
   - Commit the change before publishing to keep versioning traceable

---

## Consuming Modules (outside this repo)

See `docs/NATIVE_APP_CONSUMPTION.md` for detailed Android/iOS setup. At a high level:

1. Configure `.npmrc` inside the native project to point `@app`/`@pkg` at Verdaccio
2. `npm install @app/module-products` (and other packages)
3. Create a Metro entry point that registers the component you want to render
4. Run Metro bundling inside the native repo to produce platform-specific bundles (`react-native bundle ...`)
5. Load the generated bundle via `ReactInstanceManager` / `RCTBridge` in the native codebase

---

## Package Responsibilities

Each published module exposes a single entry component that wraps UI/state wiring:

```typescript
// apps/module-products/ModuleExport.tsx
export function ModuleProducts(props: ModuleProductsProps) {
  // Configure redux store, navigation shell, etc.
}
export default ModuleProducts;

// apps/module-products/index.js
export { default } from "./ModuleExport";
```

Keep the entry file minimal so consumers only have to `import ModuleProducts from "@app/module-products"`.

---

## Metro Bundling Cheatsheet (run inside consumer projects)

```bash
npx react-native bundle \
  --platform android \
  --entry-file index.js \
  --bundle-output android/app/src/main/assets/index.android.bundle \
  --assets-dest android/app/src/main/res \
  --dev false

npx react-native bundle \
  --platform ios \
  --entry-file index.js \
  --bundle-output ios/main.jsbundle \
  --assets-dest ios \
  --dev false
```

Your entry file typically looks like:

```javascript
import { AppRegistry } from "react-native";
import ModuleProducts from "@app/module-products";

AppRegistry.registerComponent("ModuleProducts", () => ModuleProducts);
```

---

## Dependency Expectations

Consumers must align major versions with the published modules:

- `react` 19.1+
- `react-native` 0.81+
- `react-redux` 9.2+
- `@reduxjs/toolkit` 2.9+
- Expo modules compiled for SDK 54

Treat the module packages’ `peerDependencies` as requirements in each native project.

---

## Troubleshooting

| Issue | Checklist |
| --- | --- |
| Metro cannot resolve `@pkg/*` | Ensure `.npmrc` for the native project points the scopes to Verdaccio and run `npm install` again |
| Native crash looking for Hermes libs | Use JSC (`hermesEnabled=false`) or include Hermes binaries in the native project. See `docs/NATIVE_APP_CONSUMPTION.md` for template configs |
| Assets missing | Copy `--assets-dest` output into the native resource folders each time you re-bundle |

---

## Related Docs

- **[LOCAL_REGISTRY.md](./LOCAL_REGISTRY.md)** – Starting Verdaccio and publishing packages
- **[NATIVE_APP_CONSUMPTION.md](./NATIVE_APP_CONSUMPTION.md)** – Android/iOS integration guides for external repos
- **[PACKAGES.md](./PACKAGES.md)** – Complete package API documentation
