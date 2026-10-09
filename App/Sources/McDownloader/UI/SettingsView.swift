import SwiftUI
import AppKit

/// Settings. Grouped by concern, with the browser-bridge token and port shown so
/// the extension can be configured by hand if auto-install is not used.
struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var configStore: ConfigStore
    @EnvironmentObject var tools: ToolManager

    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            SpeedSettings()
                .tabItem { Label("Bandwidth", systemImage: "speedometer") }
            TorrentSettings()
                .tabItem { Label("Torrents", systemImage: "point.3.connected.trianglepath.dotted") }
            BrowserSettings()
                .tabItem { Label("Browser", systemImage: "safari") }
            ToolsSettings()
                .tabItem { Label("Tools", systemImage: "wrench.and.screwdriver") }
        }
        // A comfortable fixed minimum: rows stay inside the frame instead of
        // pushing their controls past the window edge, and each pane scrolls.
        .frame(minWidth: 580, idealWidth: 580, minHeight: 480, idealHeight: 540, alignment: .top)
        .environmentObject(app)
        .environmentObject(configStore)
        .environmentObject(tools)
    }
}

/// One settings tab: a scrolling, padded column that never lets a form row grow
/// wider than the window. Shared by every tab so the fix lives in one place.
private struct SettingsPane<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView(.vertical) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct GeneralSettings: View {
    @EnvironmentObject var configStore: ConfigStore

    var body: some View {
        SettingsPane {
            Form {
                Section("Downloads") {
                    HStack {
                        Text("Save to")
                        Spacer()
                        Text((configStore.config.downloadDirectory as NSString).abbreviatingWithTildeInPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Choose…") { chooseFolder() }
                    }
                    Toggle("Notify when a download finishes", isOn: $configStore.config.notifyOnComplete)
                    Toggle("Prevent sleep while downloading", isOn: $configStore.config.preventSleepWhileActive)
                    Toggle("Sleep when the queue finishes", isOn: $configStore.config.sleepOnQueueComplete)
                }
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            configStore.config.downloadDirectory = url.path
        }
    }
}

private struct SpeedSettings: View {
    @EnvironmentObject var configStore: ConfigStore
    @EnvironmentObject var app: AppState

    var body: some View {
        SettingsPane {
            Form {
                Section("HTTP") {
                    Stepper("Parallel connections per file: \(configStore.config.splitCount)",
                            value: $configStore.config.splitCount, in: 1...16)
                    Stepper("Connections per server: \(configStore.config.maxConnectionsPerServer)",
                            value: $configStore.config.maxConnectionsPerServer, in: 1...16)
                }
                Section("Limits (0 = unlimited)") {
                    HStack {
                        Text("Download")
                        Spacer()
                        TextField("KB/s", value: $configStore.config.maxOverallDownloadKBps, format: .number)
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("KB/s").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Upload")
                        Spacer()
                        TextField("KB/s", value: $configStore.config.maxOverallUploadKBps, format: .number)
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("KB/s").foregroundStyle(.secondary)
                    }
                }
                Button("Apply limits now") {
                    Task { await app.store.applyLimits() }
                }
            }
        }
    }
}

private struct TorrentSettings: View {
    @EnvironmentObject var configStore: ConfigStore

    var body: some View {
        SettingsPane {
            Form {
                Section("Seeding") {
                    Toggle("Seed after the download completes", isOn: $configStore.config.seedAfterComplete)
                    HStack {
                        Text("Stop at ratio")
                        Spacer()
                        TextField("", value: $configStore.config.seedingRatioLimit, format: .number)
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    HStack {
                        Text("Stop after (minutes)")
                        Spacer()
                        TextField("", value: $configStore.config.seedingTimeLimitMinutes, format: .number)
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }
                Section("Discovery") {
                    Toggle("Add public trackers to new magnets", isOn: $configStore.config.addPublicTrackers)
                }
            }
        }
    }
}

private struct BrowserSettings: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var configStore: ConfigStore
    @State private var copied = false
    @State private var connectMessage: String?

    var body: some View {
        SettingsPane {
            Form {
                Section("Browser extension") {
                    Text("Do this once. After that the extension talks to the app on its own: no port, no token.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("1.")
                        Button("Connect browser") { connect() }
                        Text("installs the native host and opens the extension folder in Finder.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("2.")
                        Text("In the browser, open `chrome://extensions`, turn on Developer mode, click Load unpacked, and pick the extension folder.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let connectMessage {
                        Text(connectMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(nativeHostStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("If the browser was already open, quit and reopen it once.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section("Connection") {
                    HStack {
                        Text("Transport")
                        Spacer()
                        Text(nativeHostInstalled ? "Native host" : "Local bridge")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Status")
                        Spacer()
                        let info = app.bridgeInfo()
                        Text(info.running ? "Listening on 127.0.0.1:\(info.port)" : "Not running")
                            .foregroundStyle(info.running ? Theme.success : .secondary)
                    }
                }

                DisclosureGroup("Manual bridge (advanced)") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Accept downloads from the browser extension", isOn: $configStore.config.browserBridgeEnabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .onChange(of: configStore.config.browserBridgeEnabled) { _, _ in app.restartBridge() }
                        HStack {
                            Text("Port")
                            Spacer()
                            TextField("", value: $configStore.config.browserBridgePort, format: .number)
                                .labelsHidden()
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                                .onSubmit { app.restartBridge() }
                        }
                        Text("Paste this token into the extension's Options page:")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Text(configStore.config.browserBridgeToken)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button(copied ? "Copied" : "Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(configStore.config.browserBridgeToken, forType: .string)
                                copied = true
                                Task { try? await Task.sleep(nanoseconds: 1_500_000_000); copied = false }
                            }
                        }
                    }
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var nativeHostInstalled: Bool {
        !NativeHost.installedBrowsers().isEmpty
    }

    private var nativeHostStatus: String {
        let installed = NativeHost.installedBrowsers()
        if installed.isEmpty {
            let absent = NativeHost.absentBrowsers()
            return absent.isEmpty
                ? "Native host not installed."
                : "Native host not installed (found \(absent.joined(separator: ", ")))."
        }
        return "Native host installed for \(installed.joined(separator: ", "))."
    }

    private func connect() {
        let written = NativeHost.install()
        NativeHost.revealExtensionAndOpenBrowser()
        if written.isEmpty {
            connectMessage = "No Chromium browser found to configure. The manual bridge below still works."
        } else {
            connectMessage = "Done. Now load the extension in the browser, once."
        }
    }
}

private struct ToolsSettings: View {
    @EnvironmentObject var tools: ToolManager

    var body: some View {
        SettingsPane {
            Form {
                Section("Video grabber") {
                    HStack {
                        Text("yt-dlp")
                        Spacer()
                        if let version = tools.ytDlpVersion {
                            Text("installed · \(version)").foregroundStyle(.secondary)
                        } else {
                            Text("not installed").foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Text("ffmpeg")
                        Spacer()
                        Text(tools.ffmpegAvailable ? "installed" : "not installed").foregroundStyle(.secondary)
                    }
                    Button(tools.isInstalling ? "Installing…" : (tools.ytDlpVersion == nil ? "Install yt-dlp" : "Update yt-dlp")) {
                        Task { await tools.installOrUpdateYtDlp() }
                    }
                    .disabled(tools.isInstalling)
                    if let error = tools.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Theme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("yt-dlp downloads to \(tools.toolsDirectory.path)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
