#!/usr/bin/env python3
"""Hiding in Logomo (systems/hideouts.lua): wanted, walk in through its door;
gone in unseen the cops lose you in seconds, moving brings you back out,
and gone in with a cop watching they wait you out."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


class HideoutTests(unittest.TestCase):
    def test_turku(self):
        env = dict(os.environ, MAP="turku", SEED="1337", HIDEOUT_TEST="1")
        res = subprocess.run([str(BINARY), "game", "--headless", "30000"], cwd=ROOT, env=env,
                             capture_output=True, text=True, timeout=600)
        out = res.stdout + res.stderr
        self.assertEqual(res.returncode, 0, out[-3000:])
        self.assertNotIn("[lua:", out)
        self.assertIn("ALL HIDEOUT CHECKS PASSED", out, out[-3000:])


if __name__ == "__main__":
    unittest.main()
