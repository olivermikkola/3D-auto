#!/usr/bin/env python3
"""Kerbside parking: cars in the parking lanes of the streets that have
them, clear of the traffic lanes and crossings; you can get in one and
drive off; one hit hard is shoved; none on low quality."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


@unittest.skipUnless(BINARY.exists(), "needs a release build")
class ParkingTests(unittest.TestCase):
    def test_parked_cars(self):
        for name in ("turku",):
            with self.subTest(map=name):
                env = dict(os.environ, MAP=name, SEED="1337", PARKING_TEST="1")
                with tempfile.TemporaryDirectory() as d:
                    env["XDG_DATA_HOME"] = d
                    res = subprocess.run([str(BINARY), "game", "--headless", "2000"], cwd=ROOT, env=env,
                                         capture_output=True, text=True, encoding="utf-8", errors="replace",
                                         timeout=600)
                out = res.stdout + res.stderr
                self.assertEqual(res.returncode, 0, out)
                self.assertIn(f"PARKING_PROBE {name}: PASSED", out, out)


if __name__ == "__main__":
    unittest.main()
