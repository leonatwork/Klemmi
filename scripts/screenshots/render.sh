#!/usr/bin/env bash
# Regenerates the README screenshots in docs/screenshots/ (English and German) from invented
# demo data. Everything is drawn offscreen: no window appears, the screen is never captured,
# the clipboard is never read or written and the real history in
# ~/Library/Application Support/Klemmi is never touched.
#
# WORK_DIR (optional) is where the temporary app bundle and demo data go; default: mktemp -d.
set -euo pipefail

cd "$(dirname "$0")/../.."
WORK="${WORK_DIR:-$(mktemp -d)}"
APP="$WORK/KlemmiScreenshots.app"
OUT="${OUT_DIR:-docs/screenshots}"

echo "==> compiling harness"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
SOURCES=()
# Includes LoginItemPolicy.swift and LoginItem.swift; main.swift alone owns auto-registration.
for f in Sources/*.swift; do [[ "$f" == Sources/main.swift ]] || SOURCES+=("$f"); done
swiftc -O -target "$(uname -m)-apple-macosx13.0" "${SOURCES[@]}" scripts/screenshots/ScreenshotHarness.swift \
  -framework AppKit -framework Carbon -framework ServiceManagement \
  -o "$APP/Contents/MacOS/KlemmiScreenshots"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>KlemmiScreenshots</string>
  <key>CFBundleExecutable</key><string>KlemmiScreenshots</string>
  <key>CFBundleIdentifier</key><string>de.local.klemmi.screenshots</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key>
  <array><string>en</string><string>de</string></array>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
cp -R Resources/*.lproj "$APP/Contents/Resources/"

mkdir -p "$OUT"
for lang in en de; do
  case "$lang" in en) locale=en_US ;; de) locale=de_DE ;; esac
  echo "==> rendering ($lang)"
  "$APP/Contents/MacOS/KlemmiScreenshots" \
    -AppleLanguages "($lang)" -AppleLocale "$locale" -AppleInterfaceStyle Light \
    -data "$WORK/demo-$lang" -out "$OUT" -lang "$lang"
done

# The harness empties its own defaults domain (window frame autosave); drop the leftover file.
rm -f "$HOME/Library/Preferences/de.local.klemmi.screenshots.plist"
[[ -n "${WORK_DIR:-}" ]] || rm -rf "$WORK"
echo "==> done: $OUT"
