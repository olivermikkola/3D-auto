#!/usr/bin/env python3
"""Kinds of car: sports cars, vans and taxis in traffic, each its own size
and pull (a sports car pulls hardest, a van least)."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


@unittest.skipUnless(BINARY.exists(), "needs a release build")
class CarKindTests(unittest.TestCase):
    def test_car_kinds(self):
        for name in ("starter", "turku"):
            with self.subTest(map=name):
                env = dict(os.environ, MAP=name, SEED="1337", CARKINDS_TEST="1")
                with tempfile.TemporaryDirectory() as d:
                    env["XDG_DATA_HOME"] = d
                    res = subprocess.run([str(BINARY), "game", "--headless", "3000"], cwd=ROOT, env=env,
                                         capture_output=True, text=True, encoding="utf-8", errors="replace",
                                         timeout=600)
                out = res.stdout + res.stderr
                self.assertEqual(res.returncode, 0, out)
                self.assertIn(f"CARKINDS_PROBE {name}: PASSED", out, out)


if __name__ == "__main__":
    unittest.main()
