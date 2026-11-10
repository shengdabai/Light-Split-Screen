#!/bin/bash
# Whole-project compile gate. It type-checks every file in Sources/ without writing any binary or .app, then runs the
# unit and property tests. It never calls build.sh and never touches ~/Applications/轻分屏.app: rebuilding the installed
# app makes macOS revoke its Accessibility permission.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# A shared predictable path allows other local users to seed compiler modules.
CACHE="$(mktemp -d "${TMPDIR:-/tmp}/qingfenping-swift-cache.XXXXXX")"
trap 'rm -rf "$CACHE"' EXIT
xcrun swiftc -swift-version 5 -typecheck -target arm64-apple-macosx13.0 -module-cache-path "$CACHE" "$ROOT"/Sources/*.swift
echo "PASS typecheck: $(ls "$ROOT"/Sources/*.swift | wc -l | tr -d ' ') Sources/*.swift files, no output files"
"$ROOT/scripts/test.sh"
