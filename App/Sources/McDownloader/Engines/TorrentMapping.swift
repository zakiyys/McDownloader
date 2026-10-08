import Foundation

/// Maps the torrent helper's JSON to `Transfer`. The helper uses the same
/// field names as aria2 where they overlap, so the two halves of the UI read
/// identically.
enum TorrentMapping {
    static func transfer(from raw: [String: Any]) -> Transfer? {
        guard let id = raw.string("id") else { return nil }

        let total = raw.int64("totalBytes") ?? 0
        let completed = raw.int64("completedBytes") ?? 0
        let downloadSpeed = raw.int64("downloadSpeed") ?? 0
        let uploadSpeed = raw.int64("uploadSpeed") ?? 0
        let name = raw.string("name") ?? "Torrent"
        let savePath = raw.string("savePath") ?? AppPaths.downloadsDir.path
        let target = raw.string("targetPath") ?? savePath

        let state = state(from: raw.string("state") ?? "")
        let pieces = (raw["pieces"] as? [Int]) ?? []
        let segments = pieces.enumerated().map { Segment(id: $0.offset, completed: $0.element != 0) }

        let upload = raw.int64("uploadedBytes") ?? 0

        return Transfer(
            id: id,
            kind: .torrent,
            name: name,
            state: state,
            totalBytes: total,
            completedBytes: completed,
            downloadSpeed: state == .downloading || state == .seeding ? downloadSpeed : 0,
            uploadSpeed: state == .seeding || state == .downloading ? uploadSpeed : 0,
            peersConnected: raw.int("peersConnected") ?? 0,
            connections: raw.int("peersConnected") ?? 0,
            targetPath: target,
            errorMessage: raw.string("error").flatMap { $0.isEmpty ? nil : $0 },
            sourceURL: raw.string("magnet"),
            sourceHost: "BitTorrent",
            addedAt: Date(),
            category: CategoryRules.category(for: name),
            savePath: savePath,
            segments: segments,
            torrent: TorrentInfo(
                infoHash: raw.string("infoHash") ?? "",
                ratio: raw.double("ratio") ?? 0,
                uploadedBytes: upload,
                trackers: [],
                peers: [],
                files: [],
                seeders: raw.int("seeders") ?? 0,
                leechers: raw.int("leechers") ?? 0
            )
        )
    }

    static func details(from raw: [String: Any]) throws -> (TorrentInfo, Transfer?) {
        var info = TorrentInfo(
            infoHash: raw.string("infoHash") ?? "",
            ratio: raw.double("ratio") ?? 0,
            uploadedBytes: raw.int64("uploadedBytes") ?? 0,
            trackers: [],
            peers: [],
            files: [],
            seeders: raw.int("seeders") ?? 0,
            leechers: raw.int("leechers") ?? 0
        )

        if let files = raw.array("files") {
            info.files = files.compactMap { file in
                guard let index = file.int("index") else { return nil }
                return TorrentFile(
                    id: index,
                    path: file.string("path") ?? "file \(index)",
                    length: file.int64("length") ?? 0,
                    completed: file.int64("completed") ?? 0,
                    selected: file.bool("selected") ?? true
                )
            }
        }

        if let peers = raw.array("peers") {
            info.peers = peers.compactMap { peer in
                guard let address = peer.string("address") else { return nil }
                return Peer(
                    address: address,
                    port: peer.int("port") ?? 0,
                    client: peer.string("client") ?? "",
                    downloadSpeed: peer.int64("downloadSpeed") ?? 0,
                    uploadSpeed: peer.int64("uploadSpeed") ?? 0,
                    progress: peer.double("progress") ?? 0,
                    flags: peer.string("flags") ?? ""
                )
            }
        }

        if let trackers = raw.array("trackers") {
            info.trackers = trackers.compactMap { tracker in
                guard let url = tracker.string("url") else { return nil }
                return TrackerStatus(
                    url: url,
                    message: tracker.string("message") ?? "",
                    seeders: tracker.int("seeders") ?? 0,
                    leechers: tracker.int("leechers") ?? 0,
                    working: tracker.bool("working") ?? false
                )
            }
        }
        return (info, nil)
    }

    private static func state(from raw: String) -> TransferState {
        switch raw {
        case "queued", "allocating", "checking", "meta": return .connecting
        case "downloading": return .downloading
        case "seeding": return .seeding
        case "paused": return .paused
        case "completed", "finished": return .completed
        case "error": return .error
        default: return .queued
        }
    }
}
