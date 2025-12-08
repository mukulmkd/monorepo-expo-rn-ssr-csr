// swift-tools-version: 5.9
// ModuleCartFramework SPM Package
// Generated from @app/module-cart published to Verdaccio
import PackageDescription

let package = Package(
    name: "MKDRNModuleCartSPM",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "MKDRNModuleCartSPM",
            targets: ["MKDRNModuleCartSPM"]
        ),
    ],
    dependencies: [
        // React Native Runtime - required dependency
        // Path is relative to this package's location
                .package(path: "../MKDReactNativeRuntime")
    ],
    targets: [
        .target(
            name: "MKDRNModuleCartSPM",
            dependencies: [
                // React Native types from MKDReactNativeRuntime
                .product(name: "MKDReactNativeRuntime", package: "MKDReactNativeRuntime"),
                .product(name: "React", package: "MKDReactNativeRuntime")
            ],
            path: "Sources/MKDRNModuleCartSPM",
            resources: [
                .copy("Resources/module-cart.bundle")
            ],
            publicHeadersPath: "include"
        ),
    ]
)
