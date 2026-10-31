#!/usr/bin/env python3
"""The Aurajoki's stone quays: a wall at the water's edge and level paving
behind it, where the 10 m terrain grid used to slope from the street down
into the river (and rose out of the water in front of the bank at 1 in 4
of its points, 2 m out)."""
import os
from pathlib import Path
import re
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")
sys.path.insert(0, str(ROOT / "tools"))
import osm_import  # noqa: E402


class Roads:
    def __init__(self, items): self.items = items
    def near(self, *_): return iter(self.items)


class QuayTests(unittest.TestCase):
    # A river along x from z = 0 to z = 40, the bank 3 m up on either side.
    RIVER = [[(0.0, 0.0), (200.0, 0.0), (200.0, 40.0), (0.0, 40.0)]]

    @staticmethod
    def ground(x, z): return 0.2 if 0 <= z <= 40 else 3.0

    @staticmethod
    def wet(x, z): return 0 <= z <= 40 and 0 <= x <= 200

    def test_both_banks_get_a_wall_with_the_land_on_the_right(self):
        runs = osm_import.quays(self.RIVER, self.ground, self.wet)
        self.assertEqual(len(runs), 2)
        for level, pts in runs:
            self.assertAlmostEqual(level, 0.2)
            self.assertTrue(all(t == 3.0 and w == osm_import.QUAY_WIDE for _, _, t, w in pts))
            (ax, az, _, _), (bx, bz, _, _) = pts[0], pts[1]
            rx, rz = bz - az, -(bx - ax)  # right of the way along
            self.assertFalse(self.wet(ax + rx * 3, az + rz * 3), pts[:2])

    def test_a_low_bank_gets_none(self):
        runs = osm_import.quays(self.RIVER, lambda x, z: 0.5 if 0 <= z <= 40 else 1.0, self.wet)
        self.assertEqual(runs, [])

    def test_beside_a_street_the_quay_stops_at_its_pavement_and_is_level_with_it(self):
        # A street 12 m wide along the south bank, its middle 14 m in, at 2.5 m.
        street = ({"width": 12.0}, (-50.0, -14.0), (250.0, -14.0), 2.5, 2.5)
        runs = osm_import.quays(self.RIVER, self.ground, self.wet, Roads([street]))
        south = [r for r in runs if r[1][0][1] < 20][0][1]
        for _, _, top, w in south:
            self.assertAlmostEqual(w, 14 - 6 - osm_import.QUAY_GAP, places=1)
            self.assertAlmostEqual(top, 2.62, places=2)

    def test_the_grid_off_a_wall_is_sunk_under_the_water(self):
        # A 10 m grid over the river above: rows at z = -3 (on the bank, 3 m
        # up), 7 (in the river, at its bed), ...: a triangle between them
        # rose out of the water 1.2 m out from the bank.
        x0, z0, step, tw, td = 0.0, -23.0, 10.0, 21, 9
        hgt = [3.0 if not self.wet(x0 + i * step, z0 + j * step) else -1.3 for j in range(td) for i in range(tw)]
        runs = [(0.2, [(float(x), 0.0, 3.0, 10.0) for x in range(10, 191, 4)])]
        n = osm_import.sink_under_quays(hgt, tw, td, x0, z0, step, runs)
        self.assertGreater(n, 0)
        def grid(x, z):
            u, v = (x - x0) / step, (z - z0) / step
            i, j = int(u), int(v)
            fx, fz = u - i, v - j
            h = lambda a, b: hgt[b * tw + a]
            if fx + fz <= 1: return h(i, j) + (h(i + 1, j) - h(i, j)) * fx + (h(i, j + 1) - h(i, j)) * fz
            return h(i + 1, j + 1) + (h(i, j + 1) - h(i + 1, j + 1)) * (1 - fx) + (h(i + 1, j) - h(i + 1, j + 1)) * (1 - fz)
        # The wall's points have the land on the right going along +x: -z.
        # Out in the water, +z.
        for x in range(12, 189, 3):
            for d in (1.2, 2, 4, 8):
                self.assertLessEqual(grid(x, d), 0.2, (x, d))
        self.assertTrue(all(h >= 0.2 - 1.5 for h in hgt))


class TurkuQuayTests(unittest.TestCase):
    def test_turku(self):
        env = dict(os.environ, MAP="turku", SEED="1337", QUAY_TEST="1")
        res = subprocess.run([str(BINARY), "game", "--headless", "600"], cwd=ROOT, env=env,
                             capture_output=True, text=True, timeout=600)
        out = res.stdout + res.stderr
        self.assertEqual(res.returncode, 0, out[-3000:])
        self.assertNotIn("[lua:", out)
        self.assertIn("QUAY_OK", out, re.findall(r"QUAY .*", out))


if __name__ == "__main__":
    unittest.main()
