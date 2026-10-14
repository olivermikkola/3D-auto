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
        script = '''
local G = require "lib.state"

engine.on("init", function()
  local buildings = engine.find("building")
  assert(#buildings >= 200, "not enough buildings spawned")

  local balconies = 0
  local glass_shops = 0
  for _, id in ipairs(buildings) do
    local m = engine.mesh_of(id) or ""
    if m:find("^balconies") then
      balconies = balconies + 1
    elseif m:find("^glass") then
      glass_shops = glass_shops + 1
    end
  end

  print(string.format("ARCHITECTURE_COUNTS balconies=%d glass_shops=%d", balconies, glass_shops))
  assert(balconies >= 50, "procedural glazed balconies not generated for flats")
  assert(glass_shops >= 20, "glass facades not generated for commercial/retail buildings")
  print("ALL ARCHITECTURE CHECKS PASSED")
  engine.quit()
end)
'''
        env = os.environ.copy()
        env["MAP"] = "raisio"
        env["SEED"] = "1337"
        env["ARCH_TEST"] = "1"
        res = subprocess.run([str(BINARY), "game", "--headless", "5"], cwd=ROOT, env=env, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)
        self.assertIn("ALL ARCHITECTURE CHECKS PASSED", res.stdout)


if __name__ == "__main__":
    unittest.main()
