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
        self.assertEqual(bs[0], {"E": 23459560.1, "N": 6704369.81, "h": 14.2, "storeys": 3, "year": 1886,
                                 "aE": 23459560.102, "aN": 6704369.808})

    def test_lod2_gives_its_own_middle_and_a_pitched_roof(self):
        def ring(*pts):
            return "<gml:LinearRing>" + "".join(f"<gml:pos>{x} {y} {z}</gml:pos>" for x, y, z in pts) + "</gml:LinearRing>"
        # A 20 x 10 m house: ground at 5 m, eaves at 14, ridge along x at 18.
        xml = ("<bldg:Building gml:id=\"B\"><bldg:measuredHeight>13.0</bldg:measuredHeight>"
               "<bldg:GroundSurface>" + ring((0, 0, 5), (20, 0, 5), (20, 10, 5), (0, 10, 5)) + "</bldg:GroundSurface>"
               "<bldg:RoofSurface>" + ring((0, 0, 14), (20, 0, 14), (20, 5, 18), (0, 5, 18)) + "</bldg:RoofSurface>"
               "<bldg:RoofSurface>" + ring((0, 5, 18), (20, 5, 18), (20, 10, 14), (0, 10, 14)) + "</bldg:RoofSurface>"
               "</bldg:Building>")
        b = citymodel.parse(xml)[0]
        self.assertEqual((b["E"], b["N"]), (10, 5))
        self.assertEqual(b["pitch"], (9.0, 13.0))
        flat = xml.replace("(20, 5, 18)", "").replace(" 18<", " 14<")
        self.assertIsNone(citymodel.parse(flat)[0]["pitch"])

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
        self.assertEqual(h(square), (20.0, 1886, None))  # two inside: the taller, the older; a 1 m shed doesn't count
        self.assertIsNone(h([(100, 100), (110, 100), (110, 110)]))
        # A U round a yard: its middle is in the yard, its address point on it.
        u = osm_import.model_heights([(205, 205, 18.0, 5, 1900, (14.0, 18.0), [(201, 205)])])
        self.assertEqual(u([(200, 200), (202, 200), (202, 210), (200, 210)]), (18.0, 1900, (14.0, 18.0)))

    def test_a_height_over_the_sea_goes_by_the_storeys(self):
        # A two-storey house of 1935 "43.9 m" (the ground 35 m up): 2 * 3.3 + 1.5.
        h = osm_import.model_heights([(5, 5, 43.9, 2, 1935)])
        self.assertAlmostEqual(h([(0, 0), (10, 0), (10, 10), (0, 10)])[0], 8.1)
        # A tower of 12 storeys at 40 m stays as it is.
        h = osm_import.model_heights([(5, 5, 40.0, 12, 1970)])
        self.assertEqual(h([(0, 0), (10, 0), (10, 10), (0, 10)])[0], 40.0)


if __name__ == "__main__":
    unittest.main()
