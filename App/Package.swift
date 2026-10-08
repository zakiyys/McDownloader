// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "McDownloader",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "McDownloader", targets: ["McDownloader"]),
        // The Chromium native messaging host. It is shipped inside the app
        // bundle next to the main binary and launched by the browser, not by
        // the user.
        .executable(name: "mcdownloader-host", targets: ["mcdownloader-host"])
    ],
    targets: [
        .executableTarget(
            name: "McDownloader",
            path: "Sources/McDownloader",
            swiftSettings: [
                .unsafeFlags(["-Onone"], .when(configuration: .debug))
            ]
        ),
        .executableTarget(
            name: "mcdownloader-host",
            path: "Sources/mcdownloader-host"
        )
    ]
)
