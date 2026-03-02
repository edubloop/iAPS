// swift-tools-version: 5.9
// Standalone test package for the TIR Decomposition Engine (Track 1).
//
// Run:  swift test --package-path BuildTools/TIREngineTests
//
// The Sources/FreeAPS module mirrors the minimal types from the main iAPS app
// that the engine depends on, so the test files need zero modification.

import PackageDescription

let package = Package(
    name: "TIREngineTests",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "FreeAPS",
            path: "Sources/FreeAPS"
        ),
        .testTarget(
            name: "FreeAPSTests",
            dependencies: ["FreeAPS"],
            path: "Tests/FreeAPSTests"
        )
    ]
)
