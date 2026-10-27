#!/usr/bin/env python3
"""Turku's sounds of the place: the cathedral strikes the hours, gulls call over the water."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


class AmbienceTests(unittest.TestCase):
    def test_noon_bells_and_gulls(self):
        env = os.environ.copy()
        env.update(MAP="turku", SEED="1337", HOUR="11.95", AMBIENCE_TEST="1")
        res = subprocess.run([str(BINARY), "game", "--headless", "2600"], cwd=ROOT, env=env,
                             capture_output=True, text=True, timeout=600)
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn("ALL AMBIENCE CHECKS PASSED", res.stdout, res.stdout[-3000:] + res.stderr[-3000:])


if __name__ == "__main__":
    unittest.main()
