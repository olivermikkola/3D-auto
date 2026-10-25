"""tools/citymodel.py and the importer's use of it: parsing the WFS answer,
the Gauss-Krüger round trip, and an OSM outline taking the model's height
and year."""
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import citymodel
import osm_import

XML = """<wfs:FeatureCollection><gml:featureMember>
  <bldg:Building gml:id="Building_1">
    <gen:stringAttribute name="valmistunut"><gen:value>01.01.1886</gen:value></gen:stringAttribute>
    <gen:stringAttribute name="x"><gen:value>6704369.808</gen:value></gen:stringAttribute>
    <gen:stringAttribute name="y"><gen:value>23459560.102</gen:value></gen:stringAttribute>
    <bldg:measuredHeight uom="urn:adv:uom:m">14.2</bldg:measuredHeight>
    <bldg:storeysAboveGround>3</bldg:storeysAboveGround>
  </bldg:Building></gml:featureMember><gml:featureMember>
  <bldg:Building gml:id="Building_2">
    <bldg:measuredHeight uom="urn:adv:uom:m">5.0</bldg:measuredHeight>
  </bldg:Building></gml:featureMember></wfs:FeatureCollection>"""


class CityModelTests(unittest.TestCase):
    def test_parse_keeps_point_height_storeys_year(self):
        bs = citymodel.parse(XML)
        self.assertEqual(len(bs), 1)  # the second has no point
        self.assertEqual(bs[0], {"E": 23459560.102, "N": 6704369.808, "h": 14.2, "storeys": 3, "year": 1886})

    def test_gauss_kruger_round_trip(self):
        E, N = citymodel.gk(60.4513, 22.2667, 23)
        self.assertAlmostEqual(E, 23459641.0, delta=1)
        lat, lon = citymodel.gk_inverse(E, N, 23)
        self.assertAlmostEqual(lat, 60.4513, places=7)
        self.assertAlmostEqual(lon, 22.2667, places=7)

    def test_an_outline_takes_the_heights_inside_it(self):
        h = osm_import.model_heights([(5, 5, 14.2, 3, 1886), (50, 50, 30.0, 9, 1960),
                                      (12, 6, 20.0, 5, 1910), (14, 8, 1.0, None, 1990)])
        square = [(0, 0), (20, 0), (20, 20), (0, 20)]
        self.assertEqual(h(square), (20.0, 1886))  # two inside: the taller, the older; a 1 m shed doesn't count
        self.assertIsNone(h([(100, 100), (110, 100), (110, 110)]))


if __name__ == "__main__":
    unittest.main()
