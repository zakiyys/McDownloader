import Foundation

/// Applies the com.apple.quarantine extended attribute to finished files.
/// aria2 writes files directly, so without this a downloaded .app or .dmg would
/// skip Gatekeeper's first-run check. macOS sets this for Safari downloads; a
/// third-party downloader must do the same to keep that protection intact.
enum Quarantine {
    static func markQuarantined(_ path: String, sourceURL: String?) {
        guard FileManager.default.fileExists(atPath: path) else { return }
        let stamp = Int(Date().timeIntervalSince1970)
        // Format: flags;timestamp;agent;uuid
        let value = "0081;\(String(stamp, radix: 16));McDownloader;\(UUID().uuidString)"
        _ = run(["-w", value, path])
    }

    @discardableResult
    private static func run(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            Log.error("quarantine apply failed: \(error.localizedDescription)")
            return -1
        }
    }
}
