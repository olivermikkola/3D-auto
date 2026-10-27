#!/usr/bin/env python3
"""People wait at the bus shelters, and Föli buses stop to let them on."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


@unittest.skipUnless(BINARY.exists(), "needs a release build")
class BusStopsTests(unittest.TestCase):
    def test_bus_stops(self):
        env = dict(os.environ, MAP="turku", SEED="1337", BUSSTOPS_TEST="1")
        res = subprocess.run([str(BINARY), "game", "--headless", "30000"], cwd=ROOT, env=env, capture_output=True, text=True,
                             encoding="utf-8", errors="replace", timeout=900)
        out = res.stdout + res.stderr
        self.assertEqual(res.returncode, 0, out[-4000:])
        self.assertIn("BUSSTOPS_PROBE: PASSED", res.stdout, out[-4000:])


if __name__ == "__main__":
    unittest.main()
