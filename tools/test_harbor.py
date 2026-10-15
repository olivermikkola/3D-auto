#!/usr/bin/env python3
"""Automated tests for Turun linna (Turku Castle), S/S Bore museum ship, and harbor container berths."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


class HarborTests(unittest.TestCase):
    def test_turun_linna_and_harbor_slice(self):
        env = os.environ.copy()
        env["MAP"] = "turku"
        env["SEED"] = "1337"
        env["HARBOR_TEST"] = "1"
        res = subprocess.run([str(BINARY), "game", "--headless", "30"], cwd=ROOT, env=env, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn("CASTLE_OK", res.stdout)
        self.assertIn("BORE_SHIP_OK", res.stdout)
        self.assertIn("PORT_CRANES_OK", res.stdout)
        self.assertIn("CONTAINER_BERTHS_OK", res.stdout)
        self.assertIn("ALL CASTLE AND HARBOR CHECKS PASSED", res.stdout)


if __name__ == "__main__":
    unittest.main()
