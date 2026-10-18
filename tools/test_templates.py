#!/usr/bin/env python3
"""Mission templates: one story cast into real places by seed, on every
map with points of interest (docs/MISSION_TEMPLATES.md)."""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


@unittest.skipUnless(BINARY.exists(), "needs a release build")
class TemplateTests(unittest.TestCase):
    def probe(self, map_name):
        env = dict(os.environ, MAP=map_name, SEED="1337", TEMPLATE_TEST="1")
        with tempfile.TemporaryDirectory() as d:
            env["XDG_DATA_HOME"] = d
            res = subprocess.run([str(BINARY), "game", "--headless", "3000"], cwd=ROOT, env=env,
                                 capture_output=True, text=True, timeout=600)
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn("TEMPLATE_PROBE: PASSED", res.stdout, res.stdout + res.stderr)
        return res.stdout

    def versions(self, out):
        m = re.search(r"(\d+)/(\d+) seeds cast, (\d+) different versions", out)
        self.assertTrue(m, out)
        return int(m[1]), int(m[2]), int(m[3])

    def test_turku_and_raisio_get_many_versions(self):
        for name in ("turku", "raisio"):
            with self.subTest(map=name):
                cast, seeds, versions = self.versions(self.probe(name))
                self.assertEqual(cast, seeds)
                self.assertGreaterEqual(versions, seeds * 0.8)

    def test_hesburger_express_is_played_on_both_maps(self):
        for name in ("turku", "raisio"):
            with self.subTest(map=name):
                out = self.probe(name)
                m = re.search(r"Häsburger Express: (\d+)/(\d+) seeds playable, (\d+) different runs", out)
                self.assertTrue(m, out)
                self.assertEqual(m[1], m[2])
                self.assertGreaterEqual(int(m[3]), int(m[2]) * 0.6)
                self.assertIn("Häsburger Express played, 3 customers, passed", out)

    def test_a_grid_map_casts_nothing(self):
        self.assertIn("grid map, nothing to cast", self.probe("starter"))


if __name__ == "__main__":
    unittest.main()
