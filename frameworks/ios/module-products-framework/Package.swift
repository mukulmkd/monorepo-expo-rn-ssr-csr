// swift-tools-version: 5.9
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
        // React Native dependencies are provided by consuming app
    ],
    targets: [
        .target(
            name: "ModuleProductsFramework",
            dependencies: [],
            path: "Sources/ModuleProductsFramework",
            resources: [
                .process("../Resources/module-products.bundle")
            ]
        ),
    ]
)

