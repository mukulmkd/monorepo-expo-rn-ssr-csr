// swift-tools-version: 5.9
// ModuleCartFramework SPM Package
// Generated from @app/module-cart published to Verdaccio
import PackageDescription

let package = Package(
    name: "ModuleCartFramework",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "ModuleCartFramework",
            targets: ["ModuleCartFramework"]
        ),
    ],
    dependencies: [
        // React Native Runtime - required dependency
        // Path is relative to this package's location
        .package(path: "../ReactNativeRuntime")
    ],
    targets: [
        .target(
            name: "ModuleCartFramework",
            dependencies: [
                // React Native types from ReactNativeRuntime
                .product(name: "ReactNativeRuntime", package: "ReactNativeRuntime"),
                .product(name: "React", package: "ReactNativeRuntime")
            ],
            path: "Sources/ModuleCartFramework",
            resources: [
                .copy("Resources/module-cart.bundle")
            ],
            publicHeadersPath: "include"
        ),
    ]
)
