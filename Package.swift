// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Gloss",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "Gloss", targets: ["Gloss"])
    ],
    targets: [
        .binaryTarget(
            name: "llama",
            path: "Vendor/llama.xcframework"
        ),
        .executableTarget(
            name: "Gloss",
            dependencies: ["llama"],
            path: "Sources/Gloss",
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
