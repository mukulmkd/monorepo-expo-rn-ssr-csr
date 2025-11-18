# Packages Documentation

This document describes all shared packages in the monorepo. These packages are published to Verdaccio and consumed by both the modules and native apps.

## Core Packages

### `@pkg/core`

Shared domain logic, API helpers, and React hooks.

**Installation:**
```bash
npm install @pkg/core
```

**Peer Dependencies:** `react`, `react-native`, `@pkg/state`, `@pkg/ui`

**Exports:**
- `createApiClient(config)` - Simple fetch-based REST client
- `productsApi` - Product data fetching utilities
- `useProducts(apiClient)` - React hook for retrieving products (web/server compatible)
- `env` - Environment configuration helpers

**Usage:**
```ts
import { createApiClient, useProducts } from "@pkg/core";

const api = createApiClient({ baseUrl: "https://api.example.com" });

function ProductsList() {
  const { products, loading, error } = useProducts(api);
  // ...
}
```

---

### `@pkg/state`

Redux Toolkit store setup shared by all modules. Provides slices for cart state and product catalog.

**Installation:**
```bash
npm install @pkg/state
```

**Peer Dependencies:** `react-redux`, `@reduxjs/toolkit`

**Exports:**
- `configureStore(preloadedState?)` - Create Redux store
- `cartSlice` - Cart reducer and actions (`addToCart`, `removeFromCart`, `clearCart`)
- `productsSlice` - Products reducer and actions
- Types: `AppState`, `AppStore`, `RootState`

**Usage:**
```ts
import { configureStore } from "@pkg/state";
import { Provider } from "react-redux";

const store = configureStore();

<Provider store={store}>
  {/* Your app */}
</Provider>
```

---

### `@pkg/ui`

Shared, cross-platform UI primitives: navigation header, footer, and navigation menu.

**Installation:**
```bash
npm install @pkg/ui
```

**Peer Dependencies:** `react`, `react-native`, `react-redux`

**Exports:**
- `Header` - App header component
- `Footer` - App footer component
- `Navigation` - Navigation menu component
- `NavigationContext` - Context provider for module-level navigation
- `useNavigation()` - Hook to access navigation context
- `NavigationContextType` - TypeScript types

**Usage:**
```tsx
import { Header, Footer, Navigation, NavigationContext } from "@pkg/ui";

export function Shell({ children }) {
  return (
    <NavigationContext.Provider value={navigation}>
      <Header />
      <Navigation />
      <View style={{ flex: 1 }}>{children}</View>
      <Footer />
    </NavigationContext.Provider>
  );
}
```

---

## UI Component Packages

### `@pkg/products-ui`

UI components for the products listing experience.

**Installation:**
```bash
npm install @pkg/products-ui
```

**Peer Dependencies:** `react`, `react-native`, `react-redux`, `@pkg/state`, `@pkg/core`

**Exports:**
- `ProductsScreen({ onProductPress })` - Main products listing screen

**Usage:**
```tsx
import { ProductsScreen } from "@pkg/products-ui";

function ProductsModule() {
  return (
    <ProductsScreen 
      onProductPress={(productId) => navigateToPDP(productId)} 
    />
  );
}
```

**Requirements:** Redux Provider configured via `@pkg/state`

---

### `@pkg/cart-ui`

Cart experience UI components.

**Installation:**
```bash
npm install @pkg/cart-ui
```

**Peer Dependencies:** `react`, `react-native`, `react-redux`, `@pkg/state`

**Exports:**
- `CartScreen({ onProductPress })` - Main cart screen

**Usage:**
```tsx
import { CartScreen } from "@pkg/cart-ui";

function CartModule() {
  return (
    <CartScreen 
      onProductPress={(productId) => navigateToPDP(productId)} 
    />
  );
}
```

**Requirements:** Redux Provider configured via `@pkg/state`

---

### `@pkg/pdp-ui`

Product detail page UI components.

**Installation:**
```bash
npm install @pkg/pdp-ui
```

**Peer Dependencies:** `react`, `react-native`, `react-redux`, `@pkg/state`, `@pkg/core`

**Exports:**
- `ProductDetailScreen({ productId, onAddToCart })` - Product detail screen

**Usage:**
```tsx
import { ProductDetailScreen } from "@pkg/pdp-ui";
import { useDispatch } from "react-redux";
import { addToCart } from "@pkg/state";

function PDPModule({ productId }) {
  const dispatch = useDispatch();
  
  return (
    <ProductDetailScreen
      productId={productId}
      onAddToCart={() => dispatch(addToCart({ productId }))}
    />
  );
}
```

**Requirements:** Redux Provider configured via `@pkg/state`

---

### `@pkg/homepage-ui`

Homepage shell UI with hero banner and featured sections.

**Installation:**
```bash
npm install @pkg/homepage-ui
```

**Peer Dependencies:** `react`, `react-native`, `react-redux`, `@pkg/state`, `@pkg/ui`

**Exports:**
- `HomepageScreen({ onNavigate })` - Homepage screen

**Usage:**
```tsx
import { HomepageScreen } from "@pkg/homepage-ui";

export function HomepageModule() {
  return (
    <HomepageScreen 
      onNavigate={(route) => navigation.navigate(route)} 
    />
  );
}
```

**Requirements:** Redux Provider and NavigationContext configured

---

## Publishing

All packages are published to the local Verdaccio registry:

```bash
# Publish all packages
npm run verdaccio:publish-all

# Or publish individual package
cd packages/core
npm run publish:verdaccio
```

See [LOCAL_REGISTRY.md](./LOCAL_REGISTRY.md) for detailed publishing instructions.

## Dependency Graph

```
apps/module-* 
  ├── @pkg/core
  ├── @pkg/state
  ├── @pkg/ui
  └── @pkg/*-ui (products-ui, cart-ui, pdp-ui)

packages/*-ui
  ├── @pkg/core
  ├── @pkg/state
  └── @pkg/ui (for some)
```

