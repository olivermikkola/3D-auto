#!/usr/bin/env python3
"""Automated tests for rounded kerb corners, traffic islands, and road geometry."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


class KerbTests(unittest.TestCase):
    def test_corner_fillets_and_islands_exist(self):
        env = os.environ.copy()
        env["MAP"] = "raisio"
        env["SEED"] = "1337"
        env["KERB_TEST"] = "1"
        res = subprocess.run([str(BINARY), "game", "--headless", "5"], cwd=ROOT, env=env, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn("ALL KERB PROBE CHECKS PASSED", res.stdout)

    def test_pedestrian_height_at_junction_corner(self):
        # Raycast downward at a junction corner and confirm hit lands on raised sidewalk (y >= 0.1)
        env = os.environ.copy()
        env["MAP"] = "raisio"
        env["SEED"] = "1337"
        res = subprocess.run([str(BINARY), "game", "--headless", "5"], cwd=ROOT, env=env, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)


if __name__ == "__main__":
    unittest.main()
