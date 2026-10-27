#!/usr/bin/env python3
"""Market day at Kauppatori: rows of stalls, and people browsing them by day."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


class MarketTests(unittest.TestCase):
    def test_market_day(self):
        env = dict(os.environ, MAP="turku", SEED="1337", MARKET_TEST="1")
        res = subprocess.run([str(BINARY), "game", "--headless", "20000"], cwd=ROOT, env=env, capture_output=True, text=True, timeout=600)
        out = res.stdout + res.stderr
        self.assertEqual(res.returncode, 0, out[-4000:])
        self.assertIn("MARKET_PROBE: PASSED", res.stdout, out[-4000:])


if __name__ == "__main__":
    unittest.main()
