#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/dist/轻分屏.app}"
CACHE="$(mktemp -d "${TMPDIR:-/tmp}/qingfenping-swift-cache.XXXXXX")"
trap 'rm -rf "$CACHE"' EXIT
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources" "$CACHE"
xcrun swiftc -swift-version 5 -Osize -whole-module-optimization -module-name QingFenPing \
  -target arm64-apple-macosx13.0 -module-cache-path "$CACHE" \
  "$ROOT"/Sources/*.swift -o "$OUT/Contents/MacOS/QingFenPing" \
  -framework AppKit -framework ApplicationServices -framework Carbon
cat > "$OUT/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.tony.qingfenping</string>
<key>CFBundleName</key><string>轻分屏</string>
<key>CFBundleDisplayName</key><string>轻分屏</string>
<key>CFBundleExecutable</key><string>QingFenPing</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.0</string>
<key>CFBundleVersion</key><string>6</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
if [[ -f "$ROOT/Assets/AppIcon.icns" ]]; then
  cp "$ROOT/Assets/AppIcon.icns" "$OUT/Contents/Resources/AppIcon.icns"
fi
# Finder may attach metadata to newly created bundles in Desktop/iCloud.
# Remove only signing-incompatible metadata from this generated bundle.
/usr/bin/xattr -dr com.apple.FinderInfo "$OUT" 2>/dev/null || true
/usr/bin/xattr -dr com.apple.ResourceFork "$OUT" 2>/dev/null || true
/usr/bin/codesign --force --sign - "$OUT"
/usr/bin/codesign --verify --strict "$OUT"
/usr/bin/plutil -lint "$OUT/Contents/Info.plist"
/usr/bin/du -sh "$OUT"
