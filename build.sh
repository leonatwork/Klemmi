#!/usr/bin/env bash
# Builds Klemmi.app into dist/. Pass --install to copy it into /Applications.
set -euo pipefail

cd "$(dirname "$0")"
APP="dist/Klemmi.app"

echo "==> compiling"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O \
  Sources/Support.swift Sources/HistoryItem.swift Sources/HistoryStore.swift \
  Sources/ClipboardMonitor.swift Sources/Clipboard.swift Sources/HistoryList.swift \
  Sources/MainWindow.swift Sources/StatusItem.swift Sources/HotKey.swift \
  Sources/Overlay.swift Sources/main.swift \
  -framework AppKit -framework Carbon \
  -o "$APP/Contents/MacOS/Klemmi"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Klemmi</string>
  <key>CFBundleDisplayName</key><string>Klemmi</string>
  <key>CFBundleExecutable</key><string>Klemmi</string>
  <key>CFBundleIdentifier</key><string>de.local.klemmi</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Copyright © 2026 leonatwork. MIT License.</string>
</dict>
</plist>
PLIST
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Stamp a version: explicit VERSION wins, otherwise the newest git tag.
VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null || true)}"
if [[ -n "${VERSION:-}" ]]; then
  SHORT="${VERSION#v}"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $SHORT" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $SHORT" "$APP/Contents/Info.plist"
  echo "==> version $SHORT"
fi

echo "==> generating icon"
swift icon.swift "$APP/Contents/Resources/AppIcon.icns"

# Prefer the shared signing identity over ad-hoc. In CI it comes from CODESIGN_IDENTITY;
# locally it is picked up from the keychain if it has been imported there.
IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  for candidate in "leonatwork Code Signing" "Tappi Local Signing"; do
    if security find-identity -p codesigning 2>/dev/null | grep -q "$candidate"; then
      IDENTITY="$candidate"
      break
    fi
  done
  IDENTITY="${IDENTITY:--}"
fi
echo "==> codesign (identity: $IDENTITY)"
if ! codesign --force --deep --sign "$IDENTITY" "$APP"; then
  echo "!!  signing with '$IDENTITY' failed" >&2
  exit 1
fi
touch "$APP"

if [[ "${1:-}" == "--install" ]]; then
  echo "==> installing to /Applications"
  pkill -x Klemmi || true
  rm -rf /Applications/Klemmi.app
  cp -R "$APP" /Applications/Klemmi.app
  open /Applications/Klemmi.app
  echo "==> running from /Applications/Klemmi.app"
else
  echo "==> done: $APP"
fi
