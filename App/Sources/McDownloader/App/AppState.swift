import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// App-level coordinator. It owns the store, the tool manager and the browser
/// bridge, and it centralises the actions that several views trigger (add,
/// open a file, open a magnet).
@MainActor
final class AppState: ObservableObject {
    let configStore: ConfigStore
    let store: DownloadStore
    let tools = ToolManager()

    @Published var isShowingAddSheet = false
    @Published var banner: Banner?
    @Published var selectedTransferID: String?
    @Published var showInspector = true

    private var bridge: BrowserBridge?
    private var started = false

    struct Banner: Identifiable, Equatable {
        enum Kind { case info, error }
        let id = UUID()
        var kind: Kind
        var message: String
    }

    init(configStore: ConfigStore) {
        self.configStore = configStore
        self.store = DownloadStore(configStore: configStore)
    }

    func start() {
        guard !started else { return }
        started = true
        Notifier.shared.requestAuthorization()
        Task { await store.startEngines() }
        startBridge()
        observeURLs()
    }

    func shutdown() {
        store.stopEngines()
        bridge?.stop()
    }

    // MARK: Browser bridge

    private func startBridge() {
        guard configStore.config.browserBridgeEnabled else { return }
        let bridge = BrowserBridge(port: configStore.config.browserBridgePort, token: configStore.config.browserBridgeToken)
        bridge.onAdd = { [weak self] request in
            Task { @MainActor in await self?.handleBrowserAdd(request) }
        }
        bridge.start()
        self.bridge = bridge
    }

    private func handleBrowserAdd(_ request: AddRequest) async {
        let message = await store.add(request)
        if let message { present(.error, message) }
    }

    func bridgeInfo() -> (running: Bool, port: Int, token: String) {
        (bridge?.isRunning ?? false, configStore.config.browserBridgePort, configStore.config.browserBridgeToken)
    }

    func restartBridge() {
        bridge?.stop()
        bridge = nil
        startBridge()
    }

    // MARK: URL / file intake

    private func observeURLs() {
        NotificationCenter.default.addObserver(forName: .mcOpenURL, object: nil, queue: .main) { [weak self] notification in
            guard let url = notification.object as? URL else { return }
            Task { @MainActor in await self?.handleIncoming(url: url) }
        }
    }

    func handleIncoming(url: URL) async {
        if url.isFileURL {
            if url.pathExtension.lowercased() == "torrent" {
                let message = await store.add(.torrentFile(url.path))
                if let message { present(.error, message) } else { present(.info, "Torrent added.") }
            }
            return
        }
        switch InputClassifier.classify(url.absoluteString) {
        case .magnet(let magnet):
            let message = await store.add(.magnet(magnet))
            if let message { present(.error, message) } else { present(.info, "Magnet added.") }
        case .url(let value):
            let message = await store.add(.url(value))
            if let message { present(.error, message) } else { present(.info, "Download added.") }
        case .torrentFile(let path):
            let message = await store.add(.torrentFile(path))
            if let message { present(.error, message) } else { present(.info, "Torrent added.") }
        case .unknown:
            present(.error, "That does not look like a link McDownloader can use.")
        }
    }

    func openTorrentFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "torrent") ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a .torrent file"
        if panel.runModal() == .OK, let url = panel.url {
            Task { await handleIncoming(url: url) }
        }
    }

    /// The Add sheet funnel: one field, classified and routed.
    func submitAdd(text: String, savePath: String?) async {
        let result = InputClassifier.classify(text)
        let request: AddRequest
        switch result {
        case .url(let value):
            request = AddRequest.url(value, savePath: savePath)
        case .magnet(let value):
            request = AddRequest.magnet(value)
        case .torrentFile(let path):
            request = AddRequest.torrentFile(path)
        case .unknown:
            present(.error, "Paste an http(s) link, a magnet link, or a path to a .torrent file.")
            return
        }
        // A .torrent coming from the sheet needs magnet semantics folded in;
        // store.add already routes by kind, so this is one call.
        let message = await store.add(request)
        if let message { present(.error, message) } else { present(.info, "Added to the queue.") }
    }

    func pasteFromClipboard() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    // MARK: Banners

    func present(_ kind: Banner.Kind, _ message: String) {
        banner = Banner(kind: kind, message: message)
        let current = banner
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if self.banner == current { self.banner = nil }
        }
    }

    func revealWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    // MARK: Diagnostics

    func copyDiagnostics() {
        let store = self.store
        let lines = [
            "McDownloader \(AppInfo.version) (\(AppInfo.build))",
            "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Engine status: \(store.status)",
            "aria2c: \(EngineLocator.aria2c()?.path ?? "not found")",
            "torrent helper: \(EngineLocator.torrentHelper()?.path ?? "not found")",
            "yt-dlp: \(EngineLocator.ytDlp()?.path ?? "not installed")",
            "Transfers: \(store.transfers.count)",
            "Log: \(AppPaths.engineLogFile.path)"
        ]
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        present(.info, "Diagnostics copied to the clipboard.")
    }
}
