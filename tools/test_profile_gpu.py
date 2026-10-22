#!/usr/bin/env python3
"""PROFILE=1 on a real window names the GPU and times it.

The CPU-side "draw" figure only covers handing the commands over. Frame
drops reported from a real machine need the other half: which GPU and
driver drew the game (a software renderer such as llvmpipe explains a
slideshow on its own) and how long the GPU took per frame, from GL timer
queries.

Needs a display, so it is opt-in like the landmark renders: RENDER_CHECKS=1.
CI runs it under xvfb-run with Mesa's software renderer, which the report
has to call out as software."""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


@unittest.skipUnless(os.environ.get("RENDER_CHECKS") == "1", "set RENDER_CHECKS=1 (needs a display; CI uses xvfb-run)")
class ProfileGpuTests(unittest.TestCase):
    def test_profile_names_and_times_the_gpu(self):
        with tempfile.TemporaryDirectory(prefix="auto-gpu-") as folder:
            env = dict(os.environ, MAP="starter", SEED="1337", PROFILE="1")
            # Enough frames that a two-second report comes out even at a high frame rate.
            command = [str(BINARY), "game", "--screenshot", str(Path(folder) / "shot.ppm"), "--frames", "300",
                       "--size", "640x360", "--save-dir", str(Path(folder) / "save")]
            res = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True, timeout=600)
            self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
            out = res.stdout
            name = re.search(r"^profile: GPU (.+), OpenGL (\S+)", out, re.M)
            self.assertIsNotNone(name, out)
            gpu = re.search(r"\| gpu (\d+\.\d) ms \|", out)
            self.assertIsNotNone(gpu, out)
            self.assertGreater(float(gpu.group(1)), 0.0, out)
            if "llvmpipe" in name.group(1):
                self.assertIn("SOFTWARE rendering", out)


if __name__ == "__main__":
    unittest.main()
