#!/usr/bin/env python3
"""Under the Square (missions/12_under_the_square.lua), Oliver's chase route
as a mission, played through: the van robbed at Kauppatori, the robot drives
down Toriparkki's ramp, through to Louhi's hall and up its tunnel to
Ajurinkatu, then on foot into Logomo, where the cops lose you."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


class UnderSquareTests(unittest.TestCase):
    def test_turku(self):
        env = dict(os.environ, MAP="turku", SEED="1337", UNDER_SQUARE_TEST="1")
        res = subprocess.run([str(BINARY), "game", "--headless", "60000"], cwd=ROOT, env=env,
                             capture_output=True, text=True, timeout=400)
        out = res.stdout + res.stderr
        self.assertEqual(res.returncode, 0, out[-3000:])
        self.assertNotIn("[lua:", out)
        self.assertIn("ALL UNDER_SQUARE CHECKS PASSED", out, out[-3000:])


if __name__ == "__main__":
    unittest.main()
