// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PurpleAirKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "PurpleAirKit", targets: ["PurpleAirKit"]),
    ],
    targets: [
        .target(
            name: "PurpleAirKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "PurpleAirKitTests",
            dependencies: ["PurpleAirKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
