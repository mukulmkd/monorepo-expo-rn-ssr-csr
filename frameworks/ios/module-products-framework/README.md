# ModuleProductsFramework

iOS xcframework wrapper for the Products React Native module.

## Overview

This framework packages the Products module as a self-contained xcframework that can be consumed via Swift Package Manager (SPM). The framework includes:

- Pre-bundled JavaScript code (all dependencies included)
- Swift wrapper API for easy integration
- No Verdaccio or npm required at runtime

## Building

### Prerequisites

- Verdaccio must be running: `npm run verdaccio:start`
- Packages must be published: `npm run verdaccio:publish-all`

### Build Steps

```bash
# From monorepo root
npm run framework:ios:build:products

# Or manually
cd frameworks/ios/module-products-framework
./scripts/build-xcframework.sh
```

## Usage in Native Apps

### Swift Package Manager (SPM)

Add to your `Package.swift`:

```swift
dependencies: [
    .package(
        path: "../monorepo-expo-rn-ssr-csr/frameworks/ios/module-products-framework"
    )
]
```

### In Code

```swift
import ModuleProductsFramework

// Create a view
if let productsView = ModuleProductsFramework.shared.createProductsView() {
    view.addSubview(productsView)
    productsView.frame = view.bounds
}

// Or create a ViewController
let productsVC = ModuleProductsFramework.shared.createProductsViewController()
navigationController.pushViewController(productsVC, animated: true)
```

## Structure

```
module-products-framework/
├── Sources/
│   └── ModuleProductsFramework/
│       └── ModuleProductsFramework.swift
├── Resources/
│   └── module-products.bundle
├── Package.swift
└── scripts/
    ├── bundle.sh
    └── build-xcframework.sh
```

