"""The postcard spots stay where they were meant to be: inside Turku, at sane heights.

Rendering them is tools/postcards.py's job (it needs a display); this only
checks the table, so a typo can't send a camera to the sea or underground.
"""
import math
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import postcards  # noqa: E402

# Turku's box (tools/osm_import.py AREAS["turku"]) in the game's metres.
LAT0, LON0 = 60.45150, 22.27000
S, W, N, E = 60.425, 22.21, 60.480, 22.325
KX = 111320 * math.cos(math.radians(LAT0))
X0, X1 = (W - LON0) * KX, (E - LON0) * KX
Z0, Z1 = -(N - LAT0) * 110574, -(S - LAT0) * 110574


class PostcardSpotTests(unittest.TestCase):
    def test_spots_are_inside_turku(self):
        for name, spot in postcards.SPOTS.items():
            for x, y, z in (spot["eye"], spot["look"]):
                with self.subTest(spot=name):
                    self.assertTrue(X0 < x < X1 and Z0 < z < Z1, f"{name} at {x}, {z} is outside Turku")
                    self.assertTrue(0 <= y <= 300, f"{name} height {y}")

    def test_spots_are_complete(self):
        for name, spot in postcards.SPOTS.items():
            with self.subTest(spot=name):
                self.assertTrue(name.isidentifier(), name)
                self.assertTrue(10 <= spot["fov"] <= 120)
                self.assertTrue(0 <= spot["hour"] < 24)
                self.assertTrue(spot["about"])
                self.assertNotEqual(spot["eye"], spot["look"])

    def test_the_places_oliver_asked_for_are_there(self):
        for place in ("ylioppilaskyla", "aurajoki", "kauppatori", "kakolanmaki", "logomo", "puolalanmaki", "kupittaa"):
            self.assertIn(place, postcards.SPOTS)


if __name__ == "__main__":
    unittest.main()
