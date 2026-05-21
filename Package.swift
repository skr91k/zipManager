// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ZipManager",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
    ],
    targets: [
        .executableTarget(
            name: "ZipManager",
            dependencies: [
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            path: "Sources/ZipManager"
        ),
    ]
)
