# @app/module-products

Expo-based React Native module for products listing. Designed to be embedded in native Android/iOS apps or used standalone.

## Installation

```bash
npm install @app/module-products
```

**Peer Dependencies:** `expo`, `react`, `react-dom`, `react-native`

**Internal Dependencies:** `@pkg/core`, `@pkg/products-ui`, `@pkg/state`, `@pkg/ui`

## Usage

### Native Integration

The module registers itself as `ModuleProducts` with `AppRegistry`. In your native app:

**Android:**
```kotlin
val intent = Intent(context, ProductsActivity::class.java)
startActivity(intent)
```

**JavaScript:**
```tsx
import { AppRegistry } from "react-native";
import "@app/module-products"; // Registers "ModuleProducts"
```

### Standalone Development

```bash
npm run start
```

Opens in Expo Go for development and testing.

## Publishing

Publish to Verdaccio for local consumption:

```bash
npm run publish:verdaccio
```

See [docs/LOCAL_REGISTRY.md](../../docs/LOCAL_REGISTRY.md) for setup instructions.
