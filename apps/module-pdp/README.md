# @app/module-pdp

Expo-based React Native module for product detail pages. Provides detailed product information screens ready to embed in native apps.

## Installation

```bash
npm install @app/module-pdp
```

**Peer Dependencies:** `expo`, `react`, `react-dom`, `react-native`

**Internal Dependencies:** `@pkg/core`, `@pkg/pdp-ui`, `@pkg/state`, `@pkg/ui`

## Usage

### Native Integration

The module exports `ModulePDP` via `AppRegistry`. On Android, create a `ReactActivity` that returns `"ModulePDP"` and pass initial props (e.g., `productId`) through activity extras.

**Android:**
```kotlin
val intent = Intent(context, PDPActivity::class.java)
intent.putExtra("productId", productId)
startActivity(intent)
```

**JavaScript:**
```tsx
import "@app/module-pdp"; // Registers "ModulePDP"
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

See [docs/LOCAL_REGISTRY.md](../../docs/LOCAL_REGISTRY.md) for registry setup and authentication.
