#!/usr/bin/env python3
"""Outdoor stairs from the map (Puolalanportaat down Puolalanmäki to Louhi,
the tallest elsewhere in Turku) can be run up and down on foot."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


class StairsTests(unittest.TestCase):
    def test_turku(self):
        env = dict(os.environ, MAP="turku", SEED="1337", STAIRS_TEST="1")
        res = subprocess.run([str(BINARY), "game", "--headless", "60000"], cwd=ROOT, env=env,
                             capture_output=True, text=True, timeout=600)
        out = res.stdout + res.stderr
        self.assertEqual(res.returncode, 0, out[-3000:])
        self.assertNotIn("[lua:", out)
        self.assertIn("ALL STAIRS CHECKS PASSED", out, out[-3000:])
        self.assertIn("STAIRS: 24 runs, 0 failed", out)


if __name__ == "__main__":
    unittest.main()
