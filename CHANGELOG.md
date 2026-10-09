# Changelog

All notable changes to McDownloader are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.1] - 2026-10-09

### Fixed

- **The download engine no longer fails to start** ("Download engine is not
  responding"). The app passed `--bt-enabled` and `--follow-torrent` to aria2,
  but the bundled aria2 is built `--disable-bittorrent`, which compiles those
  options out. aria2 aborted on the unknown option before opening its RPC port.
  Both flags are gone; BitTorrent was always handled by the separate helper, so
  behaviour is unchanged.
- A fresh install now works: aria2 aborts when `--input-file` names a session
  file that does not exist yet, so the app creates an empty session on launch.
- Engine startup failures are no longer silent: aria2's and the helper's stderr
  are kept, and a process that dies during startup reports its exit status and
  the last stderr line instead of a bare timeout.
- Settings: the Bandwidth, Torrents and Browser (Manual bridge) tabs no longer
  push their labels and controls past the window edge. Each tab scrolls, long
  text wraps instead of clipping, and the window has a comfortable minimum size.
- Release builds sign each engine and the native host explicitly instead of
  relying on `codesign --deep`, which left the Intel slice of the universal
  engines unsigned.

### Added

- CI guard: the release build now fails if the app passes an aria2 option the
  bundled aria2 does not understand, and verifies every architecture of the
  engines and host is signed.

## [1.1.0] - 2026-10-08

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
