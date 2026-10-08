import Foundation
import Security

/// User-adjustable settings, persisted as JSON in Application Support.
struct AppConfig: Codable, Equatable {
    var downloadDirectory: String
    var maxConnectionsPerServer: Int
    var splitCount: Int
    var maxOverallDownloadKBps: Int
    var maxOverallUploadKBps: Int
    var seedingRatioLimit: Double
    var seedingTimeLimitMinutes: Int
    var seedAfterComplete: Bool
    var addPublicTrackers: Bool
    var sleepOnQueueComplete: Bool
    var notifyOnComplete: Bool
    var preventSleepWhileActive: Bool
    var browserBridgeEnabled: Bool
    var browserBridgePort: Int
    var browserBridgeToken: String
    var autoUpdateYtDlp: Bool

    static func `default`() -> AppConfig {
        AppConfig(
            downloadDirectory: AppPaths.downloadsDir.path,
            maxConnectionsPerServer: 16,
            splitCount: 16,
            maxOverallDownloadKBps: 0,
            maxOverallUploadKBps: 0,
            seedingRatioLimit: 1.0,
            seedingTimeLimitMinutes: 60,
            seedAfterComplete: true,
            addPublicTrackers: true,
            sleepOnQueueComplete: false,
            notifyOnComplete: true,
            preventSleepWhileActive: true,
            browserBridgeEnabled: true,
            browserBridgePort: 6847,
            browserBridgeToken: Self.randomToken(),
            autoUpdateYtDlp: true
        )
    }

    static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            // Fall back to a UUID; tokens are localhost-only, this is a guard, not a secret store.
            return UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    func speedLimitBytesPerSecond(up: Bool) -> Int64 {
        let kbps = up ? maxOverallUploadKBps : maxOverallDownloadKBps
        return Int64(max(0, kbps)) * 1000
    }
}
