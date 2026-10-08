import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// One field that accepts a link, a magnet, or a .torrent path. The classifier
/// routes it. Optional overrides sit behind a disclosure so the common case is
/// a single paste and Enter.
struct AddDownloadSheet: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var configStore: ConfigStore
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var customFolder = false
    @State private var folder = ""
    @State private var isSubmitting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Download")
                .font(.title2.bold())

            TextField("https://… , magnet:… , or a path to a .torrent file", text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
                .onSubmit { Task { await submit() } }

            DisclosureGroup("Destination", isExpanded: $customFolder) {
                HStack {
                    Text(folder.isEmpty ? configStore.config.downloadDirectory : folder)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Choose…") { chooseFolder() }
                }
                .font(.callout)
            }

            HStack {
                Button("Paste") {
                    text = app.pasteFromClipboard() ?? text
                }
                Button("Open .torrent…") {
                    openTorrent()
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Add") { Task { await submit() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            if let pasted = app.pasteFromClipboard(), looksLikeInput(pasted), text.isEmpty {
                text = pasted
            }
            folder = configStore.config.downloadDirectory
        }
    }

    private func looksLikeInput(_ value: String) -> Bool {
        switch InputClassifier.classify(value) {
        case .unknown: return false
        default: return true
        }
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        let savePath = customFolder ? folder : nil
        await app.submitAdd(text: text, savePath: savePath)
        if app.banner == nil || app.banner?.kind == .info {
            dismiss()
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choose where McDownloader saves files"
        if panel.runModal() == .OK, let url = panel.url { folder = url.path }
    }

    private func openTorrent() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a .torrent file"
        if panel.runModal() == .OK, let url = panel.url {
            text = url.path
        }
    }
}

/// A transient banner at the top of the window for success and error feedback.
struct BannerView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        if let banner = app.banner {
            HStack(spacing: 8) {
                Image(systemName: banner.kind == .error ? "exclamationmark.triangle" : "checkmark.circle")
                Text(banner.message).lineLimit(2)
                Spacer()
                Button {
                    app.banner = nil
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Dismiss message")
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor)))
            .foregroundStyle(banner.kind == .error ? Theme.warning : Color(nsColor: .labelColor))
            .padding(.top, 8)
            .frame(maxWidth: 480)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
