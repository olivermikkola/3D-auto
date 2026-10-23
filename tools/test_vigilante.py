#!/usr/bin/env python3
"""Vigilante: in a police car with no stars, suspects are called in near
you and run; the GPS leads to them; ramming one is no crime; wrecking or
boxing one in pays by level and raises it; the clock lets one get away;
leaving the car or a star ends the shift."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


@unittest.skipUnless(BINARY.exists(), "needs a release build")
class VigilanteTests(unittest.TestCase):
    def test_vigilante_on_every_kind_of_map(self):
        for name in ("turku", "raisio", "starter"):
            with self.subTest(map=name):
                env = dict(os.environ, MAP=name, SEED="1337", VIGILANTE_TEST="1")
                with tempfile.TemporaryDirectory() as d:
                    env["XDG_DATA_HOME"] = d
                    res = subprocess.run([str(BINARY), "game", "--headless", "120000"], cwd=ROOT, env=env,
                                         capture_output=True, text=True, encoding="utf-8", errors="replace",
                                         timeout=1800)
                out = res.stdout + res.stderr
                self.assertEqual(res.returncode, 0, out)
                self.assertIn(f"VIGILANTE_PROBE {name}: PASSED", out, out)


if __name__ == "__main__":
    unittest.main()
