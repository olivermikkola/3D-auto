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
        h, kind, wall, pts, roof, year, span = out[0]
        self.assertEqual((kind, wall, roof, year, span), ("flats", None, None, None, False))
        self.assertEqual(len(pts), 6)
        self.assertAlmostEqual(osm_import.area(pts), 40 * 12 + 12 * 28, delta=5)

    def test_a_building_a_level_up_over_a_road_is_on_a_deck(self):
        # (Like Tyks' Majakkasairaala over Helsinginkatu: layer=1 and a road under it.)
        under = lambda poly: True
        self.assertTrue(osm_import.outlines_of([building({"layer": "1"}, *L)], P, inside, over_road=under)[0][6])
        self.assertFalse(osm_import.outlines_of([building({}, *L)], P, inside, over_road=under)[0][6])
        self.assertFalse(osm_import.outlines_of([building({"layer": "1"}, *L)], P, inside, over_road=lambda p: False)[0][6])
        self.assertFalse(osm_import.raised({"layer": "1", "location": "underground"}))
        self.assertFalse(osm_import.raised({"layer": "x"}))

    def test_road_under_measures_the_centreline_inside(self):
        square = [(0, 0), (20, 0), (20, 20), (0, 20)]
        grid = osm_import.Grid(50)
        edge = {"pts": [(-10, 10), (30, 10)], "width": 7}
        grid.add((edge, (-10, 10), (30, 10)), (-10, 10), (30, 10))
        self.assertAlmostEqual(osm_import.road_under(square, grid), 20, delta=1)

    def test_the_photo_colours_the_roof_over_a_tag(self):
        photo = lambda pts: (0.4, 0.3, 0.2)
        out = osm_import.outlines_of([building({}, *L)], P, inside, photo)
        self.assertEqual(out[0][4], (0.4, 0.3, 0.2))
        out = osm_import.outlines_of([building({"roof:colour": "red"}, *L)], P, inside, photo)
        self.assertEqual(out[0][4], (0.4, 0.3, 0.2))
        out = osm_import.outlines_of([building({"roof:colour": "red"}, *L)], P, inside, lambda pts: None)
        self.assertEqual(out[0][4], osm_import.roof_colour({"roof:colour": "red"}))

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
