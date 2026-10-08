# McDownloader

A native macOS download manager that does two jobs in one window: accelerated
HTTP/HTTPS downloads (multi-connection, resumable) and BitTorrent (magnet links
and `.torrent` files). It is built for macOS 14 and later, on Apple Silicon and
Intel, and it stays out of the way in the menu bar.

> **Not affiliated with Internet Download Manager (IDM).** IDM is a proprietary
> Windows product. McDownloader is an independent download manager inspired by
> the same idea. It is not a port, crack, or repack of IDM.

## Engines

Two engines, one interface:

| Half | Engine | Why |
|---|---|---|
| HTTP / HTTPS / FTP | [aria2](https://aria2.github.io) (bundled, JSON-RPC) | Mature multi-connection engine, resume, queue, rate limits |
| BitTorrent | [libtorrent](https://www.libtorrent.org) 2.x (bundled helper) | UPnP/NAT-PMP, DHT, uTP, pex, the same engine qBittorrent uses |

Both speak the same JSON-RPC shape, so the app treats them identically. Each runs
in its own process: if one misbehaves, the other and the UI keep running.

## Features

- Multi-connection HTTP downloads with resume, including across restarts.
- BitTorrent with magnet links, `.torrent` files, per-file selection, seed
  ratio/time limits, and public-tracker augmentation.
- Browser extension (Chrome, Edge, Brave) that hands downloads to the app with
  cookies and referer, so signed URLs keep working.
- Opens `magnet:` links and `.torrent` files directly.
- Prevent sleep while transfers run; optional sleep when the queue finishes.
- Native completion notifications.
- Downloaded files get the macOS quarantine attribute, so Gatekeeper still
  checks `.app` and `.dmg` files.
- Video grabbing via yt-dlp (installed on first use, not bundled).

## Download

Grab the latest `.dmg` or `.zip` from the
[Releases](https://github.com/zakiyys/McDownloader/releases) page.

The app is **not notarized** (that needs a paid Apple Developer account), so on
first launch macOS will show a warning. To open it:

1. Control-click the app, choose **Open**, then confirm **Open**.
2. Or run once: `xattr -dr com.apple.quarantine /Applications/McDownloader.app`

## Build from source

Requires macOS 14+ with the Xcode command line tools (full Xcode is not needed
for local building).

```bash
git clone https://github.com/zakiyys/McDownloader.git
cd McDownloader/App
swift build -c release
```

To assemble a full `.app` you also need the two engine binaries. They are built
by the release workflow, or you can build them yourself:

```bash
./scripts/build-aria2-universal.sh "$PWD/vendor"
./scripts/build-libtorrent-universal.sh "$PWD/vendor"

BINARY="$(swift build -c release --package-path App --show-bin-path)/McDownloader"
./scripts/package-app.sh \
  --binary "$BINARY" --out dist \
  --aria2 vendor/aria2c --torrent-helper vendor/mcdownloader-torrentd
```

## Browser extension

1. Open `chrome://extensions`, turn on **Developer mode**.
2. Choose **Load unpacked** and select the `Extension` folder.
3. Open McDownloader, go to **Settings → Browser**, and copy the token.
4. Paste the token into the extension's **Options** and save.

The extension talks to the app on `127.0.0.1` only, authenticated by that token.
Nothing is sent anywhere else.

## How updates work

Each GitHub release is a new tag (`v1.0.1`, `v1.0.2`, ...). Watch the repository
to be notified. There is no auto-updater yet; download the new `.dmg` and replace
the app.

## License

GNU General Public License v3.0. See [LICENSE](LICENSE). This is required in part
because aria2 is GPLv2 and is bundled with the app.

## Credits

Built by [zakiyys](https://github.com/zakiyys). Engine work stands on aria2 and
libtorrent.
