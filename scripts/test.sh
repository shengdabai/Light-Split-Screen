#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP="$(mktemp -d "${TMPDIR:-/tmp}/qingfenping-test.XXXXXX")"
CACHE="$TEMP/swift-cache"
# TEMP was atomically created by mktemp; remove only this run's generated files.
trap 'rm -rf "$TEMP"' EXIT
mkdir -m 700 "$CACHE"
xcrun swiftc -swift-version 5 -module-cache-path "$CACHE" "$ROOT/Sources/Layout.swift" "$ROOT/Tests/LayoutTests.swift" -o "$TEMP/layout-tests"
"$TEMP/layout-tests"
xcrun swiftc -swift-version 5 -module-cache-path "$CACHE" "$ROOT/Sources/Layout.swift" "$ROOT/Sources/Theme.swift" "$ROOT/Sources/Shortcuts.swift" "$ROOT/Tests/ShortcutTests.swift" -framework AppKit -framework Carbon -o "$TEMP/shortcut-tests"
"$TEMP/shortcut-tests"
xcrun swiftc -swift-version 5 -module-cache-path "$CACHE" "$ROOT/Sources/Layout.swift" "$ROOT/Sources/AutoLayout.swift" "$ROOT/Tests/AutoLayoutTests.swift" -o "$TEMP/auto-layout-tests"
"$TEMP/auto-layout-tests"
xcrun swiftc -swift-version 5 -module-cache-path "$CACHE" "$ROOT/Sources/Layout.swift" "$ROOT/Sources/AutoLayout.swift" "$ROOT/Tests/GeometryPropertyTests.swift" -o "$TEMP/geometry-property-tests"
"$TEMP/geometry-property-tests"
xcrun swiftc -swift-version 5 -module-cache-path "$CACHE" "$ROOT/Sources/Layout.swift" "$ROOT/Sources/WindowEngine.swift" "$ROOT/Tests/WindowEngineTests.swift" -framework AppKit -framework ApplicationServices -o "$TEMP/window-engine-tests"
"$TEMP/window-engine-tests"
python3 "$ROOT/Tests/ScriptSecurityTests.py"
