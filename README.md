# Monorepo: Expo RN with Web CSR/SSR (Express)

This monorepo uses npm workspaces. It contains three Expo apps (shell, module-products, module-cart, module-pdp) and shared packages for UI, core utilities, and state.

Web SSR is implemented with Express and esbuild (no Next.js). Each app can run its own SSR server.

## Workspaces

- `apps/*` - Expo applications (shell, module-products, module-cart, module-pdp)
- `packages/*` - Shared packages (core, state, ui, products-ui, cart-ui, pdp-ui, homepage-ui)

## Requirements

- Node.js LTS (>=20)
- npm workspaces

## Documentation

- [Module Distribution Guide](./docs/MODULE_DISTRIBUTION.md) - How to build and distribute modules for existing native apps
- [iOS Integration Guide](./docs/IOS_INTEGRATION.md) - Integrating modules into existing iOS apps
- [Android Integration Guide](./docs/ANDROID_INTEGRATION.md) - Integrating modules into existing Android apps
- [Build Checklist](./docs/BUILD_CHECKLIST.md) - Quick reference checklist for module distribution
