// swift-tools-version: 5.9
// React Native Runtime SPM Package
// Generated from React Native 0.81.5 source
import PackageDescription

let package = Package(
    name: "MKDReactNativeRuntime",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "MKDReactNativeRuntime",
            targets: ["MKDReactNativeRuntime"]
        ),
        .library(
            name: "React",
            targets: ["React"]
        ),
    ],
    dependencies: [],
    targets: [
        .binaryTarget(
            name: "ReactNativeRuntimeBinary",
            path: "MKDReactNativeRuntime.xcframework"
        ),
        .binaryTarget(
            name: "HermesBinary",
            path: "hermes.xcframework"
        ),
        .target(
            name: "MKDReactNativeRuntime",
            dependencies: ["ReactNativeRuntimeBinary", "HermesBinary"],
            path: "Sources/MKDReactNativeRuntime",
            sources: ["MKDReactNativeRuntime.m"],
            publicHeadersPath: "Headers",
            linkerSettings: [
                .linkedFramework("MKDReactNativeRuntime"),
                .linkedFramework("hermes"),
                .linkedLibrary("c++"),
                .linkedLibrary("z"),
                .linkedLibrary("resolv"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("MobileCoreServices"),
                .linkedFramework("Accelerate"),
                .linkedFramework("CFNetwork"),
                .linkedFramework("CoreText"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Foundation"),
                .linkedFramework("UIKit"),
                .linkedFramework("JavaScriptCore"),
                .linkedFramework("SystemConfiguration"),
            ]
        ),
        .target(
            name: "React",
            dependencies: ["ReactNativeRuntimeBinary", "HermesBinary"],
            path: "Sources/React",
            sources: ["React.m"],
            publicHeadersPath: "Headers",
            linkerSettings: [
                .linkedFramework("MKDReactNativeRuntime"),
                .linkedFramework("hermes"),
                .linkedLibrary("c++"),
                .linkedLibrary("z"),
                .linkedLibrary("resolv"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("MobileCoreServices"),
                .linkedFramework("Accelerate"),
                .linkedFramework("CFNetwork"),
                .linkedFramework("CoreText"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Foundation"),
                .linkedFramework("UIKit"),
                .linkedFramework("JavaScriptCore"),
                .linkedFramework("SystemConfiguration"),
            ]
        ),
    ]
)
