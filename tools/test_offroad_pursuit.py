#!/usr/bin/env python3
"""Cops reach a player standing off the road (game/test/offroad_probe.lua):
twenty spots 20-60 m from the nearest road across Turku, three stars each."""
import os
import re
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


class OffroadPursuitTests(unittest.TestCase):
    def test_cops_reach_every_off_road_spot(self):
        with tempfile.TemporaryDirectory(prefix="offroad-") as saves:
            env = dict(os.environ, MAP="turku", SEED="1337", OFFROAD_TEST="1", OFFROAD_SPOTS="20",
                       XDG_DATA_HOME=saves, APPDATA=saves)
            res = subprocess.run([str(BINARY), "game", "--headless", "150000"], cwd=ROOT, env=env,
                                 capture_output=True, text=True, timeout=600)
        out = res.stdout + res.stderr
        self.assertEqual(res.returncode, 0, out)
        self.assertNotIn("[lua:", out)
        self.assertIn("OFFROAD DONE", out)
        # Of 20 spots, any closed off from the nearest road by a building
        # (a courtyard: a fair place to hide) are left out; every other one
        # must be reached.
        m = re.search(r"OFFROAD (\d+) of (\d+) reached", out)
        self.assertTrue(m, out)
        self.assertEqual(m[1], m[2], out)
        self.assertGreaterEqual(int(m[2]), 18, out)


if __name__ == "__main__":
    unittest.main()
