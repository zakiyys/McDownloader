import Foundation
import os

/// Thin logging wrapper. Writes to the unified log and to engine.log so the
/// user (and bug reports) have a real trail without a debug build.
enum Log {
    private static let logger = Logger(subsystem: "io.github.zakiyys.McDownloader", category: "app")
    private static let queue = DispatchQueue(label: "io.github.zakiyys.McDownloader.log")

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        append("INFO", message)
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        append("ERROR", message)
    }

    private static func append(_ level: String, _ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) [\(level)] \(message)\n"
        queue.async {
            let url = AppPaths.engineLogFile
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }
}
