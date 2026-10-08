import Foundation

/// Categories by file extension. Used only to choose a default folder and an
/// icon; a user can always override the destination.
enum CategoryRules {
    private static let map: [String: TransferCategory] = {
        var m: [String: TransferCategory] = [:]
        for ext in ["mp4", "mkv", "mov", "avi", "webm", "m4v", "flv", "wmv", "mpg", "mpeg"] { m[ext] = .video }
        for ext in ["mp3", "m4a", "flac", "wav", "aac", "ogg", "opus", "wma"] { m[ext] = .audio }
        for ext in ["pdf", "doc", "docx", "txt", "rtf", "md", "epub", "xls", "xlsx", "ppt", "pptx", "csv"] { m[ext] = .documents }
        for ext in ["zip", "rar", "7z", "tar", "gz", "bz2", "xz", "tgz", "iso", "dmg"] { m[ext] = .archives }
        for ext in ["app", "pkg", "mpkg"] { m[ext] = .applications }
        return m
    }()

    static func category(for filename: String) -> TransferCategory {
        let ext = (filename as NSString).pathExtension.lowercased()
        return map[ext] ?? .other
    }

    static func category(forURL url: String) -> TransferCategory {
        guard let name = URL(string: url)?.lastPathComponent, !name.isEmpty else { return .other }
        return category(for: name)
    }
}

/// Best-effort filename from a URL, used before the engine reports a real name.
enum NameRules {
    static func suggestedName(for urlString: String) -> String {
        guard let url = URL(string: urlString) else { return "download" }
        var name = url.lastPathComponent
        if name.isEmpty { name = url.host ?? "download" }
        if let dot = name.range(of: ".", options: .backwards),
           dot.lowerBound == name.startIndex {
            name = "download"
        }
        if !name.contains(".") {
            // No extension in the path; keep the path component, the engine will
            // correct it with Content-Disposition once the transfer starts.
            return name.isEmpty ? "download" : name
        }
        return name
    }
}
