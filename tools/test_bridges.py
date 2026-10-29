#!/usr/bin/env python3
"""Bridges: no deck end dropping off the street it meets, and no more
bridges a bus can't pass under than we know of (BRIDGE_AUDIT=1)."""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")

# Bridges a bus still can't pass under (at one spot each), per map: Turku's
# Aninkaistensilta, whose south end lands ~17 m past Virusmäenramppi, too
# close to climb over it; Raisio's Raisionlahdentie / Naantalintie over
# Upalingontie, 44 m end to end, too short to. (Before: Turku 5, Raisio 9.)
# Lower these as they're fixed; never raise them.
BLOCKED_MAX = {"turku": 1, "raisio": 1}
STEP_MAX = 1.0  # meters between a deck's end and the street it meets


@unittest.skipUnless(BINARY.exists(), "needs a release build")
class BridgeTests(unittest.TestCase):
    def audit(self, map_name):
        env = dict(os.environ, MAP=map_name, SEED="1337", BRIDGE_AUDIT="1")
        with tempfile.TemporaryDirectory() as d:
            env["XDG_DATA_HOME"] = d
            res = subprocess.run([str(BINARY), "game", "--headless", "2"], cwd=ROOT, env=env,
                                 capture_output=True, text=True, timeout=600)
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        m = re.search(r"BRIDGE_AUDIT: (\d+) bridge stretches, (\d+) with a road under that a bus can't pass", res.stdout)
        self.assertTrue(m, res.stdout + res.stderr)
        return res.stdout, int(m[1]), int(m[2])

    def test_maps(self):
        for name, most in BLOCKED_MAX.items():
            with self.subTest(map=name):
                out, bridges, blocked = self.audit(name)
                self.assertGreater(bridges, 0)
                self.assertLessEqual(blocked, most, out)
                steps = [(line.split("  ")[0], float(s)) for line in out.splitlines()
                         for s in re.findall(r"step +([\d.]+)", line)]
                self.assertTrue(steps, out)
                high = [(b, s) for b, s in steps if s > STEP_MAX]
                self.assertEqual(high, [], "deck ends off their streets")
                if name == "turku":
                    self.assertIn("RAIL_UNDERPASS_OK", out)

    def test_auransilta_meets_aurakatu(self):
        out, _, _ = self.audit("turku")
        line = next(line for line in out.splitlines() if line.startswith("BRIDGE Auransilta"))
        self.assertRegex(line, r"step +0\.\d")
        water = float(re.search(r"water +(-?[\d.]+)", line)[1])
        self.assertGreater(water, 2.0, line)  # was -1.3: the deck dipped into the river


if __name__ == "__main__":
    unittest.main()
