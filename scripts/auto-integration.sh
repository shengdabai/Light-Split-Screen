#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP="$(mktemp -d "${TMPDIR:-/tmp}/qingfenping-auto.XXXXXX")"
CACHE="${TMPDIR:-/tmp}/qingfenping-swift-cache-$(id -u)"
mkdir -p "$TEMP/Fixture.app/Contents/MacOS" "$CACHE"
FIXTURE_PID=""
cleanup() {
  if [[ -n "$FIXTURE_PID" ]]; then kill -TERM "$FIXTURE_PID" 2>/dev/null || true; fi
  rm -f "$TEMP/auto-tests" "$TEMP/Fixture.app/Contents/MacOS/Fixture" "$TEMP/Fixture.app/Contents/Info.plist" "$TEMP/Fixture.app/Contents/_CodeSignature/CodeResources"
  rmdir "$TEMP/Fixture.app/Contents/_CodeSignature" "$TEMP/Fixture.app/Contents/MacOS" "$TEMP/Fixture.app/Contents" "$TEMP/Fixture.app" "$TEMP" 2>/dev/null || true
}
trap cleanup EXIT
xcrun swiftc -swift-version 5 -module-cache-path "$CACHE" "$ROOT/Tests/Fixture.swift" -o "$TEMP/Fixture.app/Contents/MacOS/Fixture" -framework AppKit
cat > "$TEMP/Fixture.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>local.tony.qingfenping.fixture</string><key>CFBundleExecutable</key><string>Fixture</string><key>CFBundleName</key><string>轻分屏验收窗口</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
codesign --force --sign - "$TEMP/Fixture.app"
xcrun swiftc -swift-version 5 -module-cache-path "$CACHE" "$ROOT/Sources/Layout.swift" "$ROOT/Sources/WindowEngine.swift" "$ROOT/Sources/AutoLayout.swift" "$ROOT/Sources/AutoArrange.swift" "$ROOT/Tests/AutoIntegrationTests.swift" -o "$TEMP/auto-tests" -framework AppKit -framework ApplicationServices
"$TEMP/Fixture.app/Contents/MacOS/Fixture" --staged-auto &
FIXTURE_PID=$!
sleep 0.35
"$TEMP/auto-tests" "$FIXTURE_PID"
