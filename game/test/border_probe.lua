-- Headless probe for municipal borders, wooden footbridges, and military garrison.
local G = require "lib.state"
local city = require "lib.city"
local wanted = require "lib.wanted"
local U = require "lib.util"

local map = city.map()
assert(map.military and #map.military > 0, "military area missing from map")
assert(map.wooden_footbridges and #map.wooden_footbridges > 0, "wooden footbridge missing from map")
assert(map.border_crossings and #map.border_crossings > 0, "border crossings missing from map")

engine.on("init", function()
  local fences = engine.find("fence")
  local guardhouses = engine.find("guardhouse")
  local boom_barriers = engine.find("boom_barrier")
  local bollards = engine.find("bollard")
  local bridges = engine.find("bridge")
  local road_barriers = engine.find("barrier")

  print(string.format("COUNTS fences=%d guardhouses=%d boom_barriers=%d bollards=%d bridges=%d road_barriers=%d",
                      #fences, #guardhouses, #boom_barriers, #bollards, #bridges, #road_barriers))
  assert(#fences >= 100, "fences not extruded around perimeter")
  assert(#guardhouses >= 1, "guardhouse not spawned at gate")
  assert(#boom_barriers >= 1, "boom barrier not spawned at gate")
  assert(#bollards >= 2, "bollards not spawned at bridge ends")
  assert(#bridges >= 1, "wooden footbridge not spawned")
  assert(#road_barriers >= 6, "road crossings not blocked with barriers")

  -- Move player inside Pansion military base
  local player = G.player
  if player then
    engine.set_pos(player, -900, U.ground(-900, 2870) + 1.2, 2870)
  end
end)

local ticks = 0
engine.on("tick", function()
  ticks = ticks + 1
  if ticks == 20 then
    local stars = wanted.stars()
    print("PROBE_PANSIO_STARS=" .. stars)
    assert(stars >= 2, "trespassing inside military base did not trigger wanted level")
    print("ALL BORDER PROBE CHECKS PASSED")
    engine.quit()
  end
end)
