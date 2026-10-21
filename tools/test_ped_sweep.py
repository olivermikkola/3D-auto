#!/usr/bin/env python3
"""Pedestrian sweep: a walker down the pavement of every fourth road of each
map, each side, and on bridges another from the middle of the deck
(PED_SWEEP=1, PED_SWEEP_EVERY=4), counting the ones that get into trouble:
blocked, below their pavement, off it, or too slow."""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")

# Walkers in trouble out of ~550 per map. Walkers turned back at every
# street lamp in their way (Turku 25, Raisio 14), and walkers put on a
# bridge's pavement stood on the ground under it (Turku 8, Raisio 13): in
# all Turku 36, Raisio 34. Now 5 and 8, most where a bridge's deck is
# narrower than its pavements at the ends. Then 3 and 2: decks reach round
# their bends, keep their pavements over roads well below and where the
# road carrying on is graded a little off, and the map's walkway between
# Tykistökatu's twin decks no longer stands out of them. Lower these as
# they're fixed; never raise them.
TROUBLE_MAX = {"turku": 6, "raisio": 5}


@unittest.skipUnless(BINARY.exists(), "needs a release build")
class PedSweepTests(unittest.TestCase):
    def test_maps(self):
        for name, most in TROUBLE_MAX.items():
            with self.subTest(map=name):
                env = dict(os.environ, MAP=name, SEED="1337", PED_SWEEP="1", PED_SWEEP_EVERY="4")
                with tempfile.TemporaryDirectory() as d:
                    env["XDG_DATA_HOME"] = d
                    res = subprocess.run([str(BINARY), "game", "--headless", "3000000"], cwd=ROOT, env=env,
                                         capture_output=True, text=True, encoding="utf-8", timeout=900)
                out = res.stdout + res.stderr
                self.assertEqual(res.returncode, 0, out)
                self.assertNotIn("[lua:", out)
                m = re.search(r"PED_SWEEP: (\d+) walks, (\d+) in trouble", out)
                self.assertTrue(m, out)
                self.assertGreater(int(m[1]), 400)
                self.assertLessEqual(int(m[2]), most, out)


if __name__ == "__main__":
    unittest.main()
