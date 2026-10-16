#!/usr/bin/env python3
"""Each vehicle class has its own top speed and pull (game/test/speed_probe.lua)."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


class VehicleClassTests(unittest.TestCase):
    def test_bus_and_pasi_are_slower_than_a_car(self):
        env = dict(os.environ, MAP="starter", SEED="1337", SPEED_TEST="1")
        res = subprocess.run([str(BINARY), "game", "--headless", "1800"], cwd=ROOT, env=env,
                             capture_output=True, text=True, timeout=300)
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn("SPEED TEST PASSED", res.stdout)


if __name__ == "__main__":
    unittest.main()
