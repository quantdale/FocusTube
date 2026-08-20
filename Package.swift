// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FocusTubeCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "FocusTubeCore", targets: ["FocusTubeCore"])
    ],
    targets: [
        .target(name: "FocusTubeCore"),
        .testTarget(name: "FocusTubeCoreTests", dependencies: ["FocusTubeCore"])
    ]
)
