# Changelog

All notable changes to McDownloader are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Browser extension now connects through a Native Messaging host, so there is no
  port to set and no token to copy. The extension ID is pinned with a `key`, so
  it survives reinstalls and the connection keeps working.
- A **Connect browser** button in Settings installs the native host for every
  Chromium browser on the Mac and reveals the bundled extension folder.

### Changed

- The local HTTP bridge is now the fallback path, kept for browsers without the
  host and for manual setups; it is folded into a **Manual bridge (advanced)**
  section in Settings.

## [1.0.0] - 2026-10-08

First release.

### Added

- Native macOS app (SwiftUI) for macOS 14+, universal (Apple Silicon and Intel).
- HTTP/HTTPS/FTP downloads via a bundled aria2 engine: multi-connection,
  resume, queue, global rate limits.
- BitTorrent via a bundled libtorrent helper: magnet links, `.torrent` files,
  per-file selection, DHT/UPnP/uTP, seed ratio and time limits.
- Browser extension for Chrome, Edge, and Brave that hands downloads to the app
  with cookies and referer, and offers a one-click "download this link" action.
- Opens `magnet:` links and `.torrent` files as a handler.
- Prevent-sleep while active, optional sleep when the queue finishes, and native
  completion notifications.
- Quarantine attribute applied to finished files so Gatekeeper still checks them.
- Video grabbing with yt-dlp, installed on first use and updatable from Settings.
- Light and dark appearance follow the system setting.

[Unreleased]: https://github.com/zakiyys/McDownloader/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/zakiyys/McDownloader/releases/tag/v1.0.0
