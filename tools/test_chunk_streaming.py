#!/usr/bin/env python3
"""Automated tests for spatial chunk streaming and culling."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


class ChunkStreamingTests(unittest.TestCase):
    def test_chunk_streaming_active_around_player(self):
        env = os.environ.copy()
        env["MAP"] = "raisio"
        env["SEED"] = "1337"
        env["CHUNK_TEST"] = "1"
        res = subprocess.run([str(BINARY), "game", "--headless", "15"], cwd=ROOT, env=env, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn("ALL CHUNK STREAMING CHECKS PASSED", res.stdout)


if __name__ == "__main__":
    unittest.main()
