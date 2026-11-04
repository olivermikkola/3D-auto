#!/usr/bin/env python3
"""Turun Kauppahalli (systems/kauppahalli.lua): walk into Finland's second oldest
market hall on Eerikinkatu, browse food stalls, buy warm food/coffee to heal,
walk out onto Linnankatu, and evade police in Layer 1."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


class KauppahalliTests(unittest.TestCase):
    def test_turku(self):
        env = dict(os.environ, MAP="turku", SEED="1337", KAUPPAHALLI_TEST="1")
        res = subprocess.run([str(BINARY), "game", "--headless", "40000"], cwd=ROOT, env=env,
                             capture_output=True, text=True, timeout=120)
        out = res.stdout + res.stderr
        self.assertEqual(res.returncode, 0, out[-3000:])
        self.assertNotIn("[lua:", out)
        self.assertIn("ALL KAUPPAHALLI CHECKS PASSED", out, out[-3000:])


if __name__ == "__main__":
    unittest.main()
