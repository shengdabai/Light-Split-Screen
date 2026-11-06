#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP="$(mktemp -d "${TMPDIR:-/tmp}/qingfenping-test.XXXXXX")"
CACHE="${TMPDIR:-/tmp}/qingfenping-swift-cache-$(id -u)"
mkdir -p "$CACHE"
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
# Only this script's disposable executables are removed.
rm "$TEMP/layout-tests" "$TEMP/shortcut-tests" "$TEMP/auto-layout-tests" "$TEMP/geometry-property-tests" "$TEMP/window-engine-tests"
rmdir "$TEMP"
