#!/usr/bin/env python3
"""Two pedestrians meeting head-on get past each other without stepping off the kerb."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


class PedPassingTests(unittest.TestCase):
    def run_probe(self, city):
        env = dict(os.environ, MAP=city, SEED="1337", PED_PASS_TEST="1")
        res = subprocess.run([str(BINARY), "game", "--headless", "1200"], cwd=ROOT, env=env,
                             capture_output=True, text=True, timeout=600)
        out = res.stdout + res.stderr
        self.assertEqual(res.returncode, 0, out)
        self.assertNotIn("[lua:", out)
        self.assertIn("PED_PASS_OK", out, out[-3000:])

    def test_raisio(self):
        self.run_probe("raisio")

    def test_turku(self):
        self.run_probe("turku")


if __name__ == "__main__":
    unittest.main()
