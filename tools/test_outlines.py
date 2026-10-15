#!/usr/bin/env python3
"""Footprints boxes fit badly go to the game as their own outlines."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import osm_import

P = osm_import.Proj(60.45, 22.27)
M = 1 / 110574  # a metre of latitude


def building(tags, *xz):
    """A closed building way from points in metres east, south of P's origin."""
    pts = list(xz) + [xz[0]]
    return {"type": "way", "tags": {"building": "apartments", **tags},
            "geometry": [{"lat": 60.45 - z * M, "lon": 22.27 + x / P.kx} for x, z in pts]}


def inside(x, z, pad=0):
    return abs(x) < 1000 and abs(z) < 1000


L = ((0, 0), (40, 0), (40, 12), (12, 12), (12, 40), (0, 40))
RECT = ((0, 0), (40, 0), (40, 15), (0, 15))


class OutlineTests(unittest.TestCase):
    def test_an_l_is_an_outline(self):
        out = osm_import.outlines_of([building({}, *L)], P, inside)
        self.assertEqual(len(out), 1)
        h, kind, wall, pts = out[0]
        self.assertEqual((kind, wall), ("flats", None))
        self.assertEqual(len(pts), 6)
        self.assertAlmostEqual(osm_import.area(pts), 40 * 12 + 12 * 28, delta=5)

    def test_a_plain_box_stays_a_box(self):
        self.assertEqual(osm_import.outlines_of([building({}, *RECT)], P, inside), [])

    def test_a_coloured_box_is_an_outline(self):
        out = osm_import.outlines_of([building({"building:material": "brick"}, *RECT)], P, inside)
        self.assertEqual(out[0][2], osm_import.MATERIALS["brick"])
        out = osm_import.outlines_of([building({"building:colour": "#ff0000"}, *RECT)], P, inside)
        self.assertEqual(out[0][2], (1.0, 0.0, 0.0))

    def test_houses_and_sheds_keep_their_own_look(self):
        for b in ("house", "shed", "church"):
            with self.subTest(building=b):
                self.assertEqual(osm_import.outlines_of([building({"building": b}, *L)], P, inside), [])


if __name__ == "__main__":
    unittest.main()
