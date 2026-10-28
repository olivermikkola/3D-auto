#!/usr/bin/env python3
"""Shop signs: most of Turku's shops, cafés and pubs get one, flat on a
building's wall, facing out, at shop-sign height, off the carriageway."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


@unittest.skipUnless(BINARY.exists(), "needs a release build")
class ShopSignsTests(unittest.TestCase):
    def test_signs_on_shop_walls(self):
        env = dict(os.environ, MAP="turku", SEED="1337", SIGNS_TEST="1")
        with tempfile.TemporaryDirectory() as d:
            env["XDG_DATA_HOME"] = d
            res = subprocess.run([str(BINARY), "game", "--headless", "600"], cwd=ROOT, env=env,
                                 capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=600)
        out = res.stdout + res.stderr
        self.assertEqual(res.returncode, 0, out)
        self.assertIn("SIGNS TEST PASSED", out, out)

    def test_low_quality_has_none(self):
        """The lowest quality tier puts none up (as with the shelters)."""
        src = (ROOT / "game" / "systems" / "shopsigns.lua").read_text(encoding="utf-8")
        self.assertIn("quality.tier() > 1", src)


if __name__ == "__main__":
    unittest.main()
