#!/usr/bin/env python3
"""Layers (engine::Entity::layer): underground, bodies in layer 1 keep to
their own floor under the terrain, and rays only see their own layer."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


class LayersTests(unittest.TestCase):
    def test_turku(self):
        env = dict(os.environ, MAP="turku", SEED="1337", LAYERS_TEST="1")
        res = subprocess.run([str(BINARY), "game", "--headless", "3000"], cwd=ROOT, env=env,
                             capture_output=True, text=True, timeout=600)
        out = res.stdout + res.stderr
        self.assertEqual(res.returncode, 0, out[-3000:])
        self.assertNotIn("[lua:", out)
        self.assertIn("ALL LAYERS CHECKS PASSED", out, out[-3000:])


if __name__ == "__main__":
    unittest.main()
