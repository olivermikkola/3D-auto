#!/usr/bin/env python3
"""Player sweep: the player's car, driven with the player's controls by a
robot, down every 48th road of each map and round the corner at its end
(PLAYER_SWEEP=1, PLAYER_SWEEP_EVERY=48), counting the drives that get into
trouble: stuck, off its wheels, thrown up, fallen through, off the road,
lost, or too slow. (Every 8th road takes ~13 minutes a map: run that by
hand, PLAYER_SWEEP=1 MAP=raisio auto game --headless 9000000.)"""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")

# Every 8th road: Turku 6 of 692, Raisio 14 of 744 (8 at street lamps just
# past sharp bends; 5 once those lamps are moved). Every 48th: Turku 3 of
# 115, Raisio 1 of 122, with room for other machines. Lower
# these as things are fixed; never raise them.
TROUBLE_MAX = {"turku": 6, "raisio": 4}


@unittest.skipUnless(BINARY.exists(), "needs a release build")
class PlayerSweepTests(unittest.TestCase):
    def test_maps(self):
        for name, most in TROUBLE_MAX.items():
            with self.subTest(map=name):
                env = dict(os.environ, MAP=name, SEED="1337", PLAYER_SWEEP="1", PLAYER_SWEEP_EVERY="48")
                with tempfile.TemporaryDirectory() as d:
                    env["XDG_DATA_HOME"] = d
                    res = subprocess.run([str(BINARY), "game", "--headless", "3000000"], cwd=ROOT, env=env,
                                         capture_output=True, text=True, encoding="utf-8", timeout=900)
                out = res.stdout + res.stderr
                self.assertEqual(res.returncode, 0, out[-3000:])
                self.assertNotIn("[lua:", out)
                self.assertIn(f"map={name} ", out)
                self.assertNotIn("reloaded", out)
                m = re.search(r"PLAYER_SWEEP: (\d+) drives, (\d+) in trouble", out)
                self.assertTrue(m, out[-3000:])
                self.assertGreater(int(m[1]), 80)
                self.assertLessEqual(int(m[2]), most, out[-3000:])


if __name__ == "__main__":
    unittest.main()
