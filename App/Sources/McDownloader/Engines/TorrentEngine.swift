import Foundation

/// Owns the libtorrent helper process. The helper speaks the same JSON-RPC
/// envelope as aria2, so the store treats both engines identically.
final class TorrentEngine {
    private let port: Int
    private let secret: String
    private var process: Process?

    private(set) var isRunning = false
    private var rpc: RPCClient { RPCClient(endpoint: URL(string: "http://127.0.0.1:\(port)/jsonrpc")!, secret: secret) }

    init(port: Int = 6850, secret: String) {
        self.port = port
        self.secret = secret
    }

    func start(config: AppConfig) async throws {
        try AppPaths.ensureDirectories()
        guard let binary = EngineLocator.torrentHelper() else {
            // Not a hard failure: the app still does HTTP. The store degrades
            // to "torrent engine unavailable" instead of refusing to launch.
            throw EngineError.notRunning
        }
        if isRunning { return }

        let proc = Process()
        proc.executableURL = binary
        proc.arguments = [
            "--port=\(port)",
            "--secret=\(secret)",
            "--save-path=\(config.downloadDirectory)",
            "--state-dir=\(AppPaths.torrentStateDir.path)",
            "--seed=" + (config.seedAfterComplete ? "1" : "0"),
            "--ratio-limit=\(config.seedingRatioLimit)",
            "--time-limit=\(config.seedingTimeLimitMinutes)",
            "--listen-port=6881"
        ]
        proc.terminationHandler = { [weak self] finished in
            self?.isRunning = false
            Log.error("torrent helper exited (status \(finished.terminationStatus))")
        }
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = AppPaths.engineStderrHandle(named: "torrentd") ?? FileHandle.nullDevice

        do {
            try proc.run()
        } catch {
            throw EngineError.unreachable("failed to launch torrent helper: \(error.localizedDescription)")
        }
        process = proc
        isRunning = true
        Log.info("torrent helper started pid=\(proc.processIdentifier) port=\(port)")

        try await waitForReady()
    }

    func stop() {
        guard let process, process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(4)
        while process.isRunning && Date() < deadline { usleep(100_000) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        isRunning = false
    }

    private func waitForReady() async throws {
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            do {
                _ = try await rpc.call("torrent.version")
                return
            } catch {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        throw EngineError.unreachable("torrent helper did not become ready")
    }

    func allTransfers() async throws -> [[String: Any]] {
        guard let result = try await rpc.call("torrent.list") as? [[String: Any]] else {
            throw EngineError.badResponse("torrent.list did not return a list")
        }
        return result
    }

    func details(id: String) async throws -> [String: Any] {
        guard let result = try await rpc.call("torrent.detail", params: [id]) as? [String: Any] else {
            throw EngineError.badResponse("empty torrent detail for \(id)")
        }
        return result
    }

    @discardableResult
    func addMagnet(_ uri: String, savePath: String) async throws -> String {
        let result = try await rpc.call("torrent.addMagnet", params: [uri, ["save_path": savePath]])
        guard let id = result as? String else { throw EngineError.badResponse("no id returned") }
        return id
    }

    @discardableResult
    func addTorrentFile(at path: String, savePath: String) async throws -> String {
        let result = try await rpc.call("torrent.addTorrent", params: [path, ["save_path": savePath]])
        guard let id = result as? String else { throw EngineError.badResponse("no id returned") }
        return id
    }

    func pause(id: String) async throws { _ = try await rpc.call("torrent.pause", params: [id]) }
    func resume(id: String) async throws { _ = try await rpc.call("torrent.resume", params: [id]) }
    func remove(id: String, deleteFiles: Bool) async throws {
        _ = try await rpc.call("torrent.remove", params: [id, ["delete_files": deleteFiles]])
    }
    func pauseAll() async throws { _ = try await rpc.call("torrent.pauseAll") }
    func resumeAll() async throws { _ = try await rpc.call("torrent.resumeAll") }

    func setFileSelection(id: String, fileIndexes: [Int]) async throws {
        _ = try await rpc.call("torrent.setFileSelection", params: [id, ["files": fileIndexes]])
    }

    func applyLimits(downloadBytesPerSecond: Int64, uploadBytesPerSecond: Int64) async throws {
        _ = try await rpc.call("torrent.setLimits", params: [[
            "download": downloadBytesPerSecond,
            "upload": uploadBytesPerSecond
        ]])
    }
}
