# McDownloader — Design Direction

> Read together with `antislop.md` (filter) and `skills/antislop-ui`, `skills/antislop-human`.
> This file is the *soul* (identity, palette, type, mood). antislop is the *filter* on top.

## 1. Identity

**McDownloader** is a native macOS download manager: one app that handles ordinary
HTTP/HTTPS downloads (the "IDM" half) and BitTorrent (the "torrent" half). Two engines,
one window.

Personality: **calm, precise, instrument-like.** It should feel like a tool Apple could
have shipped next to Finder and Activity Monitor: quiet surfaces, real information, no
decoration that does not carry data. It is infrastructure the user glances at, not a
page that greets them.

Non-goals in the interface: dashboards, stat-card rows, mascots, marketing chrome.

## 2. Design Read

> Reading this as: a native macOS utility for everyday users, in a calm
> instrument-like language (Finder / Activity Monitor), dial ENERGY 1 / RHYTHM 1 / MOTION 1.

## 3. Dials

| Dial | Value | Why |
|---|---|---|
| ENERGY | 1 | A utility that lives all day in the background. It states facts, it does not shout. |
| RHYTHM | 1 | Predictable list + sidebar + inspector. Muscle memory beats surprise in a tool used daily. |
| MOTION | 1 | Hover and state feedback only, plus the live progress bar, which *is* data, not decoration. No loops, no scroll reveals. |

## 4. Theme

**Follow the system appearance** (light/dark), defaulting to the user's macOS setting.
Reason: a utility sits beside Finder, Mail and Activity Monitor all day; those follow the
system, so the user's eyes are already calibrated to it. A fixed dark default would be
"dark because tech", which is exactly the pattern antislop rejects (R-21). Both modes are
first-class and both are verified (R-34).

## 5. Colour

Palette: **neutral system chrome + exactly one accent.**

| Role | Value | Reason |
|---|---|---|
| Canvas / surfaces | macOS system semantic colours (`NSColor.windowBackgroundColor`, `.controlBackgroundColor`, `.underPageBackgroundColor`) | Never hard-coded hex, so light/dark and accessibility contrast are handled by the OS (R-25). |
| Text | `NSColor.labelColor` / `.secondaryLabelColor` / `.tertiaryLabelColor` | Native hierarchy, WCAG-safe in both modes. |
| Separators | `NSColor.separatorColor` | hairline structure, no borders-as-decoration. |
| **Accent (the one)** | `NSColor.controlAccentColor` | Marks the single live thing on screen: **active transfer progress**. Nothing else uses it. |

The accent is a *signal*, not a theme: an active download's progress bar and its state
dot are the only tinted elements. A finished or paused transfer goes neutral. This is the
"one deliberate accent" lever (core Part 3), and it keeps the palette at neutral + 1
accent (R-29).

## 6. Typography

- **UI / body:** the system font (SF Pro via `.system`). Reason: native macOS, best
  legibility at list sizes, and zero font to bundle or license.
- **Numbers only** (speed, size, ETA, ratio): a **monospaced-digit** variant
  (`.monospacedDigit()` on the system font). Reason is functional, not aesthetic: tabular
  figures stop the speed/size columns from jittering as values change tens of times a
  second. This is the one place a "monospace" reads, and it earns it (R-06).
- No custom display face, no uppercase-tracked eyebrow labels.

## 7. Layout

The screen's job: **"see what is transferring right now, and control it."** The layout
serves that decision, not a dashboard template (C-3, `antislop-ui` "Default Dashboard Shell").

```
┌───────────┬────────────────────────────────────────────┬──────────────┐
│ Sidebar   │  Transfer list (the focal point)           │  Inspector   │
│           │                                            │  (optional)  │
│ All       │  ▸ name            ▓▓▓▓▓░░░ 42%  3.1 MB/s   │  Details /   │
│ Active    │  ▸ name            ▓▓░░░░░░ 18%  900 KB/s   │  Files /     │
│ Finished  │  ▸ name (done)     ─────────  2.0 GB       │  Peers       │
│ Torrents  │                                            │              │
│ ‒ cats…   │                                            │              │
├───────────┴────────────────────────────────────────────┴──────────────┤
│ Toolbar: Add · Pause all · Resume all · search · Settings            │
└──────────────────────────────────────────────────────────────────────┘
```

- **Focal point:** the active transfer list. One row is the "current" row the user is
  watching; nothing else competes.
- **Sidebar = filters**, not navigation to nowhere (R-24). Every item filters the same
  list; all destinations exist.
- **Inspector** shows the selected transfer: files (with per-file selection for
  torrents), peers/trackers for torrents, the source URL/host and segmented-connection
  count for HTTP. It is a detail view, not a stat-card grid.
- **No stat cards, no charts.** A summary (total speed, active count, free disk) is a
  single compact footer line, because that is genuinely useful and nothing more (R-17:
  real numbers only, wired to the engines).

## 8. Components

- Lists and rows use native `Table`/`List` where possible. HTTP rows show progress plus
  the **live connection count** (a real aria2 metric); torrent rows show a **piece-level
  band** derived from the torrent's real piece map. We never draw a part-done band for
  HTTP, because aria2 does not expose which byte ranges are complete, and a fabricated
  band would be a lie (R-17, R-38).
- Torrent rows show progress, down/up speed, peers and ratio.
- State is shown by **icon + text + colour**, never colour alone (accessibility).
- Shadow/glass: none. Surfaces are flat; depth comes from native chrome and hairlines
  (R-10, R-12, R-13).
- Radius: native control radius only; the app does not restyle buttons into pills (R-11).

## 9. Icons

**SF Symbols**, chosen per real meaning and written down (R-04):

| Symbol | Used for | Why |
|---|---|---|
| `arrow.down.circle` | HTTP/HTTPS transfer | the universal "download" mark |
| `point.3.connected.trianglepath.dotted` | torrent | the actual P2P topology, not a generic "share" |
| `bolt.horizontal.circle` | segmented/multi-connection | the multi-connection nature of HTTP downloads |
| `checkmark.circle` | completed | state, not decoration |
| `pause.circle` / `play.circle` | transport controls | media-grade, immediately readable |
| `folder` | reveal in Finder | maps to the real Finder concept |

SF Symbols is Apple's system set, so it stays native and consistent; it is a deliberate
choice, not an imported thin-stroke library (R-04).

## 10. App icon

**Defined:** a macOS squircle tile with a blue-to-indigo **progress ring** (75%)
around a bold `M` whose final stroke ends in a **download arrowhead**
(`docs/branding/icon.svg`, rendered to `assets/icon.png`). The single accent
gradient matches the UI's "one accent for the active transfer" rule.
The master vector lives in `docs/branding/icon.svg`; `scripts/make-icon.sh`
builds `AppIcon.icns` from the PNG.

**Paw mark:** a second, secondary motif (`docs/branding/paw-mark-light.svg`
and `paw-mark-dark.svg`), debossed in the originals. In the app it is drawn as a
tintable vector (`PawMark.swift`), fused from the same six shapes so it stays
crisp at any size and needs no asset. It sits once, centred and quiet, at the
foot of the sidebar above the engine line: the app's signature, deliberately
lower emphasis than every row so it is never mistaken for a control or a status
light (R-31). It is not tinted by state; the engine dot carries that.

## 11. States (required)

Every data view ships empty / loading / error, and each names the **cause** and the
**next action** (R-27):

- **Empty:** "No downloads yet. Paste a link, or open a .torrent file." with a primary
  action button.
- **Loading:** "Connecting to the download engine…" while the aria2/torrent helper
  handshake runs.
- **Error (engine down):** "Download engine is not responding. Retry." with a Retry
  button and a "Copy diagnostics" secondary action.
- **Error (transfer):** the row shows the failure reason (e.g. "HTTP 404", "no peers")
  and a Retry action.

## 12. Accessibility

- Full keyboard operation: list focus with arrow keys, `Space` = pause/resume the focused
  transfer, `⌘V` paste a link, `⌘O` open a .torrent, `⌘,` settings, `Escape` closes the
  inspector (R-32).
- Visible focus rings everywhere (never `outline: none` without a replacement).
- VoiceOver labels on every control; progress announced as value + state, not colour.
- Contrast comes from semantic system colours, verified in both appearances (R-25, R-34).

## 13. One-line reasons (R-31)

- **Why system colours?** So light/dark and contrast are handled by the OS, not guessed.
- **Why one accent?** Because exactly one thing on screen is "live": active progress.
- **Why a list?** The job is scanning and controlling transfers; a list is the honest shape.
- **Why system font + monospaced digits?** Native legibility, and tabular numbers stop the
  speed columns from jittering.
- **Why no dashboard?** The product has no metrics to chart; a stat row would be filler.
- **Why SF Symbols?** Native, consistent, and each glyph maps to a real concept here.
