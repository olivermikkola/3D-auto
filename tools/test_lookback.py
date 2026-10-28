#!/usr/bin/env python3
"""In a car, holding the right stick's click (or C) looks back, and letting go looks ahead again."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


class LookBackTests(unittest.TestCase):
    def test_starter(self):
        env = dict(os.environ, MAP="starter", SEED="1337", LOOKBACK_TEST="1")
        res = subprocess.run([str(BINARY), "game", "--headless", "900"], cwd=ROOT, env=env,
                             capture_output=True, text=True, timeout=300)
        out = res.stdout + res.stderr
        self.assertEqual(res.returncode, 0, out)
        self.assertNotIn("[lua:", out)
        self.assertIn("LOOKBACK_PROBE: PASSED", out, out[-3000:])


if __name__ == "__main__":
    unittest.main()
