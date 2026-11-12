// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Presto",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "Presto", targets: ["Presto"])
    ],
    targets: [
        .binaryTarget(
            name: "llama",
            path: "Vendor/llama.xcframework"
        ),
        .executableTarget(
            name: "Presto",
            dependencies: ["llama"],
            path: "Sources/Presto",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("FoundationModels"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Metal"),
                .linkedFramework("Accelerate"),
                .linkedLibrary("c++"),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        )
    ]
)
