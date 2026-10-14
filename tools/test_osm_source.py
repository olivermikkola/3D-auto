#!/usr/bin/env python3
"""Synthetic OSM XML fixtures for the real API input conversion seam."""
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parent))

class OsmApiSourceTests(unittest.TestCase):
    def test_real_node_ids_and_direction_tags_survive_xml_conversion(self):
        import importlib.util
        self.assertIsNotNone(importlib.util.find_spec('osm_source'), 'OSM XML input converter required')
        import osm_source
        xml='''<osm version="0.6"><node id="1" lat="60.45" lon="22.28"/><node id="2" lat="60.451" lon="22.281"/><way id="10" version="3"><nd ref="1"/><nd ref="2"/><tag k="highway" v="residential"/><tag k="name" v="Fixture street"/><tag k="oneway" v="-1"/></way></osm>'''
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'synthetic.osm';p.write_text(xml)
            data=osm_source.load_xml([p])
        way=next(e for e in data['elements'] if e['type']=='way')
        self.assertEqual(way['nodes'],[1,2])
        self.assertEqual(way['tags']['oneway'],'-1')
        self.assertEqual(way['geometry'][1],{'lat':60.451,'lon':22.281})
        self.assertEqual(data['source']['kind'],'OSM API XML')
        self.assertEqual(data['source']['inputs'][0]['name'],'synthetic.osm')

if __name__=='__main__':
    unittest.main()
