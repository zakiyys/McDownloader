import Foundation

/// Grabs video/audio with yt-dlp. We wrap the binary rather than the Python
/// module so the app has one dependency and one update path.
final class MediaGrabber {
    struct Format: Identifiable, Hashable {
        var id: String
        var label: String
        var isAudioOnly: Bool
    }

    /// Lists the real formats yt-dlp reports for a page. Empty when yt-dlp is
    /// not installed, so the UI can prompt to install it.
    static func listFormats(pageURL: String) async -> [Format] {
        guard let ytDlp = EngineLocator.ytDlp() else { return [] }
        let output = await run(executable: ytDlp, arguments: ["-J", "--no-warnings", pageURL], timeout: 60)
        guard let data = output.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let formats = object["formats"] as? [[String: Any]] else {
            return []
        }
        return formats.compactMap { format in
            guard let formatID = format["format_id"] as? String else { return nil }
            let ext = format["ext"] as? String ?? ""
            let vcodec = format["vcodec"] as? String ?? ""
            let height = (format["height"] as? NSNumber)?.intValue
            let abr = (format["abr"] as? NSNumber)?.intValue
            let isAudioOnly = vcodec == "none"
            var parts: [String] = [formatID]
            if let height { parts.append("\(height)p") }
            if isAudioOnly, let abr { parts.append("\(abr)kbps") }
            parts.append(ext)
            let note = (format["format_note"] as? String) ?? ""
            if !note.isEmpty { parts.append(note) }
            return Format(id: formatID, label: parts.joined(separator: " · "), isAudioOnly: isAudioOnly)
        }
    }

    /// Runs a download into the destination folder. Merges to mp4 when ffmpeg
    /// is present; otherwise lets yt-dlp pick a single-file format.
    static func download(pageURL: String, format: Format, to directory: String, ffmpegPath: String?) async -> Result<String, Error> {
        guard let ytDlp = EngineLocator.ytDlp() else {
            return .failure(EngineError.fileMissing("yt-dlp is not installed"))
        }
        var arguments = ["--no-warnings", "--newline", "-P", directory]
        if !format.isAudioOnly {
            arguments += ["-f", format.id]
            if let ffmpegPath {
                arguments += ["--ffmpeg-location", ffmpegPath, "--merge-output-format", "mp4"]
            }
        } else {
            arguments += ["-f", format.id, "-x"]
            if let ffmpegPath { arguments += ["--ffmpeg-location", ffmpegPath] }
        }
        arguments.append(pageURL)

        let output = await run(executable: ytDlp, arguments: arguments, timeout: 3600)
        return .success(output)
    }

    private static func run(executable: URL, arguments: [String], timeout: TimeInterval) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: "error: \(error.localizedDescription)")
                    return
                }
                let deadline = Date().addingTimeInterval(timeout)
                while process.isRunning && Date() < deadline { usleep(150_000) }
                if process.isRunning { process.terminate() }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
            }
        }
    }
}
