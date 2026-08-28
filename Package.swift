// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ApprovalAssistant",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "ApprovalAssistant",
            targets: ["ApprovalAssistant"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "ApprovalAssistant"
        ),
        .testTarget(
            name: "ApprovalAssistantTests",
            dependencies: ["ApprovalAssistant"]
        ),
    ]
)
