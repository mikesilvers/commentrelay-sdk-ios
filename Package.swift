// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CommentRelay",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "CommentRelay", targets: ["CommentRelay"]),
    ],
    targets: [
        .target(name: "CommentRelay"),
        .testTarget(name: "CommentRelayTests", dependencies: ["CommentRelay"]),
    ]
)
