#!/usr/bin/env python3
"""Turku City Life (systems/city_life.lua):
Wave 4 market day and riverboat civic culture:
Kauppatori's iconic Torikahvila tent with morning coffee & possumunkki,
and Aurajoki's flagship riverboats (Svarte Rudolf, Donna, Majland) with
walkable Layer 0 gangways, decks, bar counters, and evening string lights.
"""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


class CityLifeTests(unittest.TestCase):
    def test_city_life_turku(self):
        env = dict(os.environ, MAP="turku", SEED="1337", CITY_LIFE_TEST="1")
        res = subprocess.run([str(BINARY), "game", "--headless", "40000"], cwd=ROOT, env=env,
                             capture_output=True, text=True, timeout=120)
        out = res.stdout + res.stderr
        self.assertEqual(res.returncode, 0, out[-3000:])
        self.assertNotIn("[lua:", out)
        self.assertIn("ALL CITY LIFE CHECKS PASSED", out, out[-3000:])


if __name__ == "__main__":
    unittest.main()
