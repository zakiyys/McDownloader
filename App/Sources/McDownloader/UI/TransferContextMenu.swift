import SwiftUI
import AppKit

/// The right-click menu on a transfer. Every action here has a real effect
/// (R-26); actions that do not apply to the transfer's kind are omitted, not
/// shown greyed for no reason.
struct TransferContextMenu: View {
    var transfer: Transfer
    @EnvironmentObject var store: DownloadStore
    @EnvironmentObject var app: AppState
    @State private var showRemoveConfirm = false
    @State private var deleteFiles = false

    var body: some View {
        if transfer.state == .paused {
            Button("Resume") { Task { await store.resume(transfer) } }
        } else if transfer.isActive {
            Button("Pause") { Task { await store.pause(transfer) } }
        }

        if transfer.state == .completed {
            Button("Open") { store.open(transfer) }
        }
        Button("Reveal in Finder") { store.revealInFinder(transfer) }

        if let url = transfer.sourceURL, transfer.kind == .http {
            Button("Copy address") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url, forType: .string)
            }
        }
        if transfer.kind == .torrent {
            Button("Copy magnet link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(transfer.sourceURL ?? transfer.torrent?.infoHash ?? "", forType: .string)
            }
            .disabled(transfer.sourceURL == nil)
        }

        if transfer.state == .error && transfer.kind == .http {
            Button("Retry") { Task { await retry() } }
        }

        Divider()
        Button("Remove…") {
            deleteFiles = false
            showRemoveConfirm = true
        }
        .confirmationDialog("Remove “\(transfer.name)”?", isPresented: $showRemoveConfirm) {
            Button("Remove from list") { Task { await store.remove(transfer, deleteFiles: false) } }
            Button("Remove and delete file", role: .destructive) {
                Task { await store.remove(transfer, deleteFiles: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The downloaded file stays on disk unless you choose to delete it.")
        }
    }

    private func retry() async {
        // Re-submit the same address; if it has expired the extension is the
        // source of a fresh one (see the extension's "Refresh link" action).
        guard let url = transfer.sourceURL else { return }
        let message = await store.retryWithFreshURL(transfer, newURL: url, referer: nil, cookie: nil)
        if let message { app.present(.error, message) }
    }
}
