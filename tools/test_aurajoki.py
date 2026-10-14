#!/usr/bin/env python3
"""Automated tests for Aurajoki river, bridges, and the Föri cable ferry in Turku."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


class AurajokiTests(unittest.TestCase):
    def test_aurajoki_bridges_and_fori_shuttle(self):
        env = os.environ.copy()
        env["MAP"] = "turku"
        env["SEED"] = "1337"
        env["AURAJOKI_TEST"] = "1"
        res = subprocess.run([str(BINARY), "game", "--headless", "30"], cwd=ROOT, env=env, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertRegex(res.stdout, r"AURAJOKI_OK bridges=\d+")
        self.assertIn("BOATS_AFLOAT_OK", res.stdout)
        self.assertIn("FORI_SHUTTLE_OK", res.stdout)
        self.assertIn("ALL AURAJOKI CHECKS PASSED", res.stdout)


if __name__ == "__main__":
    unittest.main()
