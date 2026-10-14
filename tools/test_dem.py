#!/usr/bin/env python3
"""Fail-closed GeoTIFF input acceptance; tiny rasters are synthetic fixtures."""
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import dem

try:
    from PIL import Image, TiffImagePlugin
except ImportError:
    Image = TiffImagePlugin = None


@unittest.skipIf(Image is None, 'Pillow only required for importer tests')
class StrictElevationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def tile(self, name='fixture', values=None, scale=2, crs=3067, nodata='-9999'):
        assert Image is not None and TiffImagePlugin is not None
        im = Image.new('F', (3, 3))
        im.putdata(values if values is not None else [10,12,14,20,22,24,30,32,34])
        tags = TiffImagePlugin.ImageFileDirectory_v2()
        tags[33550] = (float(scale), float(scale), 0.)
        tags[33922] = (0.,0.,0.,236000.,6714000.,0.)
        tags[34735] = (1,1,0,2,1025,0,1,1,3072,0,1,crs)
        tags[42113] = nodata
        p = self.root / (name + '.tif')
        im.save(p, tiffinfo=tags)
        return p

    def test_reads_verified_2m_raster_at_pixel_centres(self):
        p = self.tile()
        self.assertTrue(hasattr(dem.Elevation, 'from_paths'), 'explicit validated input loader required')
        source = dem.Elevation.from_paths([p], expected_resolution=2)
        self.assertAlmostEqual(source(236001.,6713999.),10.)
        self.assertAlmostEqual(source(236002.,6713998.),16.)
        self.assertEqual(source.metadata[0]['resolution_m'], [2.,2.])
        self.assertEqual(source.metadata[0]['crs'], 'EPSG:3067')

    def test_rejects_wrong_resolution_and_coordinate_system(self):
        for label, kwargs in [('resolution', {'scale':10}), ('CRS', {'crs':4326})]:
            with self.subTest(case=label):
                p = self.tile(name=label, **kwargs)
                with self.assertRaisesRegex(ValueError, label):
                    dem.Elevation.from_paths([p], expected_resolution=2)

    def test_float_nodata_value_is_honored(self):
        p = self.tile(values=[12345]*9, nodata='12345')
        source = dem.Elevation.from_paths([p], expected_resolution=2)
        with self.assertRaisesRegex(ValueError, 'no.data'):
            source(236001.,6713999.)

    def test_tiny_rasters_and_missing_georeferencing_are_rejected(self):
        assert Image is not None
        im = Image.new('F', (1,1),10)
        p = self.root / 'unreferenced.tif'
        im.save(p)
        with self.assertRaisesRegex(ValueError, 'georeferencing|dimensions'):
            dem.Elevation.from_paths([p])

    def test_missing_coverage_and_nodata_do_not_become_sea_level(self):
        p = self.tile()
        source = dem.Elevation.from_paths([p], expected_resolution=2)
        with self.assertRaisesRegex(ValueError, 'coverage'):
            source(240000.,6713999.)
        p = self.tile(name='nodata', values=[-9999]*9)
        source = dem.Elevation.from_paths([p], expected_resolution=2)
        with self.assertRaisesRegex(ValueError, 'no.data'):
            source(236001.,6713999.)
        with self.assertRaisesRegex(ValueError, 'at least one'):
            dem.Elevation.from_paths([], expected_resolution=2)


if __name__ == '__main__':
    unittest.main()
