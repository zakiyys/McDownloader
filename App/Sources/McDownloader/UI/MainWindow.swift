import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The main window: a three-pane split, a toolbar, and a thin footer summary.
/// The transfer list is the focal point; the sidebar only filters it and the
/// inspector only details the selection (DESIGN.md §7).
struct MainWindow: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DownloadStore
    @EnvironmentObject var configStore: ConfigStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            VStack(spacing: 0) {
                TransferListView()
                Divider()
                FooterSummary()
            }
            .navigationSplitViewColumnWidth(min: 420, ideal: 620)
        }
        .inspector(isPresented: $app.showInspector) {
            InspectorView()
                .inspectorColumnWidth(min: 260, ideal: 300, max: 380)
        }
        .toolbar { toolbarContent }
        .searchable(text: $store.searchText, placement: .toolbar, prompt: "Search downloads")
        .overlay(alignment: .top) { BannerView() }
        .sheet(isPresented: $app.isShowingAddSheet) {
            AddDownloadSheet()
                .environmentObject(app)
                .environmentObject(configStore)
        }
        .onDrop(of: [.fileURL, .url, .text], isTargeted: nil) { providers in
            handleDrop(providers)
            return true
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                app.isShowingAddSheet = true
            } label: {
                Label("Add", systemImage: "plus")
            }
            .help("Add a link, magnet, or .torrent (⌘N)")
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await store.pauseAll() }
            } label: {
                Label("Pause All", systemImage: "pause")
            }
            .disabled(store.counts.active == 0)
            .help("Pause everything (⇧⌘P)")
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await store.resumeAll() }
            } label: {
                Label("Resume All", systemImage: "play")
            }
            .disabled(store.counts.active == store.counts.all)
            .help("Resume everything (⇧⌘R)")
        }
        ToolbarItem {
            Button {
                app.showInspector.toggle()
            } label: {
                Label("Inspector", systemImage: "sidebar.right")
            }
            .help("Show or hide the inspector")
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in await app.handleIncoming(url: url) }
            }
        }
    }
}

/// A compact, always-visible summary. Real numbers only: total speed, active
/// count, and free space on the destination volume (DESIGN.md §7).
struct FooterSummary: View {
    @EnvironmentObject var store: DownloadStore
    @EnvironmentObject var configStore: ConfigStore

    var body: some View {
        let counts = store.counts
        HStack(spacing: 16) {
            Label(Fmt.speed(store.totalDownloadSpeed), systemImage: "arrow.down")
            Text("\(Fmt.count(counts.active)) active")
                .foregroundStyle(.secondary)
            Spacer()
            Text("Free: \(Fmt.bytes(store.freeDiskBytes))")
                .foregroundStyle(.secondary)
            Text(abbreviatedPath)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.caption)
        .monospacedDigit()
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Total speed \(Fmt.speed(store.totalDownloadSpeed)), \(counts.active) active downloads, \(Fmt.bytes(store.freeDiskBytes)) free")
    }

    private var abbreviatedPath: String {
        let path = configStore.config.downloadDirectory
        return (path as NSString).abbreviatingWithTildeInPath
    }
}
