import Foundation

enum TransferKind: String, Codable {
    case http
    case torrent
}

/// One entry in the download manager. The store keeps these in sync with
/// whichever engine owns them (aria2 for HTTP, the torrent helper for torrents).
struct Transfer: Identifiable, Equatable {
    let id: String
    var kind: TransferKind
    var name: String
    var state: TransferState

    var totalBytes: Int64
    var completedBytes: Int64
    var downloadSpeed: Int64
    var uploadSpeed: Int64

    /// Live peer connections for a torrent; segmented connections for HTTP.
    var peersConnected: Int
    var connections: Int

    /// Absolute path of the downloaded file, or the folder for multi-file torrents.
    var targetPath: String
    var errorMessage: String?

    /// Origin of the request. For HTTP this is the URL; for torrents the magnet
    /// URI when available, otherwise nil.
    var sourceURL: String?
    var sourceHost: String

    var addedAt: Date
    var category: TransferCategory
    var savePath: String

    /// Real per-piece progress derived from the engine (aria2 bitfield, or
    /// torrent piece map). Empty when the engine does not report it yet.
    var segments: [Segment]

    var torrent: TorrentInfo?

    var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(completedBytes) / Double(totalBytes))
    }

    var remainingBytes: Int64 { max(0, totalBytes - completedBytes) }

    var eta: String { Fmt.eta(remaining: remainingBytes, speed: downloadSpeed) }

    var isActive: Bool {
        state == .downloading || state == .connecting || state == .seeding
    }

    var detailSummary: String {
        switch state {
        case .completed: return Fmt.bytes(totalBytes)
        case .error: return errorMessage ?? "Error"
        case .paused: return "\(Fmt.percent(progress)) · paused"
        default: return "\(Fmt.percent(progress)) · \(Fmt.speed(downloadSpeed))"
        }
    }
}

enum TransferState: String, Codable {
    case queued
    case connecting
    case downloading
    case seeding
    case paused
    case completed
    case error

    var label: String {
        switch self {
        case .queued: return "Queued"
        case .connecting: return "Connecting"
        case .downloading: return "Downloading"
        case .seeding: return "Seeding"
        case .paused: return "Paused"
        case .completed: return "Completed"
        case .error: return "Error"
        }
    }
}

/// A slice of a file. For HTTP, aria2 reports piece-level completion as a
/// bitfield; we turn that into a fixed number of visual cells. For torrents
/// this mirrors the piece map. Never invented: derived from the engine.
struct Segment: Identifiable, Equatable, Codable {
    let id: Int
    var completed: Bool
}

enum TransferCategory: String, Codable, CaseIterable {
    case video
    case audio
    case documents
    case archives
    case applications
    case other

    var label: String {
        switch self {
        case .video: return "Video"
        case .audio: return "Audio"
        case .documents: return "Documents"
        case .archives: return "Archives"
        case .applications: return "Applications"
        case .other: return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .video: return "film"
        case .audio: return "waveform"
        case .documents: return "doc.text"
        case .archives: return "archivebox"
        case .applications: return "app.dashed"
        case .other: return "doc"
        }
    }
}

/// Torrent-only detail. Populated on demand for the inspector so the main
/// polling loop stays cheap.
struct TorrentInfo: Equatable {
    var infoHash: String
    var ratio: Double
    var uploadedBytes: Int64
    var trackers: [TrackerStatus]
    var peers: [Peer]
    var files: [TorrentFile]
    var seeders: Int
    var leechers: Int
}

struct TorrentFile: Identifiable, Equatable {
    let id: Int
    var path: String
    var length: Int64
    var completed: Int64
    var selected: Bool

    var progress: Double {
        guard length > 0 else { return 0 }
        return min(1, Double(completed) / Double(length))
    }
}

struct Peer: Identifiable, Equatable {
    var id: String { "\(address):\(port)" }
    var address: String
    var port: Int
    var client: String
    var downloadSpeed: Int64
    var uploadSpeed: Int64
    var progress: Double
    var flags: String
}

struct TrackerStatus: Identifiable, Equatable {
    var id: String { url }
    var url: String
    var message: String
    var seeders: Int
    var leechers: Int
    var working: Bool
}
