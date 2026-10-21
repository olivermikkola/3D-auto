#!/usr/bin/env python3
"""Street lamps give way to a car or bus at speed, and hold against a crawl (game/test/lamp_probe.lua)."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


class LampTests(unittest.TestCase):
    def test_cars_and_buses_knock_lamps_over(self):
        env = dict(os.environ, MAP="starter", SEED="1337", LAMP_TEST="1")
        res = subprocess.run([str(BINARY), "game", "--headless", "1200"], cwd=ROOT, env=env,
                             capture_output=True, text=True, timeout=300)
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn("LAMP TEST PASSED", res.stdout)


if __name__ == "__main__":
    unittest.main()
