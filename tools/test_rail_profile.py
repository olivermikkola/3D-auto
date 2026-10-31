#!/usr/bin/env python3
"""Railways run on their own smooth profile, not over every crease of the
10 m terrain grid: on Turku the steepest grade along a track was 29 % and
the grade changed 1.7 % every 10 m on average; now 6.2 % and 0.09 %."""
import os
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


class RailHeightsTests(unittest.TestCase):
    def test_a_bump_is_smoothed_and_tracks_meet_at_one_height(self):
        import sys
        sys.path.insert(0, str(ROOT / "tools"))
        import osm_import
        # Two tracks end to end along x over flat ground at 10 m with a 3 m
        # spike (a post, a crease) under the first.
        ground = lambda x, z: 13.0 if 98 <= x <= 102 else 10.0
        a = (True, True, [(0.0, 0.0), (200.0, 0.0)])
        b = (True, True, [(200.0, 0.0), (400.0, 0.0)])
        ha, hb = osm_import.rail_heights([a, b], ground)
        self.assertLess(max(ha) - 10.0, 0.3)
        self.assertAlmostEqual(ha[-1], hb[0], places=6)
        self.assertEqual(len(ha), 21)


class RailProfileTests(unittest.TestCase):
    def test_turku(self):
        env = dict(os.environ, MAP="turku", SEED="1337", RAIL_PROFILE_TEST="1")
        res = subprocess.run([str(BINARY), "game", "--headless", "600"], cwd=ROOT, env=env,
                             capture_output=True, text=True, timeout=600)
        out = res.stdout + res.stderr
        self.assertEqual(res.returncode, 0, out[-3000:])
        self.assertNotIn("[lua:", out)
        m = re.search(r"RAIL_PROFILE (\d+) m of track, steepest ([\d.]+) %, grade change ([\d.]+) %", out)
        self.assertIsNotNone(m, out[-3000:])
        metres, steep, change = int(m.group(1)), float(m.group(2)), float(m.group(3))
        self.assertGreater(metres, 30000)
        self.assertLess(steep, 8.0)
        self.assertLess(change, 0.3)

    def test_the_importer_gives_every_track_a_profile(self):
        text = (ROOT / "game" / "maps" / "turku_osm.lua").read_text(encoding="utf-8")
        tracks = text.split("\n  railways = {\n")[1].split("\n  },")[0].splitlines()
        self.assertGreater(len(tracks), 100)
        self.assertTrue(all("heights = {" in t for t in tracks))


if __name__ == "__main__":
    unittest.main()
