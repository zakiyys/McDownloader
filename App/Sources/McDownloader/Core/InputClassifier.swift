import Foundation

/// Decides what a piece of text is, so the "Add" flow can route it: an HTTP
/// link, a magnet, or a local .torrent file path.
enum InputClassifier {
    enum Classified {
        case url(String)
        case magnet(String)
        case torrentFile(String)
        case unknown(String)
    }

    static func classify(_ text: String) -> Classified {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .unknown("") }

        if trimmed.lowercased().hasPrefix("magnet:") {
            return .magnet(trimmed)
        }
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") || trimmed.lowercased().hasPrefix("ftp://") {
            return .url(trimmed)
        }
        if trimmed.hasPrefix("file://"), let url = URL(string: trimmed) {
            return .torrentFile(url.path)
        }
        // A bare path on disk.
        if FileManager.default.fileExists(atPath: trimmed), (trimmed as NSString).pathExtension.lowercased() == "torrent" {
            return .torrentFile(trimmed)
        }
        // Could be a host we can finish; leave it to the user.
        return .unknown(trimmed)
    }
}
