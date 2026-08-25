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

`build.sh` compiles the sources, generates the icon and installs `Klemmi.app` into
`~/Applications`. Requirements: macOS 13 or later.

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
- **Everything is stored unencrypted** in `~/Library/Application Support/Klemmi`. If you add
  new data to the store, consider whether it belongs on disk at all.

## Pull requests

- One topic per PR.
- Explain **why** the change is needed, not only what it does.
- Please describe how you tested. Much of Klemmi's behaviour can only be checked manually:
  copying from different apps, images versus text, restart persistence, the entry limit.
- Keep the build warning-free.

## Reporting bugs

Please include your macOS version, whether you are on Apple Silicon or Intel, and — where
relevant — which app you copied from. Please do **not** paste actual clipboard contents into
an issue.

## Language

Documentation is written in English. A German translation of the README lives in
[README.de.md](README.de.md); the English version is authoritative and updated first.
