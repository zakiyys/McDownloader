import SwiftUI

/// Filters, not navigation. Every row narrows the same list; nothing here leads
/// to a page that does not exist (DESIGN.md §7, R-24).
struct SidebarView: View {
    @EnvironmentObject var store: DownloadStore
    @EnvironmentObject var app: AppState
    @EnvironmentObject var configStore: ConfigStore

    var body: some View {
        let counts = store.counts
        List(selection: sidebarSelection) {
            Section {
                sidebarRow(.all, count: counts.all)
                sidebarRow(.active, count: counts.active)
                sidebarRow(.finished, count: counts.finished)
                sidebarRow(.torrents, count: counts.torrents)
            }

            Section("Categories") {
                ForEach(TransferCategory.allCases, id: \.self) { category in
                    let count = store.transfers.filter { $0.category == category }.count
                    Button {
                        store.categoryFilter = store.categoryFilter == category ? nil : category
                        store.filter = .all
                    } label: {
                        HStack {
                            Label(category.label, systemImage: category.symbol)
                            Spacer()
                            if count > 0 {
                                Text("\(count)").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        store.categoryFilter == category
                            ? Color.accentColor.opacity(0.12)
                            : Color.clear
                    )
                    .accessibilityLabel("\(category.label), \(count) downloads")
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            EngineStatusView()
                .padding(8)
        }
    }

    private var sidebarSelection: Binding<SidebarFilter?> {
        Binding(
            get: { store.filter },
            set: { newValue in
                if let newValue {
                    store.filter = newValue
                    store.categoryFilter = nil
                }
            }
        )
    }

    private func sidebarRow(_ filter: SidebarFilter, count: Int) -> some View {
        Label {
            HStack {
                Text(filter.label)
                Spacer()
                Text("\(count)").foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: filter.symbol)
        }
        .tag(filter)
        .accessibilityLabel("\(filter.label), \(count) downloads")
    }
}

/// Small footer in the sidebar showing whether the engines are up (R-27 error
/// state lives here and in the list's error view).
struct EngineStatusView: View {
    @EnvironmentObject var store: DownloadStore
    @EnvironmentObject var app: AppState

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if case .failed = store.status {
                Button("Retry") { Task { await store.startEngines() } }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
        .help(helpText)
    }

    private var symbol: String {
        switch store.status {
        case .running: return "circle.fill"
        case .starting: return "circle.dotted"
        case .idle: return "circle"
        case .failed: return "exclamationmark.circle"
        }
    }

    private var color: Color {
        switch store.status {
        case .running: return Theme.success
        case .failed: return Theme.warning
        default: return Color(nsColor: .tertiaryLabelColor)
        }
    }

    private var label: String {
        switch store.status {
        case .running:
            let engines = engineSummary
            return "Engine ready" + (engines.isEmpty ? "" : " · \(engines)")
        case .starting: return "Starting engine…"
        case .idle: return "Engine stopped"
        case .failed: return "Engine error"
        }
    }

    private var engineSummary: String {
        var parts: [String] = []
        if EngineLocator.aria2c() != nil { parts.append("HTTP") }
        if EngineLocator.torrentHelper() != nil { parts.append("torrent") }
        return parts.joined(separator: ", ")
    }

    private var helpText: String {
        switch store.status {
        case .failed(let message): return message
        case .running: return "aria2 and the torrent helper are running."
        case .starting: return "Connecting to the download engine…"
        case .idle: return "Engines are stopped."
        }
    }
}
