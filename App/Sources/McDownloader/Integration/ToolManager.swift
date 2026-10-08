import Foundation

/// Manages the optional yt-dlp and ffmpeg tools. They are downloaded on first
/// use into Application Support, never bundled, so the app stays small. yt-dlp
/// ships as a self-contained binary, so installation is a single download.
/// Observable and main-actor bound because it drives SwiftUI directly.
@MainActor
final class ToolManager: ObservableObject {
    @Published private(set) var ytDlpVersion: String?
    @Published private(set) var ffmpegAvailable = false
    @Published private(set) var isInstalling = false
    @Published var lastError: String?

    private let ytDlpURL = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos"

    init() {
        refreshState()
    }

    func refreshState() {
        ytDlpVersion = EngineLocator.ytDlp().flatMap { version(of: $0, arguments: ["--version"]) }
        ffmpegAvailable = EngineLocator.ffmpeg() != nil
    }

    private func version(of binary: URL, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }

    /// Installs or updates yt-dlp. Network only, no system changes.
    func installOrUpdateYtDlp() async {
        isInstalling = true
        lastError = nil
        defer {
            isInstalling = false
            refreshState()
        }
        do {
            try AppPaths.ensureDirectories()
            let tools = EngineLocator.toolsDir()
            if !FileManager.default.fileExists(atPath: tools.path) {
                try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
            }
            let destination = tools.appendingPathComponent("yt-dlp")

            guard let url = URL(string: ytDlpURL) else { return }
            let (temp, _) = try await URLSession.shared.download(from: url)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: temp, to: destination)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
            Log.info("yt-dlp installed at \(destination.path)")
        } catch {
            lastError = error.localizedDescription
            Log.error("yt-dlp install failed: \(error.localizedDescription)")
        }
    }

    var toolsDirectory: URL { EngineLocator.toolsDir() }
    var ytDlpPath: String? { EngineLocator.ytDlp()?.path }
    var ffmpegPath: String? { EngineLocator.ffmpeg()?.path }
}
