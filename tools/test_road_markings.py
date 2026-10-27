#!/usr/bin/env python3
"""Turku's roads get their markings beyond the center line: stop lines at
the traffic lights, solid edge lines along the main roads."""
import os
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


@unittest.skipUnless(BINARY.exists(), "needs a release build")
class RoadMarkingTests(unittest.TestCase):
    def test_marking_counts(self):
        env = dict(os.environ, MAP="turku", SEED="1337")
        res = subprocess.run([str(BINARY), "game", "--headless", "5"], cwd=ROOT, env=env, capture_output=True,
                             text=True, encoding="utf-8", errors="replace", timeout=600)
        out = res.stdout + res.stderr
        self.assertEqual(res.returncode, 0, out)
        m = re.search(r"road markings: (\d+) stop lines, (\d+) edge line pieces", out)
        self.assertIsNotNone(m, out[-2000:])
        self.assertGreater(int(m.group(1)), 300)
        self.assertGreater(int(m.group(2)), 5000)


if __name__ == "__main__":
    unittest.main()
