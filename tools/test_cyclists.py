#!/usr/bin/env python3
"""Cyclists on the cycle paths."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


@unittest.skipUnless(BINARY.exists(), "needs a release build")
class CyclistsTests(unittest.TestCase):
    def test_cyclists(self):
        env = dict(os.environ, MAP="turku", SEED="1337", CYCLISTS_TEST="1")
        res = subprocess.run([str(BINARY), "game", "--headless", "6000"], cwd=ROOT, env=env, capture_output=True, text=True,
                             encoding="utf-8", errors="replace", timeout=600)
        out = res.stdout + res.stderr
        self.assertEqual(res.returncode, 0, out[-4000:])
        self.assertIn("CYCLISTS_PROBE: PASSED", res.stdout, out[-4000:])


if __name__ == "__main__":
    unittest.main()
