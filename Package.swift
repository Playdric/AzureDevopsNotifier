// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ADONotifier",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "ADONotifier", targets: ["ADONotifier"]),
    ],
    targets: [
        .target(name: "ADOCore"),
        .executableTarget(name: "ADONotifier", dependencies: ["ADOCore"]),
        .testTarget(
            name: "ADOCoreTests",
            dependencies: ["ADOCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
