import Foundation

/// Turns aria2's raw JSON into our `Transfer` model. Kept separate from the
/// engine so the mapping is easy to test and reason about.
enum Aria2Mapping {
    static func transfer(from raw: [String: Any]) -> Transfer? {
        guard let gid = raw.string("gid") else { return nil }

        let total = raw.int64("totalLength") ?? 0
        let completed = raw.int64("completedLength") ?? 0
        let downloadSpeed = raw.int64("downloadSpeed") ?? 0
        let uploadSpeed = raw.int64("uploadSpeed") ?? 0
        let connections = raw.int("connections") ?? 0

        let files = raw.array("files") ?? []
        let firstPath = (files.first?.string("path")) ?? ""
        let dir = raw.string("dir") ?? AppPaths.downloadsDir.path
        let rawName = raw.string("bittorrent") != nil
            ? (firstPath.isEmpty ? "Torrent" : (firstPath as NSString).lastPathComponent)
            : nameFromPath(firstPath, dir: dir)
        let name = rawName.isEmpty ? "Download" : rawName

        let sourceURL = firstURI(in: files)
        let host = sourceURL.flatMap { URL(string: $0)?.host } ?? ""

        let state = state(from: raw, completed: completed, total: total)

        return Transfer(
            id: gid,
            kind: .http,
            name: name,
            state: state,
            totalBytes: total,
            completedBytes: completed,
            downloadSpeed: state == .downloading ? downloadSpeed : 0,
            uploadSpeed: 0,
            peersConnected: 0,
            connections: connections,
            targetPath: firstPath.isEmpty ? dir : firstPath,
            errorMessage: raw.string("errorMessage").flatMap { $0.isEmpty ? nil : $0 },
            sourceURL: sourceURL,
            sourceHost: host,
            addedAt: Date(),
            category: CategoryRules.category(for: name),
            savePath: dir,
            segments: [],
            torrent: nil
        )
    }

    private static func firstURI(in files: [[String: Any]]) -> String? {
        for file in files {
            if let uris = file["uris"] as? [[String: Any]],
               let uri = uris.first?.string("uri"), !uri.isEmpty {
                return uri
            }
        }
        return nil
    }

    private static func nameFromPath(_ path: String, dir: String) -> String {
        if !path.isEmpty { return (path as NSString).lastPathComponent }
        return (dir as NSString).lastPathComponent
    }

    private static func state(from raw: [String: Any], completed: Int64, total: Int64) -> TransferState {
        switch raw.string("status") ?? "" {
        case "active":
            return completed == 0 ? .connecting : .downloading
        case "waiting":
            return .queued
        case "paused":
            return .paused
        case "complete":
            return .completed
        case "error", "removed":
            // A user-removed item is not a failure; a real error carries a message.
            if let code = raw.string("errorCode"), code != "0", code != "12" {
                return .error
            }
            return raw.string("status") == "error" ? .error : .completed
        default:
            return .queued
        }
    }
}
