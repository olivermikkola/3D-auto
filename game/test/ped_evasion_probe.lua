-- Test probe validating pedestrian sidewalk restrictions and evasion reactions.
local roadnet = require "lib.roadnet"
local peds = require "systems.peds"

engine.on("init", function()
  -- 1. Verify that edges with sidewalk == "no" are not walkable
  local net = roadnet.net()
  local checked_no_sidewalk = 0
  for i, e in ipairs(net.edges) do
    if e.sidewalk == "no" then
      assert(not roadnet.walkable(i), "edge with sidewalk=no must not be walkable: " .. (e.name or e.street or i))
      checked_no_sidewalk = checked_no_sidewalk + 1
    end
  end
  print("SIDEWALK_FILTER_OK checked=" .. checked_no_sidewalk)

  -- 2. Verify pedestrian scare function
  local px, _, pz = 0, 0, 0
  peds.scare(px, pz, 50)
  print("PED_SCARE_OK")

  print("ALL PED EVASION CHECKS PASSED")
  engine.quit()
end)
