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
        h, kind, wall, pts, roof, year, span, rise, doors, ways = out[0]
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


def ring(*xz):
    return [{"lat": 60.45 - z * M, "lon": 22.27 + x / P.kx} for x, z in list(xz) + [xz[0]]]


# A 60 x 60 block round a 30 x 30 yard (as Tyyssija and Aitiopaikka are mapped:
# a multipolygon, the yard its inner ring), and a passage from the street
# (z < 0) through its south side into the yard.
YARD_BLOCK = {"type": "relation", "tags": {"building": "apartments"},
              "members": [{"role": "outer", "geometry": ring((0, 0), (60, 0), (60, 60), (0, 60))},
                          {"role": "inner", "geometry": ring((15, 15), (45, 15), (45, 45), (15, 45))}]}
PASSAGE = {"type": "way", "tags": {"highway": "footway", "tunnel": "building_passage"},
           "geometry": [{"lat": 60.45 - z * M, "lon": 22.27 + x / P.kx} for x, z in ((30, -2), (30, 20))]}


class YardTests(unittest.TestCase):
    def test_a_yard_is_cut_out(self):
        (poly,) = osm_import.with_yards(YARD_BLOCK, P)
        self.assertAlmostEqual(osm_import.area(poly), 60 * 60 - 30 * 30, delta=5)
        self.assertFalse(osm_import.inside_poly(poly, 30, 30))  # the yard
        self.assertTrue(osm_import.inside_poly(poly, 7, 30))    # the block
        # Its boxes leave the yard clear.
        for x, z, w, d, ang in osm_import.boxes_of(poly):
            self.assertFalse(abs(x - 30) + w / 2 < 15 and abs(z - 30) + d / 2 < 15, (x, z, w, d))

    def test_a_small_inner_ring_stays_roofed(self):
        well = dict(YARD_BLOCK, members=[YARD_BLOCK["members"][0], {"role": "inner", "geometry": ring((28, 28), (32, 28), (32, 32), (28, 32))}])
        (poly,) = osm_import.with_yards(well, P)
        self.assertTrue(osm_import.inside_poly(poly, 30, 30))

    def test_a_passage_makes_a_door_each_side_and_a_way_through(self):
        (poly,) = osm_import.with_yards(YARD_BLOCK, P)
        passages = osm_import.passages_of([PASSAGE], P)
        doors, ways = osm_import.doors_of(poly, passages)
        self.assertEqual(sorted(round(z) for _, z, _, _ in doors), [0, 15])
        self.assertEqual(len(ways), 1)
        x0, z0, x1, z1, w, h = ways[0]
        self.assertEqual((round(z0), round(z1), w, h), (0, 15, 3.0, 3.0))

    def test_boxes_leave_the_passage_clear(self):
        passages = osm_import.passages_of([PASSAGE], P)
        cut = osm_import.cut_passages([(30, 7.5, 60, 15, 0)], passages)  # the south side, one box
        self.assertEqual(len(cut), 2)
        for x, z, w, d, ang in cut:
            self.assertGreater(abs(x - 30) - w / 2, 1.4)  # 1.5 m either side of the way stays open


if __name__ == "__main__":
    unittest.main()
