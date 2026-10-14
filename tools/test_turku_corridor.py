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
        self.assertIn("loaded 10 missions", res.stdout)

    def test_cross_city_transfer_probe(self):
        env = os.environ.copy()
        env["MAP"] = "turku"
        env["SEED"] = "1337"
        env["CORRIDOR_TEST"] = "1"
        res = subprocess.run([str(BINARY), "game", "--headless", "15"], cwd=ROOT, env=env, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn("ALL CORRIDOR CHECKS PASSED", res.stdout)

    def test_cross_city_transfer_in_vehicle_loads_without_crash(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            save_file = Path(tmp) / "cross_city_transfer.lua"
            save_file.write_text("return { target_pos = {10, 20}, in_vehicle = true, wanted_stars = 2 }\n")
            env = os.environ.copy()
            env["MAP"] = "turku"
            env["SEED"] = "1337"
            res = subprocess.run([str(BINARY), "game", "--save-dir", str(tmp), "--headless", "5"], cwd=ROOT, env=env, capture_output=True, text=True)
            self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
            self.assertNotIn("attempt to call a nil value", res.stdout + res.stderr)
            self.assertNotIn("stack traceback", res.stdout + res.stderr)


if __name__ == "__main__":
    unittest.main()
