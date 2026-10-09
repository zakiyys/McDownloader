import Foundation

/// Owns the aria2c child process and speaks its JSON-RPC API.
/// aria2 handles every non-BitTorrent transfer: HTTP, HTTPS and FTP.
final class Aria2Engine {
    private let port: Int
    let secret: String
    private var process: Process?
    private var rpc: RPCClient { RPCClient(endpoint: URL(string: "http://127.0.0.1:\(port)/jsonrpc")!, secret: secret) }

    private(set) var isRunning = false

    init(port: Int = 6849, secret: String) {
        self.port = port
        self.secret = secret
    }

    // MARK: Lifecycle

    func start(config: AppConfig) async throws {
        try AppPaths.ensureDirectories()
        // aria2 aborts at startup when --input-file points at a file that does
        // not exist yet, so seed an empty session on a fresh install.
        AppPaths.ensureSessionFile()
        guard let binary = EngineLocator.aria2c() else {
            throw EngineError.notRunning
        }
        if isRunning { return }

        let proc = Process()
        proc.executableURL = binary
        proc.arguments = arguments(config: config)
        proc.terminationHandler = { [weak self] finished in
            self?.isRunning = false
            Log.error("aria2c exited (status \(finished.terminationStatus))")
        }
        // aria2 logs to --log once it is up, but a bad flag or a missing
        // directory makes it die before the log file exists. Keep its stderr so
        // those failures are not silent.
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = AppPaths.engineStderrHandle() ?? FileHandle.nullDevice

        do {
            try proc.run()
        } catch {
            throw EngineError.unreachable("failed to launch aria2c: \(error.localizedDescription)")
        }
        process = proc
        isRunning = true
        Log.info("aria2c started pid=\(proc.processIdentifier) port=\(port)")

        try await waitForReady()
    }

    func stop() {
        guard let process, process.isRunning else { return }
        process.terminate()
        // Give aria2 a moment to save its session, then hard-stop if needed.
        let deadline = Date().addingTimeInterval(3)
        while process.isRunning && Date() < deadline { usleep(100_000) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        isRunning = false
    }

    private func arguments(config: AppConfig) -> [String] {
        [
            "--enable-rpc=true",
            "--rpc-listen-all=false",
            "--rpc-listen-port=\(port)",
            "--rpc-secret=\(secret)",
            "--rpc-allow-origin-all=true",
            "--no-conf=true",
            "--continue=true",
            "--max-concurrent-downloads=5",
            "--split=\(max(1, config.splitCount))",
            "--max-connection-per-server=\(max(1, config.maxConnectionsPerServer))",
            "--min-split-size=1M",
            "--file-allocation=none",
            "--dir=\(config.downloadDirectory)",
            "--auto-file-renaming=true",
            "--allow-overwrite=false",
            "--save-session=\(AppPaths.aria2SessionFile.path)",
            "--save-session-interval=30",
            "--auto-save-interval=30",
            "--input-file=\(AppPaths.aria2SessionFile.path)",
            "--log=\(AppPaths.aria2LogFile.path)",
            "--log-level=warn",
            "--quiet=true",
            "--summary-interval=0",
            "--download-result=hide",
            "--follow-metalink=true",
            "--check-certificate=true"
        ]
    }

    private func waitForReady() async throws {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            // If the process already died, retrying the RPC is pointless: say why.
            if let process, !process.isRunning {
                let detail = AppPaths.engineStderrTail()
                throw EngineError.unreachable(
                    "aria2c exited during startup (status \(process.terminationStatus))"
                    + (detail.map { ": \($0)" } ?? "")
                )
            }
            do {
                _ = try await rpc.call("aria2.getVersion")
                return
            } catch {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        throw EngineError.unreachable("aria2 did not become ready")
    }

    // MARK: Queries

    /// Returns every download aria2 knows about, in one pass.
    func allTransfers() async throws -> [[String: Any]] {
        async let active = rpc.call("aria2.tellActive", params: [keyFields])
        async let waiting = rpc.call("aria2.tellWaiting", params: [0, 1000, keyFields])
        async let stopped = rpc.call("aria2.tellStopped", params: [0, 1000, keyFields])
        let (a, w, s) = try await (active, waiting, stopped)
        let activeList = a as? [[String: Any]] ?? []
        let waitingList = w as? [[String: Any]] ?? []
        let stoppedList = s as? [[String: Any]] ?? []
        return activeList + waitingList + stoppedList
    }

    private var keyFields: [String] {
        [
            "gid", "status", "totalLength", "completedLength", "downloadSpeed",
            "uploadSpeed", "connections", "numSeeders", "seeder", "errorCode",
            "errorMessage", "dir", "files", "bittorrent", "infoHash", "followedBy",
            "belongsTo", "verifiedLength", "verifyIntegrityPending"
        ]
    }

    func status(gid: String) async throws -> [String: Any] {
        guard let result = try await rpc.call("aria2.tellStatus", params: [gid, keyFields]) as? [String: Any] else {
            throw EngineError.badResponse("empty status for \(gid)")
        }
        return result
    }

    // MARK: Mutations

    @discardableResult
    func addURI(_ uri: String, options: [String: Any]) async throws -> String {
        let result = try await rpc.call("aria2.addUri", params: [[uri], options])
        guard let gid = result as? String else { throw EngineError.badResponse("no gid returned") }
        return gid
    }

    func pause(gid: String) async throws { _ = try await rpc.call("aria2.pause", params: [gid]) }
    func unpause(gid: String) async throws { _ = try await rpc.call("aria2.unpause", params: [gid]) }
    func remove(gid: String) async throws { _ = try await rpc.call("aria2.remove", params: [gid]) }
    func forceRemove(gid: String) async throws { _ = try await rpc.call("aria2.forceRemove", params: [gid]) }
    func pauseAll() async throws { _ = try await rpc.call("aria2.pauseAll") }
    func unpauseAll() async throws { _ = try await rpc.call("aria2.unpauseAll") }
    func purgeDownloadResult() async throws { _ = try await rpc.call("aria2.purgeDownloadResult") }

    func applyGlobalOptions(_ options: [String: String]) async throws {
        _ = try await rpc.call("aria2.changeGlobalOption", params: [options])
    }

    /// Copy a completed file to its final destination if the user set a custom
    /// folder that differs from the engine's working directory.
    func moveFile(gid: String, to path: String) async throws {
        _ = try await rpc.call("aria2.changeOption", params: [gid, ["dir": path]])
    }
}
