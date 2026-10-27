#!/usr/bin/env python3
"""Traffic lights: a car heading into a junction with lights waits at the
line on red (not taken for stuck), the posts show red, and it drives on when
they turn green."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


@unittest.skipUnless(BINARY.exists(), "needs a release build")
class SignalsTests(unittest.TestCase):
    def test_cars_stop_on_red(self):
        for name in ("turku", "raisio"): # (the maps with lights)
            with self.subTest(map=name):
                env = dict(os.environ, MAP=name, SEED="1337", SIGNALS_TEST="1")
                with tempfile.TemporaryDirectory() as d:
                    env["XDG_DATA_HOME"] = d
                    res = subprocess.run([str(BINARY), "game", "--headless", "6000"], cwd=ROOT, env=env,
                                         capture_output=True, text=True, encoding="utf-8", errors="replace",
                                         timeout=600)
                out = res.stdout + res.stderr
                self.assertEqual(res.returncode, 0, out)
                self.assertIn(f"SIGNALS_PROBE {name}: PASSED", out, out)


if __name__ == "__main__":
    unittest.main()
