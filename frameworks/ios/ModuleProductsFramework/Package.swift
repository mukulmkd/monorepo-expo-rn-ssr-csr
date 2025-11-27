// swift-tools-version: 5.9
// ModuleProductsFramework SPM Package
// Generated from @app/module-products published to Verdaccio
import PackageDescription

let package = Package(
    name: "ModuleProductsFramework",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "ModuleProductsFramework",
            targets: ["ModuleProductsFramework"]
        ),
    ],
    dependencies: [
        // React Native Runtime - required dependency
        // Path is relative to this package's location
        .package(path: "../ReactNativeRuntime")
    ],
    targets: [
        .target(
            name: "ModuleProductsFramework",
            dependencies: [
                // React Native types from ReactNativeRuntime
                .product(name: "ReactNativeRuntime", package: "ReactNativeRuntime"),
                .product(name: "React", package: "ReactNativeRuntime")
            ],
            path: "Sources/ModuleProductsFramework",
            resources: [
                .copy("Resources/module-products.bundle")
            ],
            publicHeadersPath: "include"
        ),
    ]
)
