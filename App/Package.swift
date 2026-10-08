// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "McDownloader",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "McDownloader", targets: ["McDownloader"])
    ],
    targets: [
        .executableTarget(
            name: "McDownloader",
            path: "Sources/McDownloader",
            swiftSettings: [
                .unsafeFlags(["-Onone"], .when(configuration: .debug))
            ]
        )
    ]
)
