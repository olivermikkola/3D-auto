#!/usr/bin/env python3
"""Automated tests for Sisu XA-180 Pasi APC, military response, and Pansio Heist mission."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


class SisuPasiTests(unittest.TestCase):
    def test_pasi_vehicle_and_mission_loaded(self):
        env = os.environ.copy()
        env["MAP"] = "raisio"
        env["SEED"] = "1337"
        env["PASI_TEST"] = "1"
        res = subprocess.run([str(BINARY), "game", "--headless", "10"], cwd=ROOT, env=env, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn("ALL PASI PROBE CHECKS PASSED", res.stdout)


if __name__ == "__main__":
    unittest.main()
