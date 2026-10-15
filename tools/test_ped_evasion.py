#!/usr/bin/env python3
"""Automated tests for pedestrian sidewalk restrictions and traffic evasion."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


class PedEvasionTests(unittest.TestCase):
    def test_ped_evasion_turku(self):
        env = os.environ.copy()
        env["MAP"] = "turku"
        env["SEED"] = "1337"
        env["PED_EVASION_TEST"] = "1"
        res = subprocess.run([str(BINARY), "game", "--headless", "30"], cwd=ROOT, env=env, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn("SIDEWALK_FILTER_OK", res.stdout)
        self.assertIn("PED_SCARE_OK", res.stdout)
        self.assertIn("ALL PED EVASION CHECKS PASSED", res.stdout)

    def test_ped_evasion_raisio(self):
        env = os.environ.copy()
        env["MAP"] = "raisio"
        env["SEED"] = "1337"
        env["PED_EVASION_TEST"] = "1"
        res = subprocess.run([str(BINARY), "game", "--headless", "30"], cwd=ROOT, env=env, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn("SIDEWALK_FILTER_OK", res.stdout)
        self.assertIn("ALL PED EVASION CHECKS PASSED", res.stdout)


if __name__ == "__main__":
    unittest.main()
