#!/usr/bin/env python3
"""Drive sweep: the traffic AI drives a car down every fourth road of each
map (DRIVE_SWEEP=1, DRIVE_SWEEP_EVERY=4) and counts the ones that get into
trouble: stuck, off their wheels, thrown up, fallen through, or too slow."""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")

# Cars in trouble out of ~1700 drives per map. With traffic in a fixed 3.2 m
# lane (wheels on the kerb of a 7.3 m street, off the asphalt of a 6 m one)
# it was Turku 70, Raisio 46; now 6 and 3. The rest are single cars, some
# at the map's edge. Lower these as they're fixed; never raise them.
TROUBLE_MAX = {"turku": 12, "raisio": 12}


@unittest.skipUnless(BINARY.exists(), "needs a release build")
class DriveSweepTests(unittest.TestCase):
    def test_maps(self):
        for name, most in TROUBLE_MAX.items():
            with self.subTest(map=name):
                env = dict(os.environ, MAP=name, SEED="1337", DRIVE_SWEEP="1", DRIVE_SWEEP_EVERY="4")
                with tempfile.TemporaryDirectory() as d:
                    env["XDG_DATA_HOME"] = d
                    res = subprocess.run([str(BINARY), "game", "--headless", "2000000"], cwd=ROOT, env=env,
                                         capture_output=True, text=True, timeout=900)
                out = res.stdout + res.stderr
                self.assertEqual(res.returncode, 0, out)
                self.assertNotIn("[lua:", out)
                m = re.search(r"DRIVE_SWEEP: (\d+) drives, (\d+) in trouble", out)
                self.assertTrue(m, out)
                self.assertGreater(int(m[1]), 1000)
                self.assertLessEqual(int(m[2]), most, out)


if __name__ == "__main__":
    unittest.main()
