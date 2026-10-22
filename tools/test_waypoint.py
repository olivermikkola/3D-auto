#!/usr/bin/env python3
"""Waypoint: on the map, Enter or a click sets one and Backspace clears it,
the GPS heads for it before any blip, a car driven along the GPS line gets
there, and it clears itself on arrival."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


@unittest.skipUnless(BINARY.exists(), "needs a release build")
class WaypointTests(unittest.TestCase):
    def test_waypoint_on_every_kind_of_map(self):
        for name in ("turku", "raisio", "starter"):
            with self.subTest(map=name):
                env = dict(os.environ, MAP=name, SEED="1337", WAYPOINT_TEST="1")
                with tempfile.TemporaryDirectory() as d:
                    env["XDG_DATA_HOME"] = d
                    res = subprocess.run([str(BINARY), "game", "--headless", "60000"], cwd=ROOT, env=env,
                                         capture_output=True, text=True, encoding="utf-8", errors="replace",
                                         timeout=900)
                out = res.stdout + res.stderr
                self.assertEqual(res.returncode, 0, out)
                self.assertIn(f"WAYPOINT_PROBE {name}: PASSED", out, out)


if __name__ == "__main__":
    unittest.main()
