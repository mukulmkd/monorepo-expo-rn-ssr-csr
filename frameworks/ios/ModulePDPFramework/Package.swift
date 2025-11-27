// swift-tools-version: 5.9
// ModulePDPFramework SPM Package
// Generated from @app/module-pdp published to Verdaccio
import PackageDescription

let package = Package(
    name: "ModulePDPFramework",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "ModulePDPFramework",
            targets: ["ModulePDPFramework"]
        ),
    ],
    dependencies: [
        // React Native Runtime - required dependency
        // Path is relative to this package's location
        .package(path: "../ReactNativeRuntime")
    ],
    targets: [
        .target(
            name: "ModulePDPFramework",
            dependencies: [
                // React Native types from ReactNativeRuntime
                .product(name: "ReactNativeRuntime", package: "ReactNativeRuntime"),
                .product(name: "React", package: "ReactNativeRuntime")
            ],
            path: "Sources/ModulePDPFramework",
            resources: [
                .copy("Resources/module-pdp.bundle")
            ],
            publicHeadersPath: "include"
        ),
    ]
)
