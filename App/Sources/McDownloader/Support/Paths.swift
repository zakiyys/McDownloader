import Foundation

/// Filesystem locations the app owns. Everything lives under the user's
/// Application Support directory so the app never writes into its own bundle.
enum AppPaths {
    static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("McDownloader", isDirectory: true)
    }

    static var downloadsDir: URL {
        let base = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        return base
    }

    static var configFile: URL { supportDir.appendingPathComponent("config.json") }
    static var aria2SessionFile: URL { supportDir.appendingPathComponent("aria2.session") }
    static var aria2LogFile: URL { supportDir.appendingPathComponent("aria2.log") }
    static var engineLogFile: URL { supportDir.appendingPathComponent("engine.log") }
    static var torrentStateDir: URL { supportDir.appendingPathComponent("torrent-state", isDirectory: true) }

    static func ensureDirectories() throws {
        let fm = FileManager.default
        for url in [supportDir, torrentStateDir] {
            if !fm.fileExists(atPath: url.path) {
                try fm.createDirectory(at: url, withIntermediateDirectories: true)
            }
        }
    }
}
