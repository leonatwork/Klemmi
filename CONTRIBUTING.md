# Contributing to Klemmi

Thanks for your interest. Klemmi is a small AppKit app with no dependencies — you should be
productive within minutes.

## Development setup

No Xcode required, the Command Line Tools are enough:

```bash
xcode-select --install
git clone https://github.com/leonatwork/Klemmi.git
cd Klemmi
./build.sh
```

`build.sh` compiles the sources, copies the localizations, generates the icon and places
`Klemmi.app` in `dist/` (`--install` also copies it into `/Applications`). Requirements:
Apple Silicon, macOS 13+.

Optional: `./setup-signing.sh` creates a self-signed local identity so that granted
permissions survive rebuilds. Its default name is now `Klemmi Local Signing` (formerly
`Tappi Local Signing`). `build.sh` looks for `Klemmi Local Signing`, then
`leonatwork Code Signing`, and only then the legacy `Tappi Local Signing`, so an existing
setup keeps working without re-running the script.

## Things worth knowing before you change something

- **The clipboard has no change notification.** macOS offers no callback when the pasteboard
  changes, so `ClipboardMonitor` polls `NSPasteboard.changeCount`. Keep the polling interval
  in mind when touching that code — it runs for the entire session.
- **Source attribution is a heuristic.** macOS does not record which app put something on
  the clipboard. Klemmi uses whichever app was frontmost at the time of copying. That is
  usually right but cannot be guaranteed, and the wording in the UI should not promise more
  than that.
- **Sensitive content must stay opt-out, not opt-in.** Password managers mark entries via
  `org.nspasteboard.ConcealedType` / `TransientType`. Klemmi honours that by default, and it
  should stay that way — a clipboard history that silently stores passwords is a liability.
- **Every UI string is localized.** Klemmi ships in English (development language),
  German, French, Spanish, Italian, Portuguese (Brazil), Dutch, Japanese, Simplified Chinese
  and Korean. Use `L10n.tr("semantic.key")` instead of a literal, add the key to every
  `Resources/<lang>.lproj/Localizable.strings` (plurals go into `Localizable.stringsdict`),
  follow Apple's own terminology for each language, and run
  `scripts/check-localizations.sh` before opening a PR.
- **Everything is stored unencrypted** in `~/Library/Application Support/Klemmi`. If you add
  new data to the store, consider whether it belongs on disk at all.

## Screenshots

The README images in `docs/screenshots/` (`popover`, `overview`, `overlay`, each in English
and as `.de.png` in German) are rendered, not captured:

```bash
scripts/screenshots/render.sh
```

The script compiles the app sources together with `scripts/screenshots/ScreenshotHarness.swift`
into a temporary app bundle and draws every view offscreen at 2× from invented demo entries.
It never captures the screen, never reads or writes the clipboard and never touches your own
history in `~/Library/Application Support/Klemmi`. Re-run it whenever the UI changes, check
the images, and keep the demo entries free of personal data.

## Pull requests

- One topic per PR.
- Explain **why** the change is needed, not only what it does.
- Please describe how you tested. Much of Klemmi's behaviour can only be checked manually:
  copying from different apps, images versus text, restart persistence, the entry limit.
- Keep the build warning-free.

## Reporting bugs

Please include your macOS version, your Apple Silicon chip model, and — where
relevant — which app you copied from. Please do **not** paste actual clipboard contents into
an issue.

## License of contributions

Contributions are accepted under the MIT License, the same license as the project.
Optional premium add-ons are developed separately. Community contributions are only
included there with the contributor's explicit consent.

## Language

Documentation is written in English. A German translation of the README lives in
[README.de.md](README.de.md); the English version is authoritative and updated first.
