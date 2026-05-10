// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MacNotificationBarkBridge",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "mac-notification-bark-bridge",
            targets: ["MacNotificationBarkBridge"]
        )
    ],
    targets: [
        .executableTarget(
            name: "MacNotificationBarkBridge",
            resources: [
                .copy("Resources")
            ]
        ),
        .testTarget(
            name: "MacNotificationBarkBridgeTests",
            dependencies: ["MacNotificationBarkBridge"],
            resources: [
                .copy("Fixtures")
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
