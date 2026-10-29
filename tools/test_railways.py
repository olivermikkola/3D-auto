#!/usr/bin/env python3
"""Railway track and platforms from map data, and a map that draws them."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import osm_import

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")
P = osm_import.Proj(60.45, 22.27)


def way(tags, *lonlats):
    return {"type": "way", "tags": tags, "geometry": [{"lat": lat, "lon": lon} for lon, lat in lonlats]}


def inside(x, z, pad=0):
    return abs(x) < 5000 and abs(z) < 5000


class RailwayTests(unittest.TestCase):
    def test_track_on_the_ground_only(self):
        line = ((22.27, 60.45), (22.28, 60.45))
        els = [
            way({"railway": "rail", "electrified": "contact_line"}, *line),
            way({"railway": "rail", "service": "yard"}, *line),
            way({"railway": "rail", "bridge": "yes"}, *line),
            way({"railway": "rail", "tunnel": "yes"}, *line),
            way({"railway": "abandoned"}, *line),
        ]
        rails, platforms, bridges = osm_import.railways_of(els, P, inside)
        self.assertEqual([(main, wired) for main, wired, _ in rails], [(True, True), (False, False)])
        self.assertEqual(platforms, [])
        self.assertEqual(len(bridges), 1)

    def test_platform_is_a_long_narrow_box(self):
        ring = ((22.270, 60.450), (22.2715, 60.450), (22.2715, 60.45005), (22.270, 60.45005), (22.270, 60.450))
        _, platforms, bridges = osm_import.railways_of([way({"railway": "platform"}, *ring)], P, inside)
        self.assertEqual(len(platforms), 1)
        self.assertEqual(bridges, [])
        _, _, length, width, _ = platforms[0]
        self.assertAlmostEqual(length, 0.0015 * P.kx, delta=1)
        self.assertAlmostEqual(width, 0.00005 * 110574, delta=0.5)

    def test_splice_keeps_the_rest_of_the_map(self):
        with tempfile.TemporaryDirectory() as d:
            dest = Path(d) / "m.lua"
            dest.write_text("return {\n  bounds = {-100, -100, 100, 100},\n  roads = {},\n"
                            "  -- towers and masts: {x, z, height, \"lattice\" or \"pylon\"}\n  towers = {},\n}\n")
            els = [way({"railway": "rail"}, (22.2695, 60.45), (22.2705, 60.45))]
            f = lambda v: f"{v:.1f}".rstrip("0").rstrip(".")
            for _ in range(2):  # twice: the second replaces the first
                osm_import.splice_railways(dest, els, P, f)
            text = dest.read_text()
            self.assertEqual(text.count("  railways = {"), 1)
            self.assertEqual(text.count("  rail_bridges = {"), 1)
            self.assertIn("  roads = {},", text)
            self.assertLess(text.index("railways"), text.index("towers = {}"))

    @unittest.skipUnless(BINARY.exists(), "needs a release build")
    def test_turku_yard_is_drawn(self):
        env = os.environ.copy()
        env.update(MAP="turku", SEED="1337", CHUNK_TEST="1")
        res = subprocess.run([str(BINARY), "game", "--headless", "5"], cwd=ROOT, env=env, capture_output=True, text=True,
                             timeout=900)
        self.assertEqual(res.returncode, 0, res.stdout[-3000:] + res.stderr[-3000:])
        self.assertIn("RAIL_CHUNKS=", res.stdout)
        self.assertGreater(int(res.stdout.split("RAIL_CHUNKS=")[1].split()[0]), 5)

    @unittest.skipUnless(BINARY.exists(), "needs a release build")
    def test_level_crossings_are_drivable(self):
        for city, least in (("raisio", 20), ("turku", 8)):
            env = dict(os.environ, MAP=city, SEED="1337", RAIL_CROSSING_TEST="1")
            res = subprocess.run([str(BINARY), "game", "--headless", "5"], cwd=ROOT, env=env, capture_output=True,
                                 text=True, timeout=900)
            self.assertEqual(res.returncode, 0, res.stdout[-3000:] + res.stderr[-3000:])
            self.assertIn("RAIL_CROSSING_OK", res.stdout, res.stdout[-3000:])
            self.assertGreaterEqual(int(res.stdout.split("RAIL_CROSSINGS=")[1].split()[0]), least, city)


if __name__ == "__main__":
    unittest.main()
