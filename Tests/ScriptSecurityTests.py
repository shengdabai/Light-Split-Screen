"""Exercise shell failure paths without compiling or launching any GUI."""
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = (
    "test.sh", "check.sh", "build.sh", "integration.sh",
    "auto-integration.sh", "control-integration.sh",
)


class ScriptSecurityTests(unittest.TestCase):
    def test_private_module_caches_and_failure_cleanup(self):
        for script in SCRIPTS:
            with self.subTest(script=script), tempfile.TemporaryDirectory() as directory:
                work = Path(directory)
                temporary = work / "temporary files"
                temporary.mkdir()
                # Simulate another account pre-creating the old predictable cache.
                poisoned = work / "untrusted-cache"
                poisoned.mkdir()
                sentinel = poisoned / "keep"
                sentinel.write_text("untrusted module")
                (temporary / f"qingfenping-swift-cache-{os.getuid()}").symlink_to(poisoned)
                binaries = work / "bin"
                binaries.mkdir()
                capture = work / "capture.json"
                compiler = binaries / "xcrun"
                compiler.write_text(
                    "#!/usr/bin/env python3\n"
                    "import json, os, pathlib, stat, sys\n"
                    "args = sys.argv[1:]\n"
                    "cache = pathlib.Path(args[args.index('-module-cache-path') + 1])\n"
                    "json.dump({'path': str(cache), 'resolved': str(cache.resolve()), "
                    "'mode': stat.S_IMODE(cache.stat().st_mode)}, "
                    "open(os.environ['CACHE_CAPTURE'], 'w'))\n"
                    "(cache / 'partial-module').write_text('failed compilation')\n"
                    "sys.exit(71)\n"
                )
                compiler.chmod(0o700)
                env = dict(os.environ, TMPDIR=str(temporary), CACHE_CAPTURE=str(capture))
                env["PATH"] = str(binaries) + os.pathsep + env["PATH"]
                command = ["bash", str(ROOT / "scripts" / script)]
                if script == "control-integration.sh":
                    command.append(str(work / "control"))
                elif script == "build.sh":
                    command.append(str(work / "output.app"))
                result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=15)
                self.assertEqual(result.returncode, 71, result.stdout + result.stderr)
                data = json.loads(capture.read_text())
                self.assertNotEqual(Path(data["resolved"]), poisoned.resolve())
                self.assertEqual(data["mode"] & (stat.S_IRWXG | stat.S_IRWXO), 0)
                self.assertFalse(Path(data["path"]).exists(), "failed compiler leaked its cache")
                self.assertEqual(list(poisoned.iterdir()), [sentinel])
                self.assertEqual(sentinel.read_text(), "untrusted module")
                self.assertEqual(len(list(temporary.iterdir())), 1, "failed test leaked temporary files")


if __name__ == "__main__":
    unittest.main()
