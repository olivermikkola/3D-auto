#!/usr/bin/env python3
"""Points of interest for missions: the importer keeps them, and the game
finds them by tag (docs/MISSION_TEMPLATES.md)."""
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
M = 1 / 110574  # a metre of latitude


def node(x, z, **tags):
    return {"type": "node", "lat": 60.45 - z * M, "lon": 22.27 + x / P.kx, "tags": tags}


def way(x, z, **tags):
    """A way as Overpass gives it with `out center`: its center, no points."""
    return {"type": "way", "center": {"lat": 60.45 - z * M, "lon": 22.27 + x / P.kx}, "tags": tags}


def inside(x, z, pad=0):
    return abs(x) < 1000 and abs(z) < 1000


def f(v): return f"{v:.1f}".rstrip("0").rstrip(".")
def q(v): return osm_import.json.dumps(v, ensure_ascii=False)


class ImportTests(unittest.TestCase):
    def test_keeps_what_missions_ask_about(self):
        out = osm_import.pois_of([node(10, 20, name="Lidl", shop="supermarket", brand="Lidl", opening_hours="8-21")], P, inside)
        self.assertEqual(len(out), 1)
        x, z, tags = out[0]
        self.assertAlmostEqual(x, 10, delta=0.1)
        self.assertAlmostEqual(z, 20, delta=0.1)
        self.assertEqual(tags, {"name": "Lidl", "shop": "supermarket", "brand": "Lidl"})

    def test_areas_by_their_center_and_nothing_outside(self):
        out = osm_import.pois_of([way(-300, 40, name="Kirkko", amenity="place_of_worship"),
                                  node(5000, 0, name="Far", shop="kiosk"), {"type": "way", "tags": {"name": "No center"}}],
                                 P, inside)
        self.assertEqual([t["name"] for _, _, t in out], ["Kirkko"])

    def test_the_same_place_twice_is_kept_once(self):
        a = node(0, 0, name="Hesburger", amenity="fast_food")
        self.assertEqual(len(osm_import.pois_of([a, dict(a, type="way")], P, inside)), 1)

    def test_order_does_not_depend_on_overpass(self):
        els = [node(i * 7, -i * 3, name=f"S{i % 4}", shop="kiosk") for i in range(12)]
        self.assertEqual(osm_import.pois_of(els, P, inside), osm_import.pois_of(els[::-1], P, inside))

    def test_splice_touches_only_the_pois_and_twice_is_once(self):
        text = "\n".join(["return {", "  bounds = {-1000, -1000, 1000, 1000},", "  piers = {", "  },",
                          "  -- named parts of town: {name, x, z, \"town\", \"suburb\" or \"neighbourhood\"}",
                          "  areas = {", "  },", "}", ""])
        els = [node(1, 2, name='Kauppa "K"', shop="convenience")]
        with tempfile.TemporaryDirectory() as d:
            dest = Path(d) / "m_osm.lua"
            dest.write_text(text)
            osm_import.splice_pois(dest, els, P, f, q)
            once = dest.read_text()
            osm_import.splice_pois(dest, els, P, f, q)
            self.assertEqual(dest.read_text(), once)
            self.assertIn('{name = "Kauppa \\"K\\"", shop = "convenience"}', once)
            self.assertEqual(once.replace("\n".join(osm_import.poi_lines(osm_import.pois_of(els, P, inside), f, q)) + "\n", ""), text)


@unittest.skipUnless(BINARY.exists(), "needs a release build")
class GameTests(unittest.TestCase):
    def probe(self, map_name):
        env = dict(os.environ, MAP=map_name, SEED="1337", POI_TEST="1")
        with tempfile.TemporaryDirectory() as d:
            env["XDG_DATA_HOME"] = d
            res = subprocess.run([str(BINARY), "game", "--headless", "5"], cwd=ROOT, env=env,
                                 capture_output=True, text=True, timeout=600)
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn("POI_PROBE: PASSED", res.stdout, res.stdout + res.stderr)
        return res.stdout

    def test_turku(self):
        out = self.probe("turku")
        self.assertRegex(out, r"turku: \d{4} points of interest")
        self.assertIn("cathedral stops at", out)

    def test_raisio(self):
        self.assertRegex(self.probe("raisio"), r"raisio: Hesburgers: [1-9]")

    def test_a_grid_map_finds_nothing(self):
        self.assertIn("grid map, nothing to find", self.probe("starter"))


if __name__ == "__main__":
    unittest.main()
