#!/usr/bin/env python3
"""Uusi Apteekki (systems/pub.lua): walk into the historic 1907 pharmacy pub
on Kaskenkatu, order craft beer to recover health, play darts, and lay low
from police pursuit in Layer 1."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


class PubTests(unittest.TestCase):
    def test_turku(self):
        env = dict(os.environ, MAP="turku", SEED="1337", PUB_TEST="1")
        res = subprocess.run([str(BINARY), "game", "--headless", "40000"], cwd=ROOT, env=env,
                             capture_output=True, text=True, timeout=120)
        out = res.stdout + res.stderr
        self.assertEqual(res.returncode, 0, out[-3000:])
        self.assertNotIn("[lua:", out)
        self.assertIn("ALL PUB CHECKS PASSED", out, out[-3000:])


if __name__ == "__main__":
    unittest.main()
