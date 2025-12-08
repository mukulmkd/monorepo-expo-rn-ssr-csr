// swift-tools-version: 5.9
// ModuleProductsFramework SPM Package
// Generated from @app/module-products published to Verdaccio
import PackageDescription

let package = Package(
    name: "MKDRNModuleProductsSPM",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "MKDRNModuleProductsSPM",
            targets: ["MKDRNModuleProductsSPM"]
        ),
    ],
    dependencies: [
        // React Native Runtime - required dependency
        // Path is relative to this package's location
                .package(path: "../MKDReactNativeRuntime")
    ],
    targets: [
        .target(
            name: "MKDRNModuleProductsSPM",
            dependencies: [
                // React Native types from MKDReactNativeRuntime
                .product(name: "MKDReactNativeRuntime", package: "MKDReactNativeRuntime"),
                .product(name: "React", package: "MKDReactNativeRuntime")
            ],
            path: "Sources/MKDRNModuleProductsSPM",
            resources: [
                .copy("Resources/module-products.bundle")
            ],
            publicHeadersPath: "include"
        ),
    ]
)
