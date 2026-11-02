#!/usr/bin/env python3
"""tools/lidar.py: the scans' coordinates, and the importer's check of
building heights against the roofs the laser saw."""
import math
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import lidar
import osm_import

try:
    import numpy as np
except ImportError:  # pragma: no cover
    np = None


class FakeCloud:
    """Flat ground at 10 m, and roof points (x, y, z, r, g, b) given."""

    def __init__(self, roofs, ground):
        self.roofs = np.array(roofs, dtype=np.float64).reshape(-1, 6)
        self.ground = np.array(ground, dtype=np.float64).reshape(-1, 6)

    def ground_at(self, x, z):
        return np.full(np.shape(x), 10.0)


def roof(x, z, w, d, y, step=1.0):
    return [(x + u, y, z + v, 0.5, 0.5, 0.5) for u in np.arange(-w / 2 + 1, w / 2 - 1, step) for v in np.arange(-d / 2 + 1, d / 2 - 1, step)]


@unittest.skipIf(np is None, "needs numpy")
class LidarTests(unittest.TestCase):
    def test_the_map_origin_is_the_games_origin(self):
        # Turku's origin (60.4515 N, 22.27 E) in ETRS-TM35FIN.
        x, z = lidar.to_game(np.array([239926.66, 239926.66 + 1000, 239926.66]), np.array([6711042.19, 6711042.19, 6711042.19 + 1000]))
        self.assertLess(abs(x[0]) + abs(z[0]), 0.5)
        # A kilometre east and north: TM35's grid is turned ~4 degrees from
        # true north this far west of its 27 E meridian, and the importer's
        # projection takes a degree of latitude as 110574 m (it is ~111400
        # here), so the game's north-south is 0.8 % short.
        east, north = math.hypot(x[1] - x[0], z[1] - z[0]), math.hypot(x[2] - x[0], z[2] - z[0])
        self.assertAlmostEqual(east, 1000, delta=5)
        self.assertAlmostEqual(north, 992, delta=5)
        self.assertLess(z[2] - z[0], -980)  # north is -z
        self.assertAlmostEqual(math.degrees(math.atan2(-(z[1] - z[0]), x[1] - x[0])), 4.1, delta=0.5)

    def test_heights_the_scans_clearly_disagree_with_are_put_right(self):
        boxes = [
            (0, 0, 10, 10, 0.0, 40.0, "house", False, None, 1935, None, False),     # roof seen at 8 m: lowered
            (100, 0, 20, 20, 0.0, 9.0, "flats", False, None, 1960, None, False),    # roof at 30 m: raised
            (200, 0, 30, 30, 0.0, 20.0, "church", False, None, 1300, None, False),  # a church keeps its own
            (300, 0, 20, 20, 0.0, 12.0, "flats", False, None, 1970, None, False),   # 13 m: close enough
            (400, 0, 6, 6, 0.0, 41.0, "shed", False, None, 1950, None, False),      # only ground seen: a shed
        ]
        roofs = roof(0, 0, 10, 10, 18) + roof(100, 0, 20, 20, 40) + roof(200, 0, 30, 30, 22) + roof(300, 0, 20, 20, 23)
        ground = [(400 + u, 10, v, 0.4, 0.4, 0.4) for u in (-2, 0, 2) for v in (-2, 0, 2)]
        cloud = FakeCloud(roofs, ground)
        out, lowered, raised, _ = lidar.check_heights(boxes, block=1000, cloud_at=lambda cx, cz, r: cloud)
        self.assertEqual((lowered, raised), (2, 1))
        self.assertAlmostEqual(out[0][5], 8.0, delta=0.6)
        self.assertAlmostEqual(out[1][5], 30.0, delta=0.6)
        self.assertEqual(out[2][5], 20.0)
        self.assertEqual(out[3][5], 12.0)
        self.assertEqual(out[4][5], 3.0)

    def test_a_building_goes_by_a_scan_taken_once_it_was_up(self):
        boxes = [
            (0, 0, 10, 10, 0.0, 16.0, "flats", False, None, 2021, None, False),   # a site in 2021, up in 2023
            (100, 0, 6, 6, 0.0, 21.0, "shed", False, None, 2022, None, False),    # 2023 sees only ground: a shed
            (200, 0, 6, 6, 0.0, 21.0, "shed", False, None, 2023, None, False),    # no scan after it: kept
        ]
        site = roof(0, 0, 10, 10, 13)
        ground = [(x + u, 10, v, 0.4, 0.4, 0.4) for x in (100, 200) for u in (-2, 0, 2) for v in (-2, 0, 2)]
        cloud = FakeCloud([], [])
        cloud.roofs_of = {"2021": np.array(site).reshape(-1, 6), "2023": roof(0, 0, 10, 10, 26.0)}
        cloud.roofs_of["2023"] = np.array(cloud.roofs_of["2023"]).reshape(-1, 6)
        cloud.ground_of = {"2021": np.zeros((0, 6)), "2023": np.array(ground).reshape(-1, 6)}
        out, lowered, raised, _ = lidar.check_heights(boxes, block=1000, cloud_at=lambda cx, cz, r: cloud)
        self.assertEqual(out[0][5], 16.0)  # the 2023 roof agrees; the 2021 site's lower points don't count
        self.assertEqual(out[1][5], 3.0)
        self.assertEqual(out[2][5], 21.0)
        self.assertEqual((lowered, raised), (1, 0))

    def test_a_ridge_the_scans_see_is_a_pitched_roof(self):
        # Flats 30 x 12 m, eaves at 7 m over the ground (10 m), a ridge 4 m
        # over them along the length; a flat roof with a little clutter on
        # it; and the same gable on a turned box, its ridge along its w.
        gable = [(u, 10 + 7 + 4 * (1 - abs(v) / 6), v, 0.5, 0.5, 0.5)
                 for u in np.arange(-14, 14, 1.0) for v in np.arange(-5.5, 5.6, 1.0)]
        rnd = np.random.default_rng(1)
        flat = [(100 + u, 10 + 9 + rnd.normal(0, 0.4), v, 0.5, 0.5, 0.5)
                for u in np.arange(-14, 14, 1.0) for v in np.arange(-5.5, 5.6, 1.0)]
        a = math.radians(30)
        turned = [(200 + p[0] * math.cos(a) - p[2] * math.sin(a), p[1], p[0] * math.sin(a) + p[2] * math.cos(a), 0.5, 0.5, 0.5)
                  for p in gable]
        boxes = [(0, 0, 30, 12, 0.0, 9.0, "flats", False, None, 1900, None, False),
                 (100, 0, 30, 12, 0.0, 9.0, "flats", False, None, 1960, None, False),
                 (200, 0, 30, 12, a, 9.0, "flats", False, None, 1900, None, False),
                 (300, 0, 30, 12, 0.0, 9.0, "house", False, None, 1900, None, False)]  # a house has a gable of its own
        roofs = gable + flat + turned + [(300 + p[0], p[1], p[2], 0.5, 0.5, 0.5) for p in gable]
        cloud = FakeCloud(roofs, [])
        out, _, _, pitched = lidar.check_heights(boxes, block=1000, cloud_at=lambda cx, cz, r: cloud)
        self.assertEqual(pitched, 2)
        self.assertAlmostEqual(out[0][5], 7.0, delta=0.3)
        self.assertAlmostEqual(out[0][10], 4.0, delta=0.3)
        self.assertIsNone(out[1][10])
        self.assertAlmostEqual(out[2][10], 4.0, delta=0.3)
        self.assertIsNone(out[3][10])

    def test_an_outline_and_its_boxes_keep_one_height(self):
        # An L drawn as its outline (20 m), the two boxes it stands for; the
        # scans lowered the big one to 14 m and left the small one. A box in
        # it of another height (a tower on the block) stays its own.
        pts = [(0, 0), (40, 0), (40, 10), (10, 10), (10, 30), (0, 30)]
        outline = (20.0, "flats", None, pts, None, 1960, False)
        before = [(20, 5, 40, 10, 0.0, 20.0, "flats"), (5, 20, 10, 20, 0.0, 20.0, "flats"), (35, 5, 5, 5, 0.0, 30.0, "flats"),
                  (100, 100, 10, 10, 0.0, 20.0, "flats")]
        after = [before[0][:5] + (14.0, "flats"), before[1], before[2], before[3][:5] + (9.0, "flats")]
        (o,), boxes = osm_import.one_height([outline], before, after)
        self.assertEqual(o[0], 14.0)  # the big box's: it has the most of the floor
        self.assertEqual([b[5] for b in boxes], [14.0, 14.0, 30.0, 9.0])
        self.assertEqual(o[1:], outline[1:])


if __name__ == "__main__":
    unittest.main()
