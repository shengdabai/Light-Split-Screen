#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${1:?Pass a new absolute test work directory}"
[[ "$WORK" = /* && ! -e "$WORK" ]] || { echo 'Use a new absolute directory' >&2; exit 2; }
mkdir -p "$WORK/Fixture.app/Contents/MacOS"
CACHE="${TMPDIR:-/tmp}/qingfenping-swift-cache-$(id -u)"
mkdir -p "$CACHE"
python3 - "$ROOT" "$WORK" <<'PY2'
from pathlib import Path
import sys,plistlib
root,work=map(Path,sys.argv[1:]);source=(root/'Sources/main.swift').read_text();marker='\nlet application = NSApplication.shared\n';assert source.count(marker)==1
(work/'ProductionDelegate.swift').write_text(source.split(marker)[0])
(work/'Fixture.app/Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'local.tony.qingfenping.fixture','CFBundleExecutable':'Fixture','CFBundleName':'轻分屏开关验收窗口','CFBundlePackageType':'APPL'}))
PY2
xcrun swiftc -swift-version 5 -module-cache-path "$CACHE" "$ROOT/Tests/ControlFixture.swift" -o "$WORK/Fixture.app/Contents/MacOS/Fixture" -framework AppKit
codesign --force --sign - "$WORK/Fixture.app"
SOURCES=()
for FILE in "$ROOT"/Sources/*.swift; do [[ "$FILE" = "$ROOT/Sources/main.swift" ]] || SOURCES+=("$FILE"); done
xcrun swiftc -swift-version 5 -module-cache-path "$CACHE" "${SOURCES[@]}" "$WORK/ProductionDelegate.swift" "$ROOT/Tests/ControlIntegrationTests.swift" -o "$WORK/control-tests" -framework AppKit -framework ApplicationServices -framework Carbon
python3 - "$WORK" <<'PY2'
from pathlib import Path
import subprocess,time,sys
work=Path(sys.argv[1]);fixture=subprocess.Popen([str(work/'Fixture.app/Contents/MacOS/Fixture')],stdout=(work/'fixture.log').open('w'),stderr=subprocess.STDOUT)
try:
 time.sleep(.4)
 result=subprocess.run([str(work/'control-tests'),'--fixture-pid',str(fixture.pid)],timeout=35)
finally:
 fixture.terminate();fixture.wait(timeout=5)
sys.exit(result.returncode)
PY2
