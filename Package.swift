// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CommentRelay",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "CommentRelayCore", targets: ["CommentRelayCore"]),
        .library(name: "CommentRelayUI", targets: ["CommentRelayUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
        .package(url: "https://github.com/nalexn/ViewInspector", from: "0.10.1"),
    ],
    targets: [
        .target(name: "CommentRelayCore"),
        .target(
            name: "CommentRelayUI",
            dependencies: ["CommentRelayCore"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "CommentRelayCoreTests", dependencies: ["CommentRelayCore"]),
        .testTarget(
            name: "CommentRelayUITests",
            dependencies: [
                "CommentRelayUI",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
                .product(name: "ViewInspector", package: "ViewInspector"),
            ]
        ),
    ]
)
