import Foundation
import AppKit

/// Installs the Native Messaging host manifest that lets a Chromium browser
/// talk to the app without a port or a token to copy.
///
/// Chrome's rule, not ours: an extension can only reach a native host when a
/// manifest matching this host's *fixed* name sits in the browser's profile
/// folder and lists the extension's ID in `allowed_origins`. The extension's ID
/// is made stable by the `key` field in `Extension/manifest.json`, so the value
/// below is the one the browser will always compute for our extension.
///
/// The host itself (`mcdownloader-host`) is a small helper next to the app
/// binary that forwards messages to the app's local HTTP bridge. No port or
/// token ever reaches the user.
enum NativeHost {
    /// Must be lowercase, match the manifest file name, and match the name the
    /// extension passes to `chrome.runtime.connectNative`. Keep in sync with
    /// `Extension/background.js`.
    static let hostName = "io.github.zakiyys.mcdownloader"

    /// The extension's stable ID, derived from the public `key` in
    /// `Extension/manifest.json`. Keep the two in sync.
    static let extensionID = "glgiiiccekihidjecfigjpcdfckmgmgd"

    static let executableName = "mcdownloader-host"

    /// Chromium browsers on macOS, by the folder each keeps under Application
    /// Support. Only the ones actually present on this Mac get a manifest.
    private static let browsers: [(name: String, supportPath: String)] = [
        ("Google Chrome", "Google/Chrome"),
        ("Google Chrome Beta", "Google/Chrome Beta"),
        ("Google Chrome Canary", "Google/Chrome Canary"),
        ("Chromium", "Chromium"),
        ("Microsoft Edge", "Microsoft Edge"),
        ("Brave", "BraveSoftware/Brave-Browser"),
        ("Vivaldi", "Vivaldi"),
    ]

    struct Installation: Identifiable {
        let id = UUID()
        let browser: String
        let path: URL
    }

    /// Absolute path to the host binary shipped inside the app bundle.
    static var hostBinaryURL: URL? {
        guard let dir = Bundle.main.executableURL?.deletingLastPathComponent() else { return nil }
        let url = dir.appendingPathComponent(executableName)
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    static func isBrowserPresent(_ supportPath: String) -> Bool {
        FileManager.default.fileExists(atPath: browserSupportDir(supportPath).path)
    }

    static func isInstalled(_ supportPath: String) -> Bool {
        FileManager.default.fileExists(atPath: manifestURL(supportPath).path)
    }

    /// Writes the manifest for every Chromium browser present on this Mac.
    /// Returns what was written so the UI can report it.
    @discardableResult
    static func install() -> [Installation] {
        guard let binary = hostBinaryURL else {
            Log.error("native host: \(executableName) not found next to the app binary")
            return []
        }
        var written: [Installation] = []
        for browser in browsers where isBrowserPresent(browser.supportPath) {
            do {
                let dir = manifestURL(browser.supportPath).deletingLastPathComponent()
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try manifestData(binary: binary).write(to: manifestURL(browser.supportPath), options: .atomic)
                written.append(Installation(browser: browser.name, path: manifestURL(browser.supportPath)))
            } catch {
                Log.error("native host: could not write manifest for \(browser.name): \(error.localizedDescription)")
            }
        }
        Log.info("native host: installed for \(written.map(\.browser).joined(separator: ", "))")
        return written
    }

    static func uninstall() {
        for browser in browsers {
            try? FileManager.default.removeItem(at: manifestURL(browser.supportPath))
        }
    }

    /// Names of the installed browsers, for the settings status line.
    static func installedBrowsers() -> [String] {
        browsers.filter { isBrowserPresent($0.supportPath) && isInstalled($0.supportPath) }.map(\.name)
    }

    static func absentBrowsers() -> [String] {
        browsers.filter { isBrowserPresent($0.supportPath) && !isInstalled($0.supportPath) }.map(\.name)
    }

    /// Opens the extension page in Chrome and reveals the bundled extension
    /// folder, so the one remaining step (Load unpacked) is two clicks.
    static func revealExtensionAndOpenBrowser() {
        if let ext = Bundle.main.resourceURL?.appendingPathComponent("extension"),
           FileManager.default.fileExists(atPath: ext.path) {
            NSWorkspace.shared.activateFileViewerSelecting([ext])
        }
        if let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome"),
           let url = URL(string: "chrome://extensions") {
            NSWorkspace.shared.open([url], withApplicationAt: chrome,
                                    configuration: NSWorkspace.OpenConfiguration(),
                                    completionHandler: nil)
        }
    }

    // MARK: - Paths

    private static func browserSupportDir(_ supportPath: String) -> URL {
        appSupport.appendingPathComponent(supportPath, isDirectory: true)
    }

    private static func manifestURL(_ supportPath: String) -> URL {
        browserSupportDir(supportPath)
            .appendingPathComponent("NativeMessagingHosts", isDirectory: true)
            .appendingPathComponent("\(hostName).json")
    }

    private static var appSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    }

    private static func manifestData(binary: URL) -> Data {
        let manifest: [String: Any] = [
            "name": hostName,
            "description": "McDownloader browser bridge",
            "path": binary.path,
            "type": "stdio",
            "allowed_origins": ["chrome-extension://\(extensionID)/"],
        ]
        return (try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }
}
