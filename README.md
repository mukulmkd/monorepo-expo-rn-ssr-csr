# Monorepo: Expo RN with Web SSR/CSR

A monorepo containing React Native modules built with Expo, designed to be embedded into native Android and iOS applications.

## 📋 Overview

This monorepo manages:

- **Apps** (`apps/*`) - Expo-based React Native modules
- **Packages** (`packages/*`) - Shared UI components, state management, and utilities
- **Verdaccio Registry** - Local npm registry for package distribution
- **Framework Generation Scripts** - Generate Android AARs and iOS SPM packages

Modules are distributed via a local Verdaccio npm registry and can be packaged as native frameworks (AARs for Android, SPM packages for iOS).

---

## 🚀 Quick Start

### Prerequisites

- **Node.js LTS** (>=20) - [Download](https://nodejs.org/)
- **npm** (comes with Node.js)

### First-Time Setup

```bash
# 1. Clone and install dependencies
git clone <repository-url>
cd monorepo-expo-rn-ssr-csr
npm install

# 2. Start Verdaccio (keep running in separate terminal)
npm run verdaccio:start

# 3. Configure npm scopes
npm config set @app:registry http://localhost:4873
npm config set @pkg:registry http://localhost:4873

# 4. Login to Verdaccio (first time only)
npm adduser --registry http://localhost:4873

# 5. Publish all packages
npm run publish:verdaccio
```

**✅ Setup Complete!** Your monorepo is ready for development.

---

## 📦 Workspace Structure

```
monorepo-expo-rn-ssr-csr/
├── apps/                    # React Native modules
│   ├── module-products/     # Products listing module
│   ├── module-cart/         # Shopping cart module
│   ├── module-pdp/          # Product detail page module
│   └── shell/               # Development shell app
├── packages/                # Shared packages
│   ├── core/                # API clients and domain logic
│   ├── state/               # Redux Toolkit store
│   ├── ui/                  # Shared UI primitives
│   ├── products-ui/         # Products UI components
│   ├── cart-ui/             # Cart UI components
│   ├── pdp-ui/              # PDP UI components
│   └── homepage-ui/         # Homepage UI components
├── tools/verdaccio/         # Verdaccio configuration
├── scripts/                 # Framework generation scripts
├── android-props/           # Centralized Android configuration
│   ├── local.properties     # Android SDK path
│   └── artifactory.properties  # Artifactory credentials
└── docs/                    # Documentation
```

---

## 🏗️ Apps

- **`module-products`** - Products listing module
- **`module-cart`** - Shopping cart module
- **`module-pdp`** - Product detail page module
- **`shell`** - Development shell app (for testing modules)

---

## 📦 Packages

- **`@pkg/core`** - API clients, hooks, and domain logic
- **`@pkg/state`** - Redux Toolkit store and slices
- **`@pkg/ui`** - Shared UI primitives (Header, Footer, Navigation)
- **`@pkg/products-ui`** - Products listing UI components
- **`@pkg/cart-ui`** - Cart UI components
- **`@pkg/pdp-ui`** - Product detail page UI components
- **`@pkg/homepage-ui`** - Homepage UI components

See [docs/PACKAGES.md](./docs/PACKAGES.md) for detailed package documentation.

---

## 🚀 Development

### Running Modules

```bash
# Run a module in Expo Go
cd apps/module-products
npm run start

# Or run the shell app
cd apps/shell
npm run start
```

### Updating Published Packages

When you make changes to modules and need to update them:

```bash
# 1. Ensure Verdaccio is running
npm run verdaccio:start

# 2. Update version in package.json if needed
# 3. Publish updated packages
npm run publish:verdaccio
```

---

## 📤 Publishing to Verdaccio

### Publish All Packages

```bash
npm run publish:verdaccio
```

This publishes all workspace packages to the local Verdaccio registry in dependency order.

### Publish Individual Package

```bash
cd apps/module-products
npm run publish:verdaccio
```

---

## 🏃 Available Scripts

### Verdaccio

- `npm run verdaccio:start` - Start Verdaccio registry
- `npm run verdaccio:reset` - Reset Verdaccio storage
- `npm run publish:verdaccio` - Publish all packages to Verdaccio

### Development

- `npm run build` - Build all packages
- `npm run typecheck` - Type check all packages
- `npm run lint` - Lint all packages
- `npm run dev` - Run shell app in development mode

### Framework Generation

See [NATIVE_INTEGRATION.md](./NATIVE_INTEGRATION.md) for complete framework generation and integration guide.

**Android AAR Generation:**
- `npm run framework:android:aar:host` - Generate React Native runtime host AAR
- `npm run framework:android:aar:products` - Generate products module AAR
- `npm run framework:android:aar:cart` - Generate cart module AAR
- `npm run framework:android:aar:pdp` - Generate PDP module AAR
- `npm run framework:android:aar:all` - Generate all module AARs at once

**Android AAR Publishing:**
- `npm run framework:android:aar:host:publish:local` - Publish host AAR to local Maven
- `npm run framework:android:aar:products:publish:local` - Publish products AAR to local Maven
- `npm run framework:android:aar:cart:publish:local` - Publish cart AAR to local Maven
- `npm run framework:android:aar:pdp:publish:local` - Publish PDP AAR to local Maven
- Similar commands for `:central` (Artifactory)

**iOS SPM Generation:**
- `npm run framework:ios:spm:runtime` - Generate React Native runtime SPM package
- `npm run framework:ios:spm:products` - Generate products module SPM package
- `npm run framework:ios:spm:cart` - Generate cart module SPM package
- `npm run framework:ios:spm:pdp` - Generate PDP module SPM package
- `npm run framework:ios:spm:all` - Generate all module SPM packages at once

---

## 🔧 Configuration

### Android Properties

All Android configuration is centralized in `android-props/`:

- **`android-props/local.properties`** - Android SDK location
  ```properties
  sdk.dir=/path/to/android/sdk
  ```

- **`android-props/artifactory.properties`** - Artifactory credentials (optional)
  - Copy from `android-props/artifactory.properties.example`
  - Used for publishing AARs to central Artifactory

### Verdaccio Configuration

Verdaccio runs locally on `http://localhost:4873` and stores packages in `.verdaccio/storage/`.

Configuration: `tools/verdaccio/config.yaml`

---

## 📚 Documentation

### Integration Guides

- **[NATIVE_INTEGRATION.md](./NATIVE_INTEGRATION.md)** - Complete guide for generating and integrating Android AARs and iOS SPM packages
- **[Android AAR Integration](./docs/ANDROID_AAR_INTEGRATION.md)** - Detailed Android AAR integration guide
- **[iOS SPM Integration](./docs/IOS_SPM_INTEGRATION.md)** - Detailed iOS SPM integration guide

### Reference Documentation

- **[Local Registry Guide](./docs/LOCAL_REGISTRY.md)** - Setting up and using Verdaccio
- **[Packages Documentation](./docs/PACKAGES.md)** - Package API reference

---

## 🚨 Quick Troubleshooting

| Issue | Quick Fix |
|-------|-----------|
| **"Verdaccio is not running"** | Run `npm run verdaccio:start` in a separate terminal |
| **"Module not found in Verdaccio"** | Run `npm run publish:verdaccio` to publish packages |
| **"Permission denied" on scripts** | Run `chmod +x scripts/*.sh` |

For detailed troubleshooting, see:
- [NATIVE_INTEGRATION.md](./NATIVE_INTEGRATION.md#troubleshooting)
- [Android AAR Integration Guide](./docs/ANDROID_AAR_INTEGRATION.md#troubleshooting)
- [iOS SPM Integration Guide](./docs/IOS_SPM_INTEGRATION.md#troubleshooting)

---

## 🎯 Use Cases

1. **Embedded Modules** - Modules run inside native Android/iOS apps via React Native bridge
2. **Standalone Development** - Each module can run independently in Expo Go for development
3. **Web SSR/CSR** - Modules support server-side rendering with Express (no Next.js)
4. **Native Framework Distribution** - Generate AARs (Android) and SPM packages (iOS) for distribution

---

## 🤝 Contributing

1. Make changes in the appropriate app or package
2. Test locally with Expo Go or the shell app
3. Publish to Verdaccio: `npm run publish:verdaccio`
4. Test integration in native apps (if applicable)
5. Update documentation if needed

---

## 📝 Notes

- All modules register themselves with `AppRegistry` for native integration
- Modules use Redux for state management (via `@pkg/state`)
- Shared UI components are in `@pkg/ui`
- Verdaccio runs locally on `http://localhost:4873`
- Native apps consume modules via npm packages or native frameworks (AARs/SPMs)
- **Framework generation** - See [NATIVE_INTEGRATION.md](./NATIVE_INTEGRATION.md) for complete guide

---

## 🔮 Future Architecture

This monorepo will be split into separate repositories:

- **Runtime Repository** - Contains React Native runtime AAR (`mkd-rn-host`) and SPM package (`MKDReactNativeRuntime`)
- **Module Repository** - Contains module AARs and SPM packages
- **This Monorepo** - Contains source code, Verdaccio, and generation scripts

The current structure supports this transition while maintaining a single source of truth for development.

**📖 See [3-Repository Architecture Guide](./docs/3_REPO_ARCHITECTURE.md) for complete step-by-step migration instructions.**
