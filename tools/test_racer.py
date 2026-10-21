#!/usr/bin/env python3
"""Street racers: one waits near you at night, races you to a landmark
junction by junction; first there wins (none on a grid map)."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


@unittest.skipUnless(BINARY.exists(), "needs a release build")
class RacerTests(unittest.TestCase):
    def test_street_racer(self):
        for name in ("turku", "starter"):
            with self.subTest(map=name):
                env = dict(os.environ, MAP=name, SEED="1337", RACER_TEST="1")
                with tempfile.TemporaryDirectory() as d:
                    env["XDG_DATA_HOME"] = d
                    res = subprocess.run([str(BINARY), "game", "--headless", "6000"], cwd=ROOT, env=env,
                                         capture_output=True, text=True, encoding="utf-8", errors="replace",
                                         timeout=600)
                out = res.stdout + res.stderr
                self.assertEqual(res.returncode, 0, out)
                self.assertIn(f"RACER_PROBE {name}: PASSED", out, out)


if __name__ == "__main__":
    unittest.main()
