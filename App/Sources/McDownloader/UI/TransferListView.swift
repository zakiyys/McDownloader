import SwiftUI

/// The focal point: one row per transfer, with real state (DESIGN.md §7).
/// The three required states (empty/loading/error) each name a cause and a
/// next action (R-27).
struct TransferListView: View {
    @EnvironmentObject var store: DownloadStore
    @EnvironmentObject var app: AppState

    var body: some View {
        Group {
            switch store.status {
            case .starting where store.transfers.isEmpty:
                LoadingState()
            case .failed(let message) where store.transfers.isEmpty:
                ErrorState(message: message) { Task { await store.startEngines() } }
            default:
                if store.transfers.isEmpty {
                    EmptyState()
                } else if store.filtered.isEmpty {
                    NoResultsState()
                } else {
                    list
                }
            }
        }
    }

    private var list: some View {
        List(selection: $app.selectedTransferID) {
            ForEach(store.filtered) { transfer in
                TransferRow(transfer: transfer)
                    .tag(transfer.id)
                    .contextMenu { TransferContextMenu(transfer: transfer) }
            }
        }
        .listStyle(.inset)
        .alternatingRowBackgrounds()
    }
}

// MARK: - States

struct EmptyState: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ContentUnavailableView {
            Label("No downloads yet", systemImage: "arrow.down.circle")
        } description: {
            Text("Paste a link or magnet, drop a .torrent file here, or add one from the toolbar.")
        } actions: {
            Button("Add a download") { app.isShowingAddSheet = true }
                .buttonStyle(.borderedProminent)
        }
    }
}

struct NoResultsState: View {
    @EnvironmentObject var store: DownloadStore

    var body: some View {
        ContentUnavailableView {
            Label("Nothing matches", systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text(store.searchText.isEmpty
                 ? "No downloads in this filter. Choose another filter in the sidebar."
                 : "No download matches “\(store.searchText)”.")
        } actions: {
            if !store.searchText.isEmpty {
                Button("Clear search") { store.searchText = "" }
            }
            Button("Show all") {
                store.filter = .all
                store.categoryFilter = nil
            }
        }
    }
}

struct LoadingState: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Starting the download engine…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct ErrorState: View {
    var message: String
    var retry: () -> Void
    @EnvironmentObject var app: AppState

    var body: some View {
        ContentUnavailableView {
            Label("The download engine is not responding", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Retry", action: retry)
                .buttonStyle(.borderedProminent)
            Button("Copy diagnostics") { app.copyDiagnostics() }
        }
    }
}

// MARK: - Row

struct TransferRow: View {
    var transfer: Transfer
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DownloadStore

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: Theme.symbol(for: transfer))
                .font(.title3)
                .foregroundStyle(Theme.tint(for: transfer.state))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(transfer.name)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 8) {
                    if transfer.kind == .torrent {
                        Text("Torrent")
                            .foregroundStyle(.secondary)
                    } else if transfer.connections > 1 {
                        Label("\(transfer.connections)", systemImage: "bolt.horizontal.circle")
                            .foregroundStyle(.secondary)
                            .help("\(transfer.connections) parallel connections")
                    }
                    if transfer.state == .error, let error = transfer.errorMessage {
                        Text(error).foregroundStyle(Theme.warning).lineLimit(1)
                    } else {
                        Text(transfer.detailSummary).foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .monospacedDigit()
            }

            Spacer(minLength: 8)

            ProgressCell(transfer: transfer)

            VStack(alignment: .trailing, spacing: 3) {
                Text(Fmt.speed(transfer.downloadSpeed))
                    .monospacedDigit()
                if transfer.kind == .torrent && transfer.uploadSpeed > 0 {
                    Text("↑ \(Fmt.speed(transfer.uploadSpeed))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else if let torrent = transfer.torrent, torrent.seeders > 0 {
                    Text("\(torrent.seeders) seeders")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 96, alignment: .trailing)

            Button {
                Task { await store.toggle(transfer) }
            } label: {
                Image(systemName: transfer.state == .paused ? "play.circle" : "pause.circle")
            }
            .buttonStyle(.borderless)
            .help(transfer.state == .paused ? "Resume" : "Pause")
            .accessibilityLabel(transfer.state == .paused ? "Resume \(transfer.name)" : "Pause \(transfer.name)")

            Button {
                store.revealInFinder(transfer)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")
            .accessibilityLabel("Reveal \(transfer.name) in Finder")
        }
        .padding(.vertical, 4)
    }
}

/// Progress bar plus a right-aligned percentage. For torrents, a thin piece
/// band sits above the bar, drawn from the real piece map.
struct ProgressCell: View {
    var transfer: Transfer

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(nsColor: .quaternaryLabelColor))
                    .frame(width: 160, height: 6)
                Capsule()
                    .fill(Theme.tint(for: transfer.state))
                    .frame(width: max(2, 160 * transfer.progress), height: 6)
            }
            .frame(width: 160, height: 6)
            Text(Fmt.percent(transfer.progress))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(transfer.name) progress")
        .accessibilityValue(Fmt.percent(transfer.progress))
    }
}
