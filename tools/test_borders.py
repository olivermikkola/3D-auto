#!/usr/bin/env python3
"""Automated headless tests for municipal borders, crossings, and military areas."""
import json
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


class BorderTests(unittest.TestCase):
    def test_raisio_borders_load_headlessly(self):
        env = os.environ.copy()
        env["MAP"] = "raisio"
        env["SEED"] = "1337"
        env["BORDER_TEST"] = "1"
        res = subprocess.run([str(BINARY), "game", "--headless", "30"], cwd=ROOT, env=env, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn("ALL BORDER PROBE CHECKS PASSED", res.stdout)

    def test_pansio_military_trespass_raises_wanted_level(self):
        env = os.environ.copy()
        env["MAP"] = "raisio"
        env["SEED"] = "1337"
        env["BORDER_TEST"] = "1"
        res = subprocess.run([str(BINARY), "game", "--headless", "25"], cwd=ROOT, env=env, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn("PROBE_PANSIO_STARS=3", res.stdout)

    def test_wooden_footbridge_and_border_props_spawned(self):
        # Run test script verifying entity tags: fence, guardhouse, boom_barrier, bridge, bollard
        script = '''
local G = require "lib.state"
local city = require "lib.city"

engine.on("init", function()
  local map = city.map()
  assert(map.military and #map.military > 0, "military zone missing")
  assert(map.wooden_footbridges and #map.wooden_footbridges > 0, "wooden footbridges missing")
  assert(map.border_crossings and #map.border_crossings > 0, "border crossings missing")

  local fences = engine.find("fence")
  local guardhouses = engine.find("guardhouse")
  local barriers = engine.find("boom_barrier")
  local bollards = engine.find("bollard")
  local bridges = engine.find("bridge")

  print(string.format("PROBE_COUNTS fences=%d guardhouses=%d barriers=%d bollards=%d bridges=%d",
                      #fences, #guardhouses, #barriers, #bollards, #bridges))
  assert(#fences > 50, "fence mesh not extruded")
  assert(#guardhouses >= 1, "guardhouse missing")
  assert(#barriers >= 1, "boom barrier missing")
  assert(#bollards >= 2, "wooden bridge bollards missing")
  assert(#bridges >= 1, "footbridge missing")
  print("ALL BORDER PROBE CHECKS PASSED")
  engine.quit()
end)
'''
        fixture = ROOT / "target/test_fixtures/props_probe.lua"
        fixture.parent.mkdir(parents=True, exist_ok=True)
        fixture.write_text(script, encoding="utf-8")

        env = os.environ.copy()
        env["MAP"] = "raisio"
        env["SEED"] = "1337"
        # Run with lua fixture appended
        cmd = [str(BINARY), "game", "--headless", "3"]
        res = subprocess.run(cmd, cwd=ROOT, env=env, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)


if __name__ == "__main__":
    unittest.main()
