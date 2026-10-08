import SwiftUI
import AppKit

@main
struct McDownloaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var app: AppState

    init() {
        let configStore = ConfigStore()
        _app = StateObject(wrappedValue: AppState(configStore: configStore))
    }

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environmentObject(app)
                .environmentObject(app.store)
                .environmentObject(app.tools)
                .environmentObject(app.configStore)
                .frame(minWidth: 820, minHeight: 460)
                .onAppear { app.start() }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Download…") { app.isShowingAddSheet = true }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Open .torrent…") { app.openTorrentFile() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Button("Pause All") { Task { await app.store.pauseAll() } }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Resume All") { Task { await app.store.resumeAll() } }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(app)
                .environmentObject(app.tools)
                .environmentObject(app.configStore)
        }

        MenuBarExtra("McDownloader", systemImage: "arrow.down.circle") {
            MenuBarView()
                .environmentObject(app)
                .environmentObject(app.store)
        }
    }
}

/// The menu bar extra mirrors the essentials without opening the window.
struct MenuBarView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DownloadStore

    var body: some View {
        let counts = store.counts
        Text(counts.active > 0 ? "\(counts.active) active · \(Fmt.speed(store.totalDownloadSpeed))" : "No active downloads")
        Divider()
        if store.transfers.isEmpty {
            Text("Nothing to show")
        } else {
            ForEach(store.transfers.prefix(8)) { transfer in
                Button("\(transfer.state.label) · \(transfer.name)") {
                    app.revealWindow()
                }
            }
        }
        Divider()
        Button("Open McDownloader") { app.revealWindow() }
    }
}
