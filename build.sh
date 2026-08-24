#!/bin/bash
# Baut Klemmi.app nach ~/Applications
set -e
cd "$(dirname "$0")"
APP="$HOME/Applications/Klemmi.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O \
  Sources/Support.swift Sources/HistoryItem.swift Sources/HistoryStore.swift Sources/ClipboardMonitor.swift \
  Sources/Clipboard.swift Sources/HistoryList.swift Sources/StatusItem.swift Sources/main.swift \
  -framework AppKit \
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
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Klemmi – Zwischenablage-Verlauf</string>
</dict>
</plist>
PLIST

# Symbol erzeugen
swift icon.swift "$APP/Contents/Resources/AppIcon.icns"

codesign --force --deep -s - "$APP" 2>/dev/null || true
touch "$APP"
echo "Fertig: $APP"
