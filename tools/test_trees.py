#!/usr/bin/env python3
"""Turku's trees from the aerial photo: as many as it shows, none on a road
or in the river, thinned by the quality setting, and solid to drive into
(game/test/trees_probe.lua)."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


@unittest.skipUnless(BINARY.exists(), "needs a release build")
class TreeTests(unittest.TestCase):
    def test_photo_trees(self):
        env = dict(os.environ, MAP="turku", SEED="1337", TREES_TEST="1")
        res = subprocess.run([str(BINARY), "game", "--headless", "1800"], cwd=ROOT, env=env, capture_output=True,
                             text=True, encoding="utf-8", errors="replace", timeout=900)
        out = res.stdout + res.stderr
        self.assertIn("TREES TEST PASSED", out, out[-3000:])


if __name__ == "__main__":
    unittest.main()
