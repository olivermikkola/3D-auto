#!/usr/bin/env python3
"""Losing the cops takes longer the more stars (game/test/wanted_probe.lua)."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


class WantedEscapeTests(unittest.TestCase):
    def test_escape_time_scales_with_stars(self):
        env = dict(os.environ, MAP="starter", SEED="1337", WANTED_TEST="1")
        res = subprocess.run([str(BINARY), "game", "--headless", "10"], cwd=ROOT, env=env,
                             capture_output=True, text=True, timeout=120)
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn("WANTED TEST PASSED", res.stdout)


if __name__ == "__main__":
    unittest.main()
