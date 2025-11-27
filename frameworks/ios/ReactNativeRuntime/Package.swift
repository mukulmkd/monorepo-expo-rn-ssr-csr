// swift-tools-version: 5.9
// React Native Runtime SPM Package
// Generated from React Native 0.81.5 source
import PackageDescription

let package = Package(
    name: "ReactNativeRuntime",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "ReactNativeRuntime",
            targets: ["ReactNativeRuntime"]
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
            path: "ReactNativeRuntime.xcframework"
        ),
        .binaryTarget(
            name: "HermesBinary",
            path: "hermes.xcframework"
        ),
        .target(
            name: "ReactNativeRuntime",
            dependencies: ["ReactNativeRuntimeBinary", "HermesBinary"],
            path: "Sources/ReactNativeRuntime",
            exclude: [
                "Headers/**/*.m",
                "Headers/**/*.mm",
                "Headers/**/*.cpp",
                "Headers/**/*.c",
                "Headers/**/*.S"
            ],
            sources: ["ReactNativeRuntime.m"],
            publicHeadersPath: "Headers",
            linkerSettings: [
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
            exclude: [
                "Headers/**/*.m",
                "Headers/**/*.mm",
                "Headers/**/*.cpp",
                "Headers/**/*.c",
                "Headers/**/*.S"
            ],
            sources: ["React.m"],
            publicHeadersPath: "Headers",
            linkerSettings: [
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
