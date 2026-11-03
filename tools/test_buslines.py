#!/usr/bin/env python3
"""Föli's lines: every junction turku_bus.lua names is one of turku_osm.lua's
(re-run tools/foli_lines.py after importing the map again), and in the game
traffic's buses drive their lines (game/test/buslines_probe.lua)."""
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")
sys.path.insert(0, str(ROOT / "tools"))


class BusLinesTests(unittest.TestCase):
    def test_lines_name_the_maps_junctions(self):
        import foli_lines
        _, _, pos, edges = foli_lines.load_map(ROOT / "game" / "maps" / "turku_osm.lua")
        links = {(u, v) for u, v, _, _ in edges} | {(v, u) for u, v, _, one in edges if not one}
        text = (ROOT / "game" / "maps" / "turku_bus.lua").read_text(encoding="utf-8")
        lines = re.findall(r'\{line = "([^"]+)", to = "([^"]*)".*?\n   (.*?)\},\n', text, re.S)
        self.assertGreater(len(lines), 140)
        for line, to, body in lines:
            js = re.findall(r'"((?:[^"\\]|\\.)*)"', body)
            for name in js:
                self.assertIn(name, pos, f"line {line} to {to}: no junction {name!r} on the map")
            for a, b in zip(js, js[1:]):
                self.assertIn((a, b), links, f"line {line} to {to}: no street {a!r} -> {b!r}")

    def test_lua_values(self):
        import foli_lines
        v, end = foli_lines.lua_value('{name = "A \\"B\\"", width = 7.3, oneway = true, heights = {1, 2}, "J1", {1.5, -2}, "J2"}', 0)
        items, keyed = v
        self.assertEqual(items[0], "J1")
        self.assertEqual(items[1][0], [1.5, -2.0])
        self.assertEqual(items[2], "J2")
        self.assertEqual(keyed["name"], 'A "B"')
        self.assertIs(keyed["oneway"], True)

    @unittest.skipUnless(BINARY.exists(), "needs a release build")
    def test_buses_drive_their_lines(self):
        env = dict(os.environ, MAP="turku", SEED="1337", BUSLINES_TEST="1")
        with tempfile.TemporaryDirectory() as d:
            res = subprocess.run([str(BINARY), "game", "--headless", "9000", "--save-dir", d], cwd=ROOT, env=env,
                                 capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=900)
        out = res.stdout + res.stderr
        self.assertEqual(res.returncode, 0, out[-3000:])
        self.assertIn("BUSLINES TEST PASSED", out, out[-3000:])


if __name__ == "__main__":
    unittest.main()
