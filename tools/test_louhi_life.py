#!/usr/bin/env python3
"""Louhi's cars coming and going (systems/louhi_life.lua): you stand in a bay;
cars back out, drive away, come back down and park."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


class LouhiLifeTests(unittest.TestCase):
    def test_turku(self):
        env = dict(os.environ, MAP="turku", SEED="1337", LOUHI_LIFE_TEST="1")
        res = subprocess.run([str(BINARY), "game", "--headless", "40000"], cwd=ROOT, env=env,
                             capture_output=True, text=True, timeout=600)
        out = res.stdout + res.stderr
        self.assertEqual(res.returncode, 0, out[-3000:])
        self.assertNotIn("[lua:", out)
        self.assertIn("ALL LOUHI_LIFE CHECKS PASSED", out, out[-3000:])


if __name__ == "__main__":
    unittest.main()
