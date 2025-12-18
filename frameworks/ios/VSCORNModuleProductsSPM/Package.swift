// swift-tools-version: 5.9
// ModuleProductsFramework SPM Package
// Generated from @app/module-products published to Verdaccio
import PackageDescription

let package = Package(
    name: "VSCORNModuleProductsSPM",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "VSCORNModuleProductsSPM",
            targets: ["VSCORNModuleProductsSPM"]
        ),
    ],
    dependencies: [
        // React Native Runtime - required dependency
        // Path is relative to this package's location
        .package(path: "../VSCOReactNativeRuntime"),
        // Native dependencies (react-native-svg, react-native-safe-area-context, etc.)
        // Detected native dependencies: expo-file-system react-native-svg
        // Path is relative to this package's location
        // Note: Package.swift is located at vsco-native-kit/ios/VSCONativeKit/Package.swift
        // Path is relative to this package's location (frameworks/ios/VSCORNModuleProductsSPM/)
        .package(path: "../../../vsco-native-kit/ios/VSCONativeKit")
    ],
    targets: [
        .target(
            name: "VSCORNModuleProductsSPM",
            dependencies: [
                // React Native types from VSCOReactNativeRuntime
                .product(name: "VSCOReactNativeRuntime", package: "VSCOReactNativeRuntime"),
                .product(name: "React", package: "VSCOReactNativeRuntime"),
                // Native dependencies from VSCONativeKit
                // Detected native dependencies: expo-file-system react-native-svg
                // Note: Package name is "VSCONativeKit" as defined in its Package.swift
                .product(name: "VSCONativeKit", package: "VSCONativeKit")
            ],
            path: "Sources/VSCORNModuleProductsSPM",
            resources: [
                .copy("Resources/module-products.bundle")
            ],
            publicHeadersPath: "include"
        ),
    ]
)
