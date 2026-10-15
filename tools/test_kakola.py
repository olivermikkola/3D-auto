#!/usr/bin/env python3
"""Automated tests for Kakolanmäki 500m slice, funicular slope elevator, and hilltop fortress."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


class KakolaTests(unittest.TestCase):
    def test_kakolanmaki_and_funicular_movement(self):
        env = os.environ.copy()
        env["MAP"] = "turku"
        env["SEED"] = "1337"
        env["KAKOLA_TEST"] = "1"
        res = subprocess.run([str(BINARY), "game", "--headless", "30"], cwd=ROOT, env=env, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn("FUNIKULAARI_SPAWN_OK", res.stdout)
        self.assertIn("FUNIKULAARI_MOVEMENT_OK", res.stdout)
        self.assertIn("ALL KAKOLA CHECKS PASSED", res.stdout)


if __name__ == "__main__":
    unittest.main()
