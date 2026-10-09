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
    static func engineStderrURL(named name: String) -> URL { supportDir.appendingPathComponent("engine.stderr.\(name).log") }
    static var torrentStateDir: URL { supportDir.appendingPathComponent("torrentState", isDirectory: true) }

    static func ensureDirectories() throws {
        let fm = FileManager.default
        for url in [supportDir, torrentStateDir] {
            if !fm.fileExists(atPath: url.path) {
                try fm.createDirectory(at: url, withIntermediateDirectories: true)
            }
        }
    }

    /// aria2 refuses to start when `--input-file` names a file that is not there.
    /// Create an empty session so a first launch works, and so resume works after.
    static func ensureSessionFile() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: aria2SessionFile.path) {
            _ = fm.createFile(atPath: aria2SessionFile.path, contents: Data())
        }
    }

    /// A shared, append-only handle for an engine's stderr, so startup failures
    /// (bad flag, missing folder) are captured instead of silently discarded.
    static func engineStderrHandle(named name: String = "aria2") -> FileHandle? {
        let url = engineStderrURL(named: name)
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            _ = fm.createFile(atPath: url.path, contents: Data())
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return nil }
        handle.seekToEndOfFile()
        return handle
    }

    /// The last non-empty line of an engine's stderr, for a human-readable error.
    static func engineStderrTail(named name: String = "aria2") -> String? {
        guard let text = try? String(contentsOf: engineStderrURL(named: name), encoding: .utf8) else { return nil }
        return text
            .split(whereSeparator: \.isNewline)
            .last
            .map(String.init)
            .flatMap { $0.isEmpty ? nil : $0 }
    }
}
