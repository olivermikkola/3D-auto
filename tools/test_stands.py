#!/usr/bin/env python3
"""Grandstands and stadium stands become stands; a stadium hall stays a building."""
import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import osm_import


def box(w, d):
    return [(0, 0), (w, 0), (w, d), (0, d)]


class StandTests(unittest.TestCase):
    def test_grandstand_is_a_stand_whatever_its_shape(self):
        self.assertTrue(osm_import.is_stand({"building": "grandstand"}, box(40, 30)))

    def test_long_narrow_stadium_building_is_a_stand(self):
        # Veritas Stadion's main stand: about 134 x 32 m.
        self.assertTrue(osm_import.is_stand({"building": "stadium"}, box(134, 32)))

    def test_squarish_stadium_building_is_a_hall(self):
        # Kupittaan palloiluhalli: about 110 x 56 m, a ball hall.
        self.assertFalse(osm_import.is_stand({"building": "stadium"}, box(110, 56)))

    def test_other_buildings_are_not_stands(self):
        self.assertFalse(osm_import.is_stand({"building": "yes"}, box(134, 32)))


if __name__ == "__main__":
    unittest.main()
