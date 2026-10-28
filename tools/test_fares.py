#!/usr/bin/env python3
"""Taxi fares: in a cab in free roam a fare calls from a real place near you,
the GPS leads to them and on to where they go, the fare is by the distance,
a knock cuts the tip, a star or leaving the cab calls it off, and at night
the bars call. Not in an ordinary car, nor on a map without places."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


@unittest.skipUnless(BINARY.exists(), "needs a release build")
class FaresTests(unittest.TestCase):
    def test_fares_on_every_kind_of_map(self):
        for name in ("turku", "raisio", "starter"):
            with self.subTest(map=name):
                # (FARES_TRACE: where the cab is every 2 s, shown if it fails.)
                env = dict(os.environ, MAP=name, SEED="1337", FARES_TEST="1", FARES_TRACE="1")
                with tempfile.TemporaryDirectory() as d:
                    env["XDG_DATA_HOME"] = d
                    res = subprocess.run([str(BINARY), "game", "--headless", "90000"], cwd=ROOT, env=env,
                                         capture_output=True, text=True, encoding="utf-8", errors="replace",
                                         timeout=1500)
                out = res.stdout + res.stderr
                self.assertEqual(res.returncode, 0, out)
                self.assertIn(f"FARES_PROBE {name}: PASSED", out, out)


if __name__ == "__main__":
    unittest.main()
