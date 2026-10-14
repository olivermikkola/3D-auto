#!/usr/bin/env python3
"""Automated tests for Turku city map and cross-city corridor transitions."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


class TurkuCorridorTests(unittest.TestCase):
    def test_turku_map_loads_and_runs(self):
        env = os.environ.copy()
        env["MAP"] = "turku"
        env["SEED"] = "1337"
        res = subprocess.run([str(BINARY), "game", "--headless", "20"], cwd=ROOT, env=env, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn("map=turku", res.stdout)
        self.assertIn("loaded 9 missions", res.stdout)

    def test_cross_city_transfer_probe(self):
        env = os.environ.copy()
        env["MAP"] = "turku"
        env["SEED"] = "1337"
        env["CORRIDOR_TEST"] = "1"
        res = subprocess.run([str(BINARY), "game", "--headless", "15"], cwd=ROOT, env=env, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn("ALL CORRIDOR CHECKS PASSED", res.stdout)


if __name__ == "__main__":
    unittest.main()
