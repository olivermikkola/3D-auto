#!/usr/bin/env python3
"""Automated tests for Finnish architectural styling: balconies, shops, and roofs."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


class ArchitectureTests(unittest.TestCase):
    def test_glazed_balconies_and_glass_shops_spawned(self):
        env = os.environ.copy()
        env["MAP"] = "raisio"
        env["SEED"] = "1337"
        env["ARCH_TEST"] = "1"
        res = subprocess.run([str(BINARY), "game", "--headless", "5"], cwd=ROOT, env=env, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn("ALL ARCHITECTURE CHECKS PASSED", res.stdout)


if __name__ == "__main__":
    unittest.main()
