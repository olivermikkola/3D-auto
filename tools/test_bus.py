#!/usr/bin/env python3
"""Pöli bus driver: on Turku a Pöli bus at the bus station; in it a route of
four real bus stops, people waiting, the GPS leads on, doors open lets them
on and pays (less when late), the last stop a bonus; leaving ends it. Maps
without bus stops have no bus."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


@unittest.skipUnless(BINARY.exists(), "needs a release build")
class BusTests(unittest.TestCase):
    def test_bus_routes(self):
        for name in ("turku", "raisio", "starter"):
            with self.subTest(map=name):
                env = dict(os.environ, MAP=name, SEED="1337", BUS_TEST="1")
                with tempfile.TemporaryDirectory() as d:
                    env["XDG_DATA_HOME"] = d
                    res = subprocess.run([str(BINARY), "game", "--headless", "120000"], cwd=ROOT, env=env,
                                         capture_output=True, text=True, encoding="utf-8", errors="replace",
                                         timeout=1800)
                out = res.stdout + res.stderr
                self.assertEqual(res.returncode, 0, out)
                self.assertIn(f"BUS_PROBE {name}: PASSED", out, out)


if __name__ == "__main__":
    unittest.main()
