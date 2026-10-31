#!/usr/bin/env python3
"""Covered tunnels have a roof and clear lanes; Unioninkatu at the old
Wärtsilä works, through a hill's nose, is one (it was an open cutting)."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


class TunnelTests(unittest.TestCase):
    def test_turku(self):
        env = dict(os.environ, MAP="turku", SEED="1337", TUNNEL_TEST="1")
        res = subprocess.run([str(BINARY), "game", "--headless", "600"], cwd=ROOT, env=env,
                             capture_output=True, text=True, timeout=600)
        out = res.stdout + res.stderr
        self.assertEqual(res.returncode, 0, out[-3000:])
        self.assertNotIn("[lua:", out)
        self.assertIn("TUNNEL_OK", out, out[-3000:])


if __name__ == "__main__":
    unittest.main()
