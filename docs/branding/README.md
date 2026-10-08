# Branding

## App icon

The icon is defined by `icon.svg` and rendered to PNG. The design: a macOS
squircle tile holding a **progress ring** (75%, blue to indigo) around a bold
`M` whose descending stroke ends in a **download arrowhead**. It encodes the
product in one mark: an accelerated download ("M" for McDownloader, the arrow)
inside a transfer that is in progress (the ring) - the same idea the UI repeats
with its one accent colour for the active transfer.

Files:

- `icon.svg` - the master vector.
- `assets/icon.png` - a 1024x1024 render used by the README and by
  `scripts/make-icon.sh` to build `AppIcon.icns`.
- `assets/screenshot-main.png` - a render of the main window (also used by the README).

To rebuild the PNG from the SVG (any headless Chromium works):

```bash
chrome --headless=new --window-size=1024,1024 \
  --default-background-color=00000000 \
  --screenshot=assets/icon.png render.html   # render.html just <img>s icon.svg at 1024px
```

`scripts/make-icon.sh` then turns `assets/icon.png` into the `.iconset` /
`AppIcon.icns` the app bundle needs (it falls back to a drawn placeholder if the
PNG is absent, so the release pipeline never breaks).

## Palette

The icon uses one gradient as its single accent: `#0A84FF` to `#5E5CE6`
(system blue to system indigo), on a near-white tile (`#FFFFFF` to `#E6E9EF`).
The app itself stays native and neutral; the accent is reserved for the active
transfer, matching the icon.
