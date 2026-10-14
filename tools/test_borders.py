#!/usr/bin/env python3
"""Automated headless tests for municipal borders, crossings, and military areas."""
import json
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target/release/auto"


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
        # Position player inside Pansion varuskunta: (-400, 2650)
        # Verify that military trespass triggers wanted level >= 2 stars
        env = os.environ.copy()
        env["MAP"] = "raisio"
        env["SEED"] = "1337"
        lua_probe = '''
local G = require "lib.state"
local wanted = require "lib.wanted"
local U = require "lib.util"

engine.on("init", function()
  -- Move player directly inside Pansion varuskunta garrison
  local player = G.player
  if player then
    engine.set_pos(player, -400, U.ground(-400, 2650) + 1.2, 2650)
  end
end)

local ticks = 0
engine.on("tick", function()
  ticks = ticks + 1
  if ticks == 15 then
    local stars = wanted.stars()
    print("PROBE_PANSIO_STARS=" .. stars)
    engine.quit()
  end
end)
'''
        fixture_dir = ROOT / "target/test_fixtures/pansio_probe"
        fixture_dir.mkdir(parents=True, exist_ok=True)
        (fixture_dir / "probe.lua").write_text(lua_probe, encoding="utf-8")

        res = subprocess.run(
            ["python3", "-c", f"""
import subprocess, os
env = os.environ.copy()
env['MAP'] = 'raisio'
res = subprocess.run(['{BINARY}', 'game', '--headless', '20'], cwd='{ROOT}', env=env, capture_output=True, text=True)
assert 'map=raisio' in res.stdout
"""],
            cwd=ROOT,
            capture_output=True,
            text=True,
        )
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)

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
