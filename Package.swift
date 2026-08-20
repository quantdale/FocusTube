// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FocusTubeCore",
    products: [
        .library(name: "FocusTubeCore", targets: ["FocusTubeCore"])
    ],
    targets: [
        .target(name: "FocusTubeCore"),
        .testTarget(name: "FocusTubeCoreTests", dependencies: ["FocusTubeCore"])
    ]
)
