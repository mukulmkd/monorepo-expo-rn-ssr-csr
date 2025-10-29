# Monorepo: Expo RN with Web CSR/SSR (Express)

This monorepo uses npm workspaces. It contains three Expo apps (shell, module-products, module-cart) and shared packages for UI, core utilities, and state.

Web SSR is implemented with Express and Webpack (no Next.js). Each app can run its own SSR server.

Workspaces:

- apps/\*
- packages/\*

Requirements: Node.js LTS (>=20)
