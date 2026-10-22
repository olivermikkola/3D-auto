#!/usr/bin/env python3
"""GPS: routes between random spots are real drives (one-way streets the
right way, the goal at the end, no longer than the shortest way between
their junctions), quick on a whole town, none to mission start markers, and
the player's car driven along the GPS line as it's redrawn gets there."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


@unittest.skipUnless(BINARY.exists(), "needs a release build")
class GpsTests(unittest.TestCase):
    def test_gps_on_every_kind_of_map(self):
        for name in ("turku", "raisio", "starter"):
            with self.subTest(map=name):
                env = dict(os.environ, MAP=name, SEED="1337", GPS_TEST="1")
                with tempfile.TemporaryDirectory() as d:
                    env["XDG_DATA_HOME"] = d
                    res = subprocess.run([str(BINARY), "game", "--headless", "60000"], cwd=ROOT, env=env,
                                         capture_output=True, text=True, encoding="utf-8", errors="replace",
                                         timeout=900)
                out = res.stdout + res.stderr
                self.assertEqual(res.returncode, 0, out)
                self.assertIn(f"GPS_PROBE {name}: PASSED", out, out)


if __name__ == "__main__":
    unittest.main()
