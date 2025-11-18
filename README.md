# Monorepo: Expo RN with Web SSR/CSR

A monorepo containing React Native modules built with Expo, designed to be embedded into native Android and iOS applications. Modules are distributed via a local Verdaccio npm registry.

## 📋 Setup Order (For New Team Members)

**Follow this order when setting up for the first time:**

1. **✅ This Monorepo** (set up first) - Start Verdaccio and publish packages
2. **Native Android App** (set up second) - Depends on Verdaccio running
3. **Native iOS App** (set up third) - Depends on Verdaccio running

> **⚠️ Important**: The monorepo must be set up and Verdaccio must be running before setting up the native apps.

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

## 🚀 First-Time Setup (For New Team Members)

> **⚠️ IMPORTANT**: This monorepo must be set up **FIRST** before setting up the native Android or iOS apps. The native apps depend on Verdaccio running and packages being published.

### Prerequisites

- **Node.js LTS** (>=20) - [Download](https://nodejs.org/)
- **npm** (comes with Node.js)
- **Git** (for cloning the repository)

### Step-by-Step Setup

Follow these steps **in order**:

#### Step 1: Clone and Install Dependencies

```bash
# Clone the repository
git clone <repository-url>
cd monorepo-expo-rn-ssr-csr

# Install all workspace dependencies
npm install
```

**Expected output**: All packages in `apps/` and `packages/` will have their dependencies installed.

#### Step 2: Start Verdaccio Registry

```bash
# Start Verdaccio (keep this terminal open)
npm run verdaccio:start
```

**Expected output**: You should see:
```
warn --- http address - http://localhost:4873/ - verdaccio/6.0.5
```

**⚠️ Keep this terminal running** - Verdaccio must stay running for native apps to install packages.

#### Step 3: Login to Verdaccio (First Time Only)

Open a **new terminal** (keep Verdaccio running in the first one):

```bash
# Navigate to the monorepo directory
cd monorepo-expo-rn-ssr-csr

# Login to Verdaccio
npm adduser --registry http://localhost:4873
```

**When prompted:**
- **Username**: Enter any username (e.g., `developer`)
- **Password**: Enter any password (e.g., `password`)
- **Email**: Enter any email (e.g., `dev@example.com`)

**Expected output**: `Logged in as <username> on http://localhost:4873/`

#### Step 4: Configure npm Scopes

```bash
# Configure npm to use Verdaccio for @app and @pkg scopes
npm config set @app:registry http://localhost:4873
npm config set @pkg:registry http://localhost:4873
```

**Verify configuration:**
```bash
npm config get @app:registry
npm config get @pkg:registry
```

Both should return: `http://localhost:4873`

#### Step 5: Publish All Packages to Verdaccio

```bash
# Publish all workspace packages to Verdaccio
npm run verdaccio:publish-all
```

**Expected output**: You should see packages being published:
```
✅ Published @pkg/core@0.1.0
✅ Published @pkg/state@0.1.0
✅ Published @app/module-products@0.1.2
...
```

**⚠️ Important**: If you see errors about packages already existing, that's fine - it means they were already published.

#### Step 6: Verify Setup

```bash
# Check if packages are available in Verdaccio
npm view @app/module-products --registry http://localhost:4873
```

**Expected output**: Package metadata should be displayed.

**Or visit**: http://localhost:4873 in your browser to see the Verdaccio web UI.

### ✅ Setup Complete!

Your monorepo is now ready. You can now proceed to set up the native Android and iOS apps.

**Next Steps:**
1. **Keep Verdaccio running** (the terminal from Step 2)
2. Set up **Native Android App** (see its README)
3. Set up **Native iOS App** (see its README)

---

## 🚀 Quick Start (For Development)

Once setup is complete, you can use these commands for daily development:

### Development

```bash
# Run a module in Expo Go
cd apps/module-products
npm run start

# Or run the shell app
cd apps/shell
npm run start
```

### Updating Published Packages

When you make changes to modules and need to update them in native apps:

```bash
# 1. Make sure Verdaccio is running (Step 2 above)
# 2. Update version in package.json if needed
# 3. Publish updated packages
npm run verdaccio:publish-all

# 4. In native apps, update dependencies:
#    cd js && npm install @app/module-products@latest
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
- **[Performance Optimization](./docs/PERFORMANCE_OPTIMIZATION.md)** - OTA updates, bundle size, and performance optimization guide
- **[Native Module Bridge](./docs/NATIVE_MODULE_BRIDGE.md)** - React Native ↔ Native communication guide
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
