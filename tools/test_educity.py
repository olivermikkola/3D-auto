#!/usr/bin/env python3
"""EduCity (systems/educity.lua), Turku AMK at Kupittaa: walk in from
Joukahaisenkatu, the floors hold (down the Stairway of Skills to the
restaurant), coffee, lunch and the hackathon's pizza heal, out again, and the
cops lose you inside."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


class EduCityTests(unittest.TestCase):
    def test_turku(self):
        env = dict(os.environ, MAP="turku", SEED="1337", EDUCITY_TEST="1")
        res = subprocess.run([str(BINARY), "game", "--headless", "40000"], cwd=ROOT, env=env,
                             capture_output=True, text=True, timeout=120)
        out = res.stdout + res.stderr
        self.assertEqual(res.returncode, 0, out[-3000:])
        self.assertNotIn("[lua:", out)
        self.assertIn("ALL EDUCITY CHECKS PASSED", out, out[-3000:])


if __name__ == "__main__":
    unittest.main()
