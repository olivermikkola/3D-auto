#!/usr/bin/env python3
"""Map missions: Pansio Base Heist, Pöli Transit and The Archipelago Run play
through on the maps that have them (they crashed at their first line)."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


@unittest.skipUnless(BINARY.exists(), "needs a release build")
class MapMissionTests(unittest.TestCase):
    def test_map_missions_play_through(self):
        for name in ("turku", "raisio"):
            with self.subTest(map=name):
                env = dict(os.environ, MAP=name, SEED="1337", MAP_MISSIONS_TEST="1")
                with tempfile.TemporaryDirectory() as d:
                    env["XDG_DATA_HOME"] = d
                    res = subprocess.run([str(BINARY), "game", "--headless", "20000"], cwd=ROOT, env=env,
                                         capture_output=True, text=True, encoding="utf-8", errors="replace",
                                         timeout=600)
                out = res.stdout + res.stderr
                self.assertEqual(res.returncode, 0, out)
                self.assertIn(f"MAP_MISSIONS_PROBE {name}: PASSED", out, out)


if __name__ == "__main__":
    unittest.main()
