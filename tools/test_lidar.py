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
        out, lowered, raised = lidar.check_heights(boxes, block=1000, cloud_at=lambda cx, cz, r: cloud)
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
        out, lowered, raised = lidar.check_heights(boxes, block=1000, cloud_at=lambda cx, cz, r: cloud)
        self.assertEqual(out[0][5], 16.0)  # the 2023 roof agrees; the 2021 site's lower points don't count
        self.assertEqual(out[1][5], 3.0)
        self.assertEqual(out[2][5], 21.0)
        self.assertEqual((lowered, raised), (1, 0))


if __name__ == "__main__":
    unittest.main()
