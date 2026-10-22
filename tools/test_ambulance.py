#!/usr/bin/env python3
"""Ambulance calls: an ambulance by the hospital; in it, calls come from real
places (street corners without them) with a clock, the GPS leads to the
patient and on to the nearest hospital, a knock costs seconds, it pays by
the time left; too late or leaving it calls it off; a lost one comes back."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


@unittest.skipUnless(BINARY.exists(), "needs a release build")
class AmbulanceTests(unittest.TestCase):
    def test_ambulance_on_every_kind_of_map(self):
        for name in ("turku", "raisio", "starter"):
            with self.subTest(map=name):
                env = dict(os.environ, MAP=name, SEED="1337", AMBULANCE_TEST="1")
                with tempfile.TemporaryDirectory() as d:
                    env["XDG_DATA_HOME"] = d
                    res = subprocess.run([str(BINARY), "game", "--headless", "120000"], cwd=ROOT, env=env,
                                         capture_output=True, text=True, encoding="utf-8", errors="replace",
                                         timeout=1800)
                out = res.stdout + res.stderr
                self.assertEqual(res.returncode, 0, out)
                self.assertIn(f"AMBULANCE_PROBE {name}: PASSED", out, out)


if __name__ == "__main__":
    unittest.main()
