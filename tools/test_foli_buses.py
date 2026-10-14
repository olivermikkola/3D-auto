#!/usr/bin/env python3
"""Automated tests for Föli municipal buses and transit operations."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parent.parent
BINARY = ROOT / "target" / "release" / ("auto.exe" if os.name == "nt" else "auto")


class FoliBusTests(unittest.TestCase):
    def test_foli_bus_spawning_and_transit_mission(self):
        script = '''
local G = require "lib.state"
local vehicle = require "lib.vehicle"
local mission = require "lib.mission"

engine.on("init", function()
  -- Spawn Föli bus
  local bus_id = vehicle.spawn(870, -1700, 0, nil, "bus", "bus")
  assert(engine.exists(bus_id), "Föli bus failed to spawn")
  assert(vehicle.tags[engine.tag(bus_id)], "bus tag is not drivable")
  print("FOLI_BUS_SPAWN_OK id=" .. bus_id)

  -- Verify Line 7 transit mission loaded
  local all = mission.all()
  local found_foli = false
  for _, m in ipairs(all) do
    if m.title == "Föli Transit: Line 7" then
      found_foli = true
      break
    end
  end
  assert(found_foli, "09_foli_transit mission was not loaded")
  print("ALL FOLI CHECKS PASSED")
  engine.quit()
end)
'''
        env = os.environ.copy()
        env["MAP"] = "raisio"
        env["SEED"] = "1337"
        env["FOLI_TEST"] = "1"
        res = subprocess.run([str(BINARY), "game", "--headless", "10"], cwd=ROOT, env=env, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertRegex(res.stdout, r"loaded \d+ missions")
        self.assertIn("ALL FOLI CHECKS PASSED", res.stdout)


if __name__ == "__main__":
    unittest.main()
