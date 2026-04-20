// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CommentRelay",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "CommentRelayCore", targets: ["CommentRelayCore"]),
    ],
    targets: [
        .target(name: "CommentRelayCore"),
        .testTarget(name: "CommentRelayCoreTests", dependencies: ["CommentRelayCore"]),
    ]
)
