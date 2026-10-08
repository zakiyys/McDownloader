import Foundation
import AppKit
import Combine

enum EngineStatus: Equatable {
    case idle
    case starting
    case running
    case failed(String)

    var isRunning: Bool { self == .running }
}

/// The single source of truth the UI observes. It owns both engines, polls
/// them on a timer, and merges their output into one list of `Transfer`s.
@MainActor
final class DownloadStore: ObservableObject {
    @Published private(set) var transfers: [Transfer] = []
    @Published private(set) var status: EngineStatus = .idle
    @Published var searchText: String = ""
    @Published var filter: SidebarFilter = .all
    @Published var categoryFilter: TransferCategory?

    private let configStore: ConfigStore
    var config: AppConfig { configStore.config }

    private var aria2: Aria2Engine
    private var torrent: TorrentEngine
    private var timer: Timer?
    private var addedAtCache: [String: Date] = [:]
    private var knownStates: [String: TransferState] = [:]
    private let sleepGuard = SleepGuard()

    init(configStore: ConfigStore) {
        self.configStore = configStore
        // Each engine instance gets a fresh token so a stale client cannot talk to a restarted engine.
        let token = AppConfig.randomToken()
        self.aria2 = Aria2Engine(secret: token)
        self.torrent = TorrentEngine(secret: token)
    }

    // MARK: Lifecycle

    func startEngines() async {
        status = .starting
        do {
            try await aria2.start(config: config)
        } catch {
            status = .failed(error.localizedDescription)
            Log.error("aria2 start failed: \(error.localizedDescription)")
            return
        }
        // The torrent helper is optional: if its binary is missing (e.g. a build
        // where it was not bundled) HTTP still works.
        do {
            try await torrent.start(config: config)
        } catch {
            Log.error("torrent helper start failed: \(error.localizedDescription)")
        }
        status = .running
        await applyLimits()
        await refresh()
        startPolling()
    }

    func stopEngines() {
        stopPolling()
        aria2.stop()
        torrent.stop()
        status = .idle
    }

    private func startPolling() {
        stopPolling()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: Refresh

    func refresh() async {
        guard status.isRunning else { return }

        var merged: [Transfer] = []

        if aria2.isRunning {
            do {
                let raw = try await aria2.allTransfers()
                merged.append(contentsOf: raw.compactMap { Aria2Mapping.transfer(from: $0) })
            } catch {
                Log.error("aria2 refresh failed: \(error.localizedDescription)")
            }
        }

        if torrent.isRunning {
            do {
                let raw = try await torrent.allTransfers()
                merged.append(contentsOf: raw.compactMap { TorrentMapping.transfer(from: $0) })
            } catch {
                Log.error("torrent refresh failed: \(error.localizedDescription)")
            }
        }

        // Restore stable "added at" timestamps and detect completions.
        for index in merged.indices {
            let id = merged[index].id
            if let existing = addedAtCache[id] {
                merged[index].addedAt = existing
            } else {
                addedAtCache[id] = merged[index].addedAt
            }
            handleTransition(id: id, to: merged[index])
        }

        transfers = merged
        manageSleep()
    }

    private func handleTransition(id: String, to transfer: Transfer) {
        let previous = knownStates[id]
        knownStates[id] = transfer.state
        guard let previous, previous != transfer.state else { return }
        if transfer.state == .completed {
            onCompleted(transfer)
        }
        if transfer.state == .error, transfer.errorMessage != nil {
            Log.error("transfer \(transfer.name) failed: \(transfer.errorMessage ?? "")")
        }
    }

    private func onCompleted(_ transfer: Transfer) {
        if config.notifyOnComplete {
            Notifier.shared.notifyCompleted(transfer)
        }
        // aria2 does not mark downloaded files with the quarantine attribute, so
        // we do it ourselves to keep Gatekeeper's check intact.
        if transfer.kind == .http, transfer.state == .completed {
            Quarantine.markQuarantined(transfer.targetPath, sourceURL: transfer.sourceURL)
        }
        if config.sleepOnQueueComplete, !hasActiveTransfers() {
            SleepGuard.scheduleSleepIfIdle()
        }
    }

    private func hasActiveTransfers() -> Bool {
        transfers.contains { $0.isActive }
    }

    private func manageSleep() {
        if config.preventSleepWhileActive && hasActiveTransfers() {
            sleepGuard.acquire()
        } else {
            sleepGuard.release()
        }
    }

    // MARK: Derived values

    var totalDownloadSpeed: Int64 {
        transfers.filter { $0.isActive }.reduce(0) { $0 + $1.downloadSpeed }
    }

    var activeCount: Int {
        transfers.filter { $0.isActive }.count
    }

    var freeDiskBytes: Int64 {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: config.downloadDirectory),
              let free = attrs[.systemFreeSize] as? NSNumber else { return 0 }
        return free.int64Value
    }

    var filtered: [Transfer] {
        transfers
            .filter { filter.matches($0) }
            .filter { categoryFilter == nil || $0.category == categoryFilter }
            .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
            .sorted { lhs, rhs in
                if lhs.isActive != rhs.isActive { return lhs.isActive }
                return lhs.addedAt > rhs.addedAt
            }
    }

    var counts: (all: Int, active: Int, finished: Int, torrents: Int) {
        let active = transfers.filter { $0.isActive }.count
        let finished = transfers.filter { $0.state == .completed }.count
        let torrents = transfers.filter { $0.kind == .torrent }.count
        return (transfers.count, active, finished, torrents)
    }

    func transfer(id: String?) -> Transfer? {
        guard let id else { return nil }
        return transfers.first { $0.id == id }
    }

    // MARK: Adding

    /// Routes any input to the right engine. Returns a human message for the UI.
    @discardableResult
    func add(_ input: AddRequest) async -> String? {
        switch input.kind {
        case .url:
            return await addHTTP(input)
        case .magnet:
            return await addMagnet(input.magnet)
        case .torrentFile:
            return await addTorrentFile(input.filePath)
        }
    }

    private func addHTTP(_ request: AddRequest) async -> String? {
        guard aria2.isRunning else { return "The download engine is not running." }
        var options: [String: Any] = [
            "dir": request.savePath ?? config.downloadDirectory,
            "split": String(config.splitCount),
            "max-connection-per-server": String(config.maxConnectionsPerServer),
            "continue": "true"
        ]
        if let filename = request.filename, !filename.isEmpty { options["out"] = filename }
        if let referer = request.referer { options["referer"] = referer }
        if let cookie = request.cookie, !cookie.isEmpty { options["header"] = ["Cookie: \(cookie)"] }
        if let userAgent = request.userAgent, !userAgent.isEmpty { options["user-agent"] = userAgent }
        if config.maxOverallDownloadKBps > 0 { options["max-download-limit"] = "\(config.maxOverallDownloadKBps)K" }

        do {
            _ = try await aria2.addURI(request.url, options: options)
            await refresh()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func addMagnet(_ magnet: String) async -> String? {
        guard torrent.isRunning else { return "The torrent engine is not running." }
        do {
            _ = try await torrent.addMagnet(magnet, savePath: config.downloadDirectory)
            await refresh()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func addTorrentFile(_ path: String) async -> String? {
        guard torrent.isRunning else { return "The torrent engine is not running." }
        do {
            _ = try await torrent.addTorrentFile(at: path, savePath: config.downloadDirectory)
            await refresh()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: Control

    func pause(_ transfer: Transfer) async {
        do {
            if transfer.kind == .http { try await aria2.pause(gid: transfer.id) }
            else { try await torrent.pause(id: transfer.id) }
            await refresh()
        } catch { Log.error("pause failed: \(error.localizedDescription)") }
    }

    func resume(_ transfer: Transfer) async {
        do {
            if transfer.kind == .http { try await aria2.unpause(gid: transfer.id) }
            else { try await torrent.resume(id: transfer.id) }
            await refresh()
        } catch { Log.error("resume failed: \(error.localizedDescription)") }
    }

    func toggle(_ transfer: Transfer) async {
        if transfer.state == .paused { await resume(transfer) } else { await pause(transfer) }
    }

    func remove(_ transfer: Transfer, deleteFiles: Bool) async {
        do {
            if transfer.kind == .http {
                _ = deleteFiles
                try await aria2.forceRemove(gid: transfer.id)
                try await aria2.purgeDownloadResult()
            } else {
                try await torrent.remove(id: transfer.id, deleteFiles: deleteFiles)
            }
            addedAtCache[transfer.id] = nil
            knownStates[transfer.id] = nil
            transfers.removeAll { $0.id == transfer.id }
        } catch { Log.error("remove failed: \(error.localizedDescription)") }
    }

    /// Re-submits a failed HTTP transfer using the address the browser extension
    /// last captured. aria2 cannot refresh an expired signed URL on its own, so
    /// the extension is the source of the fresh link.
    func retryWithFreshURL(_ transfer: Transfer, newURL: String, referer: String?, cookie: String?) async -> String? {
        guard transfer.kind == .http else { return "Retry with a fresh link applies to HTTP downloads." }
        await remove(transfer, deleteFiles: false)
        return await addHTTP(AddRequest(kind: .url, url: newURL, referer: referer, cookie: cookie, filename: transfer.name, savePath: transfer.savePath))
    }

    func pauseAll() async {
        try? await aria2.pauseAll()
        try? await torrent.pauseAll()
        await refresh()
    }

    func resumeAll() async {
        try? await aria2.unpauseAll()
        try? await torrent.resumeAll()
        await refresh()
    }

    func applyLimits() async {
        let down = config.speedLimitBytesPerSecond(up: false)
        let up = config.speedLimitBytesPerSecond(up: true)
        do {
            try await aria2.applyGlobalOptions([
                "max-overall-download-limit": "\(config.maxOverallDownloadKBps)K",
                "max-overall-upload-limit": "\(config.maxOverallUploadKBps)K"
            ])
        } catch { Log.error("aria2 limit apply failed: \(error.localizedDescription)") }
        if torrent.isRunning {
            do { try await torrent.applyLimits(downloadBytesPerSecond: down, uploadBytesPerSecond: up) }
            catch { Log.error("torrent limit apply failed: \(error.localizedDescription)") }
        }
    }

    // MARK: Detail

    func loadDetails(for transfer: Transfer) async -> TorrentInfo? {
        guard transfer.kind == .torrent, torrent.isRunning else { return nil }
        guard let raw = try? await torrent.details(id: transfer.id) else { return nil }
        return try? TorrentMapping.details(from: raw).0
    }

    func setFileSelection(_ transfer: Transfer, fileIndexes: [Int]) async {
        guard transfer.kind == .torrent else { return }
        try? await torrent.setFileSelection(id: transfer.id, fileIndexes: fileIndexes)
        await refresh()
    }

    // MARK: Finder helpers

    func revealInFinder(_ transfer: Transfer) {
        let path = transfer.targetPath
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: transfer.savePath))
        }
    }

    func open(_ transfer: Transfer) {
        let path = transfer.targetPath
        guard FileManager.default.fileExists(atPath: path) else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}

enum SidebarFilter: String, CaseIterable, Identifiable {
    case all, active, finished, torrents

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .active: return "Active"
        case .finished: return "Finished"
        case .torrents: return "Torrents"
        }
    }

    var symbol: String {
        switch self {
        case .all: return "square.stack"
        case .active: return "arrow.down.circle"
        case .finished: return "checkmark.circle"
        case .torrents: return "point.3.connected.trianglepath.dotted"
        }
    }

    func matches(_ transfer: Transfer) -> Bool {
        switch self {
        case .all: return true
        case .active: return transfer.isActive
        case .finished: return transfer.state == .completed
        case .torrents: return transfer.kind == .torrent
        }
    }
}

struct AddRequest {
    enum Kind { case url, magnet, torrentFile }

    var kind: Kind
    var url: String = ""
    var magnet: String = ""
    var filePath: String = ""
    var referer: String?
    var cookie: String?
    var userAgent: String?
    var filename: String?
    var savePath: String?

    static func url(_ value: String, referer: String? = nil, cookie: String? = nil, userAgent: String? = nil, filename: String? = nil, savePath: String? = nil) -> AddRequest {
        AddRequest(kind: .url, url: value, referer: referer, cookie: cookie, userAgent: userAgent, filename: filename, savePath: savePath)
    }

    static func magnet(_ value: String) -> AddRequest {
        AddRequest(kind: .magnet, magnet: value)
    }

    static func torrentFile(_ value: String) -> AddRequest {
        AddRequest(kind: .torrentFile, filePath: value)
    }
}
