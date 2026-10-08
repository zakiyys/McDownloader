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
        .frame(width: 520)
        .padding(16)
        .environmentObject(app)
        .environmentObject(configStore)
        .environmentObject(tools)
    }
}

private struct GeneralSettings: View {
    @EnvironmentObject var configStore: ConfigStore

    var body: some View {
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
                        .frame(width: 90)
                        .multilineTextAlignment(.trailing)
                    Text("KB/s").foregroundStyle(.secondary)
                }
                HStack {
                    Text("Upload")
                    Spacer()
                    TextField("KB/s", value: $configStore.config.maxOverallUploadKBps, format: .number)
                        .frame(width: 90)
                        .multilineTextAlignment(.trailing)
                    Text("KB/s").foregroundStyle(.secondary)
                }
            }
            Button("Apply limits now") {
                Task { await app.store.applyLimits() }
            }
        }
    }
}

private struct TorrentSettings: View {
    @EnvironmentObject var configStore: ConfigStore

    var body: some View {
        Form {
            Section("Seeding") {
                Toggle("Seed after the download completes", isOn: $configStore.config.seedAfterComplete)
                HStack {
                    Text("Stop at ratio")
                    Spacer()
                    TextField("", value: $configStore.config.seedingRatioLimit, format: .number)
                        .frame(width: 70)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Stop after (minutes)")
                    Spacer()
                    TextField("", value: $configStore.config.seedingTimeLimitMinutes, format: .number)
                        .frame(width: 70)
                        .multilineTextAlignment(.trailing)
                }
            }
            Section("Discovery") {
                Toggle("Add public trackers to new magnets", isOn: $configStore.config.addPublicTrackers)
            }
        }
    }
}

private struct BrowserSettings: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var configStore: ConfigStore
    @State private var copied = false

    var body: some View {
        Form {
            Section("Browser bridge") {
                Toggle("Accept downloads from the browser extension", isOn: $configStore.config.browserBridgeEnabled)
                    .onChange(of: configStore.config.browserBridgeEnabled) { _, _ in app.restartBridge() }
                HStack {
                    Text("Port")
                    Spacer()
                    TextField("", value: $configStore.config.browserBridgePort, format: .number)
                        .frame(width: 90)
                        .multilineTextAlignment(.trailing)
                        .onSubmit { app.restartBridge() }
                }
                HStack {
                    Text("Status")
                    Spacer()
                    let info = app.bridgeInfo()
                    Text(info.running ? "Listening on 127.0.0.1:\(info.port)" : "Not running")
                        .foregroundStyle(info.running ? Theme.success : .secondary)
                }
            }
            Section("Extension setup") {
                Text("Paste this token into the McDownloader extension's options:")
                    .font(.callout)
                    .foregroundStyle(.secondary)
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
        }
    }
}

private struct ToolsSettings: View {
    @EnvironmentObject var tools: ToolManager

    var body: some View {
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
                    Text(error).font(.caption).foregroundStyle(Theme.warning)
                }
                Text("yt-dlp downloads to \(tools.toolsDirectory.path)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
