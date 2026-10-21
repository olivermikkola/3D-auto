#!/usr/bin/env python3
"""Weather: clear at the start, turning by the seed every three hours; rain
greys the sky, pulls the fog in, and wet roads brake longer."""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


@unittest.skipUnless(BINARY.exists(), "needs a release build")
class WeatherTests(unittest.TestCase):
    def test_weather_on_a_survey_map_and_a_grid_map(self):
        for name in ("turku", "starter"):
            with self.subTest(map=name):
                env = dict(os.environ, MAP=name, SEED="1337", WEATHER_TEST="1")
                env.pop("WEATHER", None)
                with tempfile.TemporaryDirectory() as d:
                    env["XDG_DATA_HOME"] = d
                    res = subprocess.run([str(BINARY), "game", "--headless", "3000"], cwd=ROOT, env=env,
                                         capture_output=True, text=True, encoding="utf-8", errors="replace",
                                         timeout=600)
                out = res.stdout + res.stderr
                self.assertEqual(res.returncode, 0, out)
                self.assertIn(f"WEATHER_PROBE {name}: PASSED", out, out)
                m = re.search(r"([\d.]+) m dry, ([\d.]+) m wet", out)
                self.assertTrue(m, out)
                self.assertGreater(float(m[2]), float(m[1]) * 1.2)


if __name__ == "__main__":
    unittest.main()
