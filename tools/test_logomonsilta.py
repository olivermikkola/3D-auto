#!/usr/bin/env python3
"""Logomonsilta (systems/landmarks.lua) can be crossed on foot: up the
station end's stairs, through the tube over the railway yard, down to
Logomo, back, and down to a platform."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


class LogomonsiltaTests(unittest.TestCase):
    def test_turku(self):
        env = dict(os.environ, MAP="turku", SEED="1337", LOGOMONSILTA_TEST="1")
        res = subprocess.run([str(BINARY), "game", "--headless", "60000"], cwd=ROOT, env=env,
                             capture_output=True, text=True, timeout=600)
        out = res.stdout + res.stderr
        self.assertEqual(res.returncode, 0, out[-3000:])
        self.assertNotIn("[lua:", out)
        self.assertIn("ALL LOGOMONSILTA CHECKS PASSED", out, out[-3000:])


if __name__ == "__main__":
    unittest.main()
