import Foundation

/// Human-readable formatting for sizes, speeds and durations.
/// Kept in one place so every column in the UI formats the same way.
enum Fmt {
    static func bytes(_ value: Int64) -> String {
        guard value > 0 else { return "0 B" }
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var size = Double(value)
        var index = 0
        while size >= 1000 && index < units.count - 1 {
            size /= 1000
            index += 1
        }
        let decimals = size >= 100 || index == 0 ? 0 : 1
        return String(format: "%.\(decimals)f %@", size, units[index])
    }

    static func speed(_ bytesPerSecond: Int64) -> String {
        guard bytesPerSecond > 0 else { return "—" }
        return bytes(bytesPerSecond) + "/s"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        if seconds < 60 { return String(format: "%.0fs", seconds) }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%dh %02dm", h, m) }
        return String(format: "%dm %02ds", m, s)
    }

    static func eta(remaining: Int64, speed: Int64) -> String {
        guard speed > 0, remaining > 0 else { return "—" }
        return duration(Double(remaining) / Double(speed))
    }

    static func percent(_ fraction: Double) -> String {
        String(format: "%.1f%%", max(0, min(1, fraction)) * 100)
    }

    static func count(_ value: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }
}
