#!/usr/bin/env python3
"""Automated tests for Turku Castle, Buster speedboat, and Archipelago Heist mission."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


class ArchipelagoHeistTests(unittest.TestCase):
    def test_speedboat_and_archipelago_heist(self):
        env = os.environ.copy()
        env["MAP"] = "turku"
        env["SEED"] = "1337"
        env["HEIST_TEST"] = "1"
        res = subprocess.run([str(BINARY), "game", "--headless", "25"], cwd=ROOT, env=env, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn("SPEEDBOAT_SPAWN_OK", res.stdout)
        self.assertIn("MISSION_ARCHIPELAGO_OK", res.stdout)
        self.assertIn("ALL HEIST CHECKS PASSED", res.stdout)


if __name__ == "__main__":
    unittest.main()
