# Klemmi

Klemmi is a small native macOS app that keeps a searchable clipboard history — text and
images, each with a timestamp and the app the content was copied from. It brings the
`Win`+`V` clipboard history from Windows to macOS.

![Platform](https://img.shields.io/badge/macOS-13%2B-blue) ![Language](https://img.shields.io/badge/Swift-AppKit-orange) [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

*🇩🇪 [Deutsche Version](README.de.md)*

## Screenshots

<div align="center">
  <img src="docs/screenshots/popover.png" alt="Klemmi popover with clipboard history" width="380" />
  <br />
  <em>Menu bar popover — every entry shows the app it was copied from</em>
  <br /><br />
  <img src="docs/screenshots/overview.png" alt="Klemmi overview grouped by app" width="440" />
  <br />
  <em>Overview window, grouped by source app</em>
</div>

## Features

- **Menu bar icon**: a click opens a compact popover with the history, a right-click opens
  a menu (open overview, show/hide the Dock icon, ignore sensitive content, clear history,
  quit).
- **Overview window**: a larger view grouping entries by **date** (today / yesterday / this
  week / older), **app**, or **type** (text / images) — reachable via "Übersicht …" in the
  popover or the right-click menu.
- **Captures text and images** from the clipboard. Every entry shows which app it came from
  (name and icon) plus a relative timestamp.
- **Search** across text and source app, both in the popover and the overview window.
- **Back to the clipboard**: double-click an entry (or right-click ▸ copy to clipboard in
  the overview) to put it back on the clipboard. Pasting stays manual via <kbd>⌘</kbd><kbd>V</kbd>.
- **Persistence**: the history lives in `~/Library/Application Support/Klemmi` (images as
  PNG, metadata as JSON) and survives a restart of the app.
- **Bounded**: the most recent 200 entries by default; older ones drop out automatically
  along with their image files.
- **Respects password managers**: content marked as sensitive via the
  `org.nspasteboard.ConcealedType` / `TransientType` convention (1Password, for example) is
  not stored by default. This can be switched off.

### Known limitations (v1)

- The source app is determined from whichever app was frontmost at the moment of copying —
  macOS provides no direct attribution through the clipboard. Reliable in practice, but not
  guaranteed by the system.
- No automatic pasting via a keyboard shortcut, which would require Accessibility
  permissions. An entry is only placed on the clipboard; pasting stays
  <kbd>⌘</kbd><kbd>V</kbd>.
- No global shortcut to open the popover — only clicking the menu bar icon.

## Building

The Xcode Command Line Tools are the only requirement; there are no further dependencies.

```bash
xcode-select --install
git clone https://github.com/leonatwork/Klemmi.git
cd Klemmi
./build.sh
```

The script compiles the sources, generates the app icon and places `Klemmi.app` in
`~/Applications`.

## Privacy

Klemmi stores everything locally in `~/Library/Application Support/Klemmi` and sends
nothing anywhere. Be aware that a clipboard history is sensitive by nature: anything you
copy ends up on disk unencrypted, which is exactly why content flagged as concealed by
password managers is skipped by default. Clear the history from the menu bar icon when you
would rather it did not persist.

## Layout

| File | Role |
| --- | --- |
| `Sources/main.swift` | App delegate, entry point |
| `Sources/StatusItem.swift` | Menu bar icon, popover, context menu |
| `Sources/HistoryList.swift` | Table view of the history including search (popover) |
| `Sources/MainWindow.swift` | Overview window grouped by date / app / type |
| `Sources/ClipboardMonitor.swift` | Polls the clipboard, identifies the source app |
| `Sources/HistoryStore.swift` | In-memory history plus persistence to disk |
| `Sources/HistoryItem.swift` | Data model of a single entry |
| `Sources/Clipboard.swift` | Writes an entry back to the clipboard |
| `Sources/Support.swift` | Settings (UserDefaults) |
| `icon.swift` | Generates the app icon as `.icns` |

## Contributing

Bug reports and pull requests are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE) — free to use, modify and redistribute, without warranty.
