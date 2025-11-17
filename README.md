# Monorepo: Expo RN with Web SSR/CSR

A monorepo containing React Native modules built with Expo, designed to be embedded into native Android and iOS applications. Modules are distributed via a local Verdaccio npm registry.

## 🏗️ Architecture

This monorepo uses **npm workspaces** to manage:
- **Apps** (`apps/*`) - Expo-based React Native modules that can be embedded in native apps
- **Packages** (`packages/*`) - Shared UI components, state management, and utilities

### Apps

- **`module-products`** - Products listing module
- **`module-cart`** - Shopping cart module  
- **`module-pdp`** - Product detail page module
- **`shell`** - Development shell app (for testing modules)

### Packages

- **`@pkg/core`** - API clients, hooks, and domain logic
- **`@pkg/state`** - Redux Toolkit store and slices
- **`@pkg/ui`** - Shared UI primitives (Header, Footer, Navigation)
- **`@pkg/products-ui`** - Products listing UI components
- **`@pkg/cart-ui`** - Cart UI components
- **`@pkg/pdp-ui`** - Product detail page UI components
- **`@pkg/homepage-ui`** - Homepage UI components

See [docs/PACKAGES.md](./docs/PACKAGES.md) for detailed package documentation.

## 🚀 Quick Start

### Prerequisites

- Node.js LTS (>=20)
- npm workspaces support

### Setup

```bash
# Install all dependencies
npm install

# Start Verdaccio registry (in one terminal)
npm run verdaccio:start

# Login to Verdaccio (first time only)
npm adduser --registry http://localhost:4873

# Publish all packages to Verdaccio
npm run verdaccio:publish-all
```

### Development

```bash
# Run a module in Expo Go
cd apps/module-products
npm run start

# Or run the shell app
cd apps/shell
npm run start
```

## 📦 Distribution

Modules are published to a local Verdaccio registry and consumed by standalone native Android/iOS apps.

### Publishing Modules

```bash
# Publish all packages at once
npm run verdaccio:publish-all

# Or publish individual packages
cd apps/module-products
npm run publish:verdaccio
```

### Consuming in Native Apps

1. Configure `.npmrc` in your native project to point to Verdaccio
2. Install packages: `npm install @app/module-products`
3. Bundle with Metro: `npm run bundle:products`
4. Load the bundle in your native app

See [docs/LOCAL_REGISTRY.md](./docs/LOCAL_REGISTRY.md) for detailed setup instructions.

## 📚 Documentation

- **[Local Registry Guide](./docs/LOCAL_REGISTRY.md)** - Setting up and using Verdaccio
- **[Module Distribution](./docs/MODULE_DISTRIBUTION.md)** - How modules are built and distributed
- **[Native App Consumption](./docs/NATIVE_APP_CONSUMPTION.md)** - Integrating modules into native apps
- **[Packages Documentation](./docs/PACKAGES.md)** - Detailed package API reference
- **[Android Integration](./docs/ANDROID_INTEGRATION.md)** - Android-specific integration guide
- **[iOS Integration](./docs/IOS_INTEGRATION.md)** - iOS-specific integration guide
- **[Build Checklist](./docs/BUILD_CHECKLIST.md)** - Quick reference for module distribution

## 🏃 Available Scripts

### Root Level

- `npm install` - Install all workspace dependencies
- `npm run verdaccio:start` - Start Verdaccio registry
- `npm run verdaccio:publish-all` - Publish all packages to Verdaccio
- `npm run build` - Build all packages (if applicable)

### Module Level

Each module (`apps/module-*`) has:
- `npm run start` - Start Expo development server
- `npm run publish:verdaccio` - Publish this module to Verdaccio
- `npm run build` - Build for production (if applicable)

## 🔧 Workspace Structure

```
monorepo-expo-rn-ssr-csr/
├── apps/
│   ├── module-products/    # Products listing module
│   ├── module-cart/         # Cart module
│   ├── module-pdp/          # Product detail module
│   └── shell/               # Development shell
├── packages/
│   ├── core/                # Core utilities and API
│   ├── state/               # Redux store
│   ├── ui/                  # Shared UI primitives
│   ├── products-ui/         # Products UI components
│   ├── cart-ui/             # Cart UI components
│   ├── pdp-ui/              # PDP UI components
│   └── homepage-ui/         # Homepage UI components
├── docs/                    # Documentation
├── tools/
│   └── verdaccio/           # Verdaccio configuration
└── package.json             # Workspace root
```

## 🎯 Use Cases

1. **Embedded Modules** - Modules run inside native Android/iOS apps via React Native bridge
2. **Standalone Development** - Each module can run independently in Expo Go for development
3. **Web SSR/CSR** - Modules support server-side rendering with Express (no Next.js)

## 🤝 Contributing

1. Make changes in the appropriate app or package
2. Test locally with Expo Go or the shell app
3. Publish to Verdaccio: `npm run verdaccio:publish-all`
4. Test integration in native apps
5. Update documentation if needed

## 📝 Notes

- All modules register themselves with `AppRegistry` for native integration
- Modules use Redux for state management (via `@pkg/state`)
- Shared UI components are in `@pkg/ui`
- Verdaccio runs locally on `http://localhost:4873`
- Native apps consume modules via npm packages, not direct code inclusion
