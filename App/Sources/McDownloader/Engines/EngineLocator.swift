import Foundation

/// Finds the engine binaries. In a release build they live inside the app
/// bundle's Resources; during development they may sit in the repo's vendor
/// folder or on the PATH, so we look there too.
enum EngineLocator {
    static func aria2c() -> URL? {
        find(name: "aria2c", extraDirs: [
            Bundle.main.resourceURL,
            repoVendorDir()
        ])
    }

    static func torrentHelper() -> URL? {
        find(name: "mcdownloader-torrentd", extraDirs: [
            Bundle.main.resourceURL,
            repoVendorDir()
        ])
    }

    static func ytDlp() -> URL? {
        find(name: "yt-dlp", extraDirs: [toolsDir()])
    }

    static func ffmpeg() -> URL? {
        find(name: "ffmpeg", extraDirs: [toolsDir()])
    }

    static func toolsDir() -> URL {
        AppPaths.supportDir.appendingPathComponent("tools", isDirectory: true)
    }

    private static func repoVendorDir() -> URL? {
        // Walk up from the executable looking for a sibling "vendor" folder,
        // which is how the development layout ships the engines.
        var url = Bundle.main.bundleURL
        for _ in 0..<6 {
            let candidate = url.appendingPathComponent("vendor")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            url.deleteLastPathComponent()
        }
        return nil
    }

    private static func find(name: String, extraDirs: [URL?]) -> URL? {
        let fm = FileManager.default
        for dir in extraDirs {
            guard let dir else { continue }
            let url = dir.appendingPathComponent(name)
            if fm.isExecutableFile(atPath: url.path) { return url }
        }
        // PATH lookup as a last resort.
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
        for p in paths {
            let url = URL(fileURLWithPath: String(p)).appendingPathComponent(name)
            if fm.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }
}
