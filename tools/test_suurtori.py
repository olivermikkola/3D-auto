#!/usr/bin/env python3
"""Automated tests for Vanha Suurtori & Tuomiokirkko 500m slice."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


class SuurtoriTests(unittest.TestCase):
    def test_suurtori_slice(self):
        env = os.environ.copy()
        env["MAP"] = "turku"
        env["SEED"] = "1337"
        env["SUURTORI_TEST"] = "1"
        res = subprocess.run([str(BINARY), "game", "--headless", "30"], cwd=ROOT, env=env, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn("TUOMIOKIRKKO_CATHEDRAL_OK", res.stdout)
        self.assertIn("BRINKKALA_BALCONY_OK", res.stdout)
        self.assertIn("PORTHAN_MONUMENT_OK", res.stdout)
        self.assertIn("SUURTORI_PLAZA_OK", res.stdout)
        self.assertIn("ALL SUURTORI CHECKS PASSED", res.stdout)


if __name__ == "__main__":
    unittest.main()
