import SwiftUI
import AppKit

/// Details for the selected transfer. For torrents it loads trackers, peers and
/// the file list on demand, so the one-second polling loop stays cheap.
struct InspectorView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DownloadStore
    @State private var torrentInfo: TorrentInfo?

    private var transfer: Transfer? { store.transfer(id: app.selectedTransferID) }

    var body: some View {
        Group {
            if let transfer {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header(transfer)
                        Divider()
                        if transfer.kind == .http {
                            httpDetails(transfer)
                        } else {
                            torrentDetails(transfer)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .task(id: transfer.id) {
                    torrentInfo = await store.loadDetails(for: transfer)
                }
            } else {
                ContentUnavailableView {
                    Label("Nothing selected", systemImage: "sidebar.right")
                } description: {
                    Text("Select a download to see its details here.")
                }
            }
        }
    }

    // MARK: Header

    private func header(_ transfer: Transfer) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(transfer.name)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            StateBadge(transfer: transfer)
            HStack(spacing: 12) {
                Text(Fmt.percent(transfer.progress))
                if transfer.downloadSpeed > 0 { Text(Fmt.speed(transfer.downloadSpeed)) }
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
    }

    // MARK: HTTP

    private func httpDetails(_ transfer: Transfer) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            section("Transfer") {
                row("Size", transfer.totalBytes > 0 ? Fmt.bytes(transfer.totalBytes) : "Unknown")
                row("Downloaded", Fmt.bytes(transfer.completedBytes))
                row("Remaining", transfer.totalBytes > 0 ? Fmt.bytes(transfer.remainingBytes) : "Unknown")
                row("Speed", Fmt.speed(transfer.downloadSpeed))
                row("ETA", transfer.eta)
                row("Connections", Fmt.count(transfer.connections))
                row("Added", transfer.addedAt.formatted(date: .abbreviated, time: .shortened))
            }
            section("Source") {
                if let url = transfer.sourceURL {
                    Text(url)
                        .font(.caption)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
                row("Host", transfer.sourceHost.isEmpty ? "—" : transfer.sourceHost)
            }
            section("Destination") {
                pathRow(transfer.targetPath)
            }
        }
    }

    // MARK: Torrent

    private func torrentDetails(_ transfer: Transfer) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            section("Transfer") {
                row("Size", Fmt.bytes(transfer.totalBytes))
                row("Downloaded", Fmt.bytes(transfer.completedBytes))
                row("Down", Fmt.speed(transfer.downloadSpeed))
                row("Up", Fmt.speed(transfer.uploadSpeed))
                row("Peers", Fmt.count(transfer.peersConnected))
                if let info = torrentInfo {
                    row("Seeders", Fmt.count(info.seeders))
                    row("Leechers", Fmt.count(info.leechers))
                    row("Ratio", String(format: "%.2f", info.ratio))
                    row("Uploaded", Fmt.bytes(info.uploadedBytes))
                }
                row("Added", transfer.addedAt.formatted(date: .abbreviated, time: .shortened))
            }

            if let info = torrentInfo, !info.files.isEmpty {
                section("Files") {
                    ForEach(info.files) { file in
                        HStack(spacing: 8) {
                            Toggle("", isOn: Binding(
                                get: { file.selected },
                                set: { newValue in
                                    var indexes = info.files.filter { $0.selected }.map(\.id)
                                    if newValue { if !indexes.contains(file.id) { indexes.append(file.id) } }
                                    else { indexes.removeAll { $0 == file.id } }
                                    Task { await store.setFileSelection(transfer, fileIndexes: indexes) }
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.path).font(.caption).lineLimit(1).truncationMode(.middle)
                                Text("\(Fmt.bytes(file.completed)) / \(Fmt.bytes(file.length))")
                                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                    }
                }
            }

            if let info = torrentInfo, !info.trackers.isEmpty {
                section("Trackers") {
                    ForEach(info.trackers) { tracker in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tracker.url).font(.caption).lineLimit(1).truncationMode(.middle)
                            Text(tracker.working ? "Working · \(tracker.seeders) seeders" : (tracker.message.isEmpty ? "No response" : tracker.message))
                                .font(.caption2)
                                .foregroundStyle(tracker.working ? Theme.success : .secondary)
                        }
                    }
                }
            }

            if let info = torrentInfo, !info.peers.isEmpty {
                section("Peers") {
                    ForEach(info.peers.prefix(30)) { peer in
                        HStack {
                            Text("\(peer.address):\(peer.port)").font(.caption).monospacedDigit()
                            Spacer()
                            Text(Fmt.speed(peer.downloadSpeed)).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: Building blocks

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.caption)
    }

    private func pathRow(_ path: String) -> some View {
        HStack(alignment: .top) {
            Text(path)
                .font(.caption)
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer()
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")
        }
    }
}
