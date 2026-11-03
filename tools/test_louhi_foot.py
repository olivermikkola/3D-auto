#!/usr/bin/env python3
"""Louhi on foot (systems/louhi.lua): from Kauppatori through the stair house's door,
down the stairs into the hall and back out; an officer follows you down."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


class LouhiFootTests(unittest.TestCase):
    def test_turku(self):
        env = dict(os.environ, MAP="turku", SEED="1337", LOUHI_FOOT_TEST="1")
        res = subprocess.run([str(BINARY), "game", "--headless", "40000"], cwd=ROOT, env=env,
                             capture_output=True, text=True, timeout=600)
        out = res.stdout + res.stderr
        self.assertEqual(res.returncode, 0, out[-3000:])
        self.assertNotIn("[lua:", out)
        self.assertIn("ALL LOUHI_FOOT CHECKS PASSED", out, out[-3000:])


if __name__ == "__main__":
    unittest.main()
