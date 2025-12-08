// swift-tools-version: 5.9
// ModulePDPFramework SPM Package
// Generated from @app/module-pdp published to Verdaccio
import PackageDescription

let package = Package(
    name: "MKDRNModulePdpSPM",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "MKDRNModulePdpSPM",
            targets: ["MKDRNModulePdpSPM"]
        ),
    ],
    dependencies: [
        // React Native Runtime - required dependency
        // Path is relative to this package's location
                .package(path: "../MKDReactNativeRuntime")
    ],
    targets: [
        .target(
            name: "MKDRNModulePdpSPM",
            dependencies: [
                // React Native types from MKDReactNativeRuntime
                .product(name: "MKDReactNativeRuntime", package: "MKDReactNativeRuntime"),
                .product(name: "React", package: "MKDReactNativeRuntime")
            ],
            path: "Sources/MKDRNModulePdpSPM",
            resources: [
                .copy("Resources/module-pdp.bundle")
            ],
            publicHeadersPath: "include"
        ),
    ]
)
