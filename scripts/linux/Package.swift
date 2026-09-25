// swift-tools-version:5.9
// Template used by scripts/linux-check.sh to build and test MusicApp/Core on Linux.
// The iOS app itself is built with MusicApp.xcodeproj; this package only exists for CI.
import PackageDescription

let package = Package(
    name: "MusicAppCore",
    targets: [
        .target(
            name: "MusicApp",
            path: "Sources/MusicApp"
        ),
        .testTarget(
            name: "MusicAppTests",
            dependencies: ["MusicApp"],
            path: "Tests/MusicAppTests",
            resources: [.process("Fixtures")]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
