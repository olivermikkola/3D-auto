#!/usr/bin/env python3
"""Tests for explicit city geodata selection, not a procedural grid substitute."""
import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import osm_import


class CityGeodataTests(unittest.TestCase):
    def test_turku_configuration_covers_comparison_districts(self):
        self.assertIn('turku', osm_import.AREAS, 'Turku needs an actual importer target')
        cfg = osm_import.AREAS['turku']
        s, w, n, e = cfg['bbox']
        # Public district/campus anchors, not a private residence or personal route.
        for label, lat, lon in [
            ('Ylioppilaskyla OSM node 25417668', 60.4637095, 22.293054),
            ('Kupittaa EduCity public campus', 60.4486861, 22.2974464),
        ]:
            with self.subTest(anchor=label):
                self.assertTrue(s < lat < n and w < lon < e, label)
        self.assertEqual(cfg['terrain_source']['resolution_m'], 2)
        self.assertEqual(cfg['terrain_source']['crs'], 'EPSG:3067')
        self.assertEqual(cfg['terrain_source']['vertical_datum'], 'N2000')
        self.assertEqual(cfg['terrain_source']['license'], 'CC BY 4.0')
        self.assertEqual(cfg['coverage_kind'], 'regional_first_slice')
        self.assertIn('first', cfg)
        self.assertIn('origin', cfg)

    def test_turku_import_rejects_missing_real_terrain(self):
        import subprocess
        try:
            res = subprocess.run(
                [sys.executable, str(Path(osm_import.__file__)), 'turku',
                 '--cache', 'definitely-missing-osm-cache.json'],
                capture_output=True, text=True, timeout=5,
            )
        except subprocess.TimeoutExpired:
            self.fail('CLI attempted networking instead of rejecting missing real terrain')
        self.assertNotEqual(res.returncode, 0)
        self.assertIn('requires verified 2 m terrain', res.stdout + res.stderr)
        self.assertNotIn('fetching', res.stdout + res.stderr)

    def test_cli_rejects_incomplete_terrain_coverage_before_network(self):
        import subprocess, tempfile
        try:
            from PIL import Image, TiffImagePlugin
        except ImportError:
            self.skipTest('Pillow required for importer raster fixtures')
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / 'tiny.tif'
            im = Image.new('F', (3,3), 10)
            tags = TiffImagePlugin.ImageFileDirectory_v2()
            tags[33550] = (2.,2.,0.)
            tags[33922] = (0.,0.,0.,236000.,6714000.,0.)
            tags[34735] = (1,1,0,2,1025,0,1,1,3072,0,1,3067)
            im.save(p,tiffinfo=tags)
            try:
                res = subprocess.run([sys.executable, str(Path(osm_import.__file__)),
                    'turku', '--terrain', str(p)],capture_output=True,text=True,timeout=5)
            except subprocess.TimeoutExpired:
                self.fail('network attempted before terrain coverage validation')
            self.assertNotEqual(res.returncode,0)
            self.assertIn('terrain coverage',res.stdout+res.stderr)
            self.assertNotIn('fetching',res.stdout+res.stderr)

    def test_explicit_terrain_input_is_checked_before_osm_networking(self):
        import subprocess
        res = subprocess.run(
            [sys.executable, str(Path(osm_import.__file__)), 'turku',
             '--terrain', 'missing-terrain.tif'],
            capture_output=True, text=True, timeout=5,
        )
        self.assertNotEqual(res.returncode, 0)
        self.assertIn('terrain file not found', res.stdout + res.stderr)
        self.assertNotIn('fetching', res.stdout + res.stderr)


if __name__ == '__main__':
    unittest.main()
