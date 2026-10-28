#!/usr/bin/env python3
"""Taking a bike: enter beside a rider pulls them off and you ride it, at a
bike's speed and upright; a knocked off rider's bike can be picked up."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


@unittest.skipUnless(BINARY.exists(), "needs a release build")
class BikeTests(unittest.TestCase):
    def test_take_a_bike(self):
        env = dict(os.environ, MAP="turku", SEED="1337", BIKE_TEST="1")
        with tempfile.TemporaryDirectory() as d:
            env["XDG_DATA_HOME"] = d
            res = subprocess.run([str(BINARY), "game", "--headless", "4000"], cwd=ROOT, env=env, capture_output=True,
                                 text=True, encoding="utf-8", errors="replace", timeout=600)
        out = res.stdout + res.stderr
        self.assertEqual(res.returncode, 0, out[-3000:])
        self.assertNotIn("[lua:", out, out[-3000:])
        self.assertIn("BIKE_PROBE: PASSED", out, out[-3000:])


if __name__ == "__main__":
    unittest.main()
