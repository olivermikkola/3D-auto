#!/usr/bin/env python3
"""The city radio picks fitting lines deterministically (game/test/story_probe.lua)."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


class StoryTests(unittest.TestCase):
    def test_radio_picks_fit_and_repeat(self):
        env = dict(os.environ, MAP="turku", SEED="1337", STORY_TEST="1")
        res = subprocess.run([str(BINARY), "game", "--headless", "30"], cwd=ROOT, env=env,
                             capture_output=True, text=True, timeout=300)
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn("STORY TEST PASSED", res.stdout)


if __name__ == "__main__":
    unittest.main()
