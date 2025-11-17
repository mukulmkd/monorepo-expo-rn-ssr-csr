# @app/module-cart

Expo-based React Native module for shopping cart experience. Embeddable in native hosts via React Native bridge.

## Installation

```bash
npm install @app/module-cart
```

**Peer Dependencies:** `expo`, `react`, `react-dom`, `react-native`

**Internal Dependencies:** `@pkg/cart-ui`, `@pkg/core`, `@pkg/state`, `@pkg/ui`

## Usage

### Native Integration

The module registers `ModuleCart` with `AppRegistry`. Configure your native host to render this component.

**Android:**
```kotlin
// In your ReactActivity
override fun getMainComponentName(): String = "ModuleCart"
```

**JavaScript:**
```tsx
import "@app/module-cart"; // Registers "ModuleCart"
```

### Standalone Development

```bash
npm run start
```

## Publishing

Publish to local Verdaccio:

```bash
npm run publish:verdaccio
```

See [docs/LOCAL_REGISTRY.md](../../docs/LOCAL_REGISTRY.md) for registry setup.
