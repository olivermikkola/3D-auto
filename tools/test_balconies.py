#!/usr/bin/env python3
"""Turku's blocks of flats get balconies on their sunny walls."""
import os
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


@unittest.skipUnless(BINARY.exists(), "needs a release build")
class BalconyTests(unittest.TestCase):
    def test_flats_have_balconies(self):
        env = dict(os.environ, MAP="turku", SEED="1337")
        res = subprocess.run([str(BINARY), "game", "--headless", "5"], cwd=ROOT, env=env, capture_output=True,
                             text=True, encoding="utf-8", errors="replace", timeout=600)
        out = res.stdout + res.stderr
        self.assertEqual(res.returncode, 0, out)
        m = re.search(r"balconies: (\d+)", out)
        self.assertIsNotNone(m, out[-2000:])
        self.assertGreater(int(m.group(1)), 10000)


if __name__ == "__main__":
    unittest.main()
