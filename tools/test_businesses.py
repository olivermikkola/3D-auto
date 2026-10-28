#!/usr/bin/env python3
"""Businesses to buy: a grill, a kiosk and a taxi firm."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


@unittest.skipUnless(BINARY.exists(), "needs a release build")
class BusinessTests(unittest.TestCase):
    def test_businesses(self):
        env = dict(os.environ, MAP="turku", SEED="1337", BUSINESS_TEST="1")
        res = subprocess.run([str(BINARY), "game", "--headless", "3000"], cwd=ROOT, env=env, capture_output=True, text=True,
                             encoding="utf-8", errors="replace", timeout=600)
        out = res.stdout + res.stderr
        self.assertEqual(res.returncode, 0, out[-4000:])
        self.assertIn("BUSINESS_PROBE: PASSED", res.stdout, out[-4000:])


if __name__ == "__main__":
    unittest.main()
