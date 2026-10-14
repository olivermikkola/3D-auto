#!/usr/bin/env python3
"""Automated tests for Föli municipal buses and transit operations."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


class FoliBusTests(unittest.TestCase):
    def test_foli_bus_spawning_and_transit_mission(self):
        env = os.environ.copy()
        env["MAP"] = "raisio"
        env["SEED"] = "1337"
        env["FOLI_TEST"] = "1"
        res = subprocess.run([str(BINARY), "game", "--headless", "10"], cwd=ROOT, env=env, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertRegex(res.stdout, r"loaded \d+ missions")
        self.assertIn("ALL FOLI CHECKS PASSED", res.stdout)


if __name__ == "__main__":
    unittest.main()
