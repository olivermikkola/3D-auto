#!/usr/bin/env python3
"""Touch controls drive the game like a pad (game/test/touch_probe.lua)."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


class TouchTests(unittest.TestCase):
    def test_touch_walks_drives_and_pauses(self):
        env = dict(os.environ, MAP="starter", SEED="1337", TOUCH_TEST="1")
        res = subprocess.run([str(BINARY), "game", "--headless", "600"], cwd=ROOT, env=env,
                             capture_output=True, text=True, timeout=120)
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn("TOUCH TEST PASSED", res.stdout)


if __name__ == "__main__":
    unittest.main()
