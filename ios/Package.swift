// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "EasyTrans",
    platforms: [
        .iOS(.v26),
    ],
    products: [
        // An xtool project should contain exactly one library product,
        // representing the main app.
        .library(
            name: "EasyTrans",
            targets: ["EasyTrans"]
        ),
    ],
    targets: [
        .target(
            name: "EasyTrans",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
