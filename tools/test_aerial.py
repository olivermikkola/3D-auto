"""tools/aerial.py on a made-up photo: a roof's colour, shadows, crowns and
the white outside a flight."""
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import aerial

try:
    import numpy as np
    from PIL import Image
except ImportError:  # the importer's aerial step needs them; skip without
    np = None


@unittest.skipIf(np is None, "needs numpy and Pillow")
class AerialTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        rng = np.random.default_rng(1)
        img = np.full((1000, 1000, 3), 128, dtype=np.uint8)  # grey asphalt
        img[100:200, 100:200] = (150, 60, 45)  # a red tile roof, x/z 100-200
        img[300:400, 300:400] = (30, 30, 50)  # a shadow
        crowns = rng.integers(0, 2, (100, 100)).astype(bool)  # leaves and their shadows
        img[500:600, 500:600] = np.where(crowns[..., None], (60, 140, 50), (25, 60, 22))
        img[700:800, 700:800] = (100, 170, 90)  # an even lawn
        img[900:, 900:] = 255  # outside the flight
        Image.fromarray(img).save(Path(self.tmp.name) / "0_0.jpg", quality=97)
        self.a = aerial.Aerial("turku", (60.45, 22.27), (0, 0, 999, 999), source="turku")
        self.a.dir = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def test_a_roof_is_its_tiles_colour(self):
        r, g, b = self.a.roof_of_box(150, 150, 60, 60, 0.3)
        self.assertGreater(r, g * 1.8)
        self.assertGreater(r, b * 1.8)

    def test_a_shadow_is_grey_not_blue(self):
        r, g, b = self.a.robust([350, 360], [350, 360])
        self.assertLess(max(r, g, b) - min(r, g, b), 0.02)

    def test_crowns_are_lumpy_lawns_are_even(self):
        tree, lawn, road = self.a.canopy([550, 750, 50], [550, 750, 50]).tolist()
        self.assertEqual((tree, lawn, road), (True, False, False))

    def test_white_outside_the_flight_is_no_photo(self):
        self.assertIsNone(self.a.robust([950, 960], [950, 960]))
        palette, idx = self.a.ground([50, 950], [50, 950], 10, n=1)
        self.assertEqual(idx.tolist()[1], -1)
        self.assertEqual(idx.tolist()[0], 0)


if __name__ == "__main__":
    unittest.main()
