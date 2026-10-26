#!/usr/bin/env python3
"""Bus shelters: most bus stops get one, off the carriageway, backed by
nothing, standing level."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


@unittest.skipUnless(BINARY.exists(), "needs a release build")
class SheltersTests(unittest.TestCase):
    def test_shelters_at_bus_stops(self):
        for name in ("turku", "raisio"): # (the maps with bus stops)
            with self.subTest(map=name):
                env = dict(os.environ, MAP=name, SEED="1337", SHELTERS_TEST="1")
                with tempfile.TemporaryDirectory() as d:
                    env["XDG_DATA_HOME"] = d
                    res = subprocess.run([str(BINARY), "game", "--headless", "600"], cwd=ROOT, env=env,
                                         capture_output=True, text=True, encoding="utf-8", errors="replace",
                                         timeout=600)
                out = res.stdout + res.stderr
                self.assertEqual(res.returncode, 0, out)
                self.assertIn(f"SHELTERS_PROBE {name}: PASSED", out, out)


if __name__ == "__main__":
    unittest.main()
