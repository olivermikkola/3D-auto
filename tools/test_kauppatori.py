#!/usr/bin/env python3
"""Automated tests for Turun Kauppatori 500m slice, pavilions, and market stalls."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


class KauppatoriTests(unittest.TestCase):
    def test_kauppatori_slice(self):
        env = os.environ.copy()
        env["MAP"] = "turku"
        env["SEED"] = "1337"
        env["KAUPPATORI_TEST"] = "1"
        res = subprocess.run([str(BINARY), "game", "--headless", "30"], cwd=ROOT, env=env, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn("TORIPAVILJONGIT_OK", res.stdout)
        self.assertIn("MARKET_STALLS_OK", res.stdout)
        self.assertIn("TAXI_RANK_OK", res.stdout)
        self.assertIn("ALL KAUPPATORI CHECKS PASSED", res.stdout)


if __name__ == "__main__":
    unittest.main()
