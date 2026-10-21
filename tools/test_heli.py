#!/usr/bin/env python3
"""Police helicopter: at four stars it flies in, sees you in the open but
not under a roof, and leaves under four stars."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


@unittest.skipUnless(BINARY.exists(), "needs a release build")
class HeliTests(unittest.TestCase):
    def test_police_helicopter(self):
        for name in ("turku", "starter"):
            with self.subTest(map=name):
                env = dict(os.environ, MAP=name, SEED="1337", HELI_TEST="1")
                with tempfile.TemporaryDirectory() as d:
                    env["XDG_DATA_HOME"] = d
                    res = subprocess.run([str(BINARY), "game", "--headless", "6000"], cwd=ROOT, env=env,
                                         capture_output=True, text=True, encoding="utf-8", errors="replace",
                                         timeout=600)
                out = res.stdout + res.stderr
                self.assertEqual(res.returncode, 0, out)
                self.assertIn(f"HELI_PROBE {name}: PASSED", out, out)


if __name__ == "__main__":
    unittest.main()
