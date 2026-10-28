#!/usr/bin/env python3
"""Turku's cycle paths are painted: bicycles along them, and the squares of
a cycle crossing where one crosses a street."""
import os
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


@unittest.skipUnless(BINARY.exists(), "needs a release build")
class CyclePathTests(unittest.TestCase):
    def test_paint_counts(self):
        env = dict(os.environ, MAP="turku", SEED="1337")
        res = subprocess.run([str(BINARY), "game", "--headless", "5"], cwd=ROOT, env=env, capture_output=True,
                             text=True, encoding="utf-8", errors="replace", timeout=600)
        out = res.stdout + res.stderr
        self.assertEqual(res.returncode, 0, out)
        m = re.search(r"cycle paths: (\d+) bicycles painted, (\d+) crossings", out)
        self.assertIsNotNone(m, out[-2000:])
        self.assertGreater(int(m.group(1)), 1000)
        self.assertGreater(int(m.group(2)), 150)


if __name__ == "__main__":
    unittest.main()
