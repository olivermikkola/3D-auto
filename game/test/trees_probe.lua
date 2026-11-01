-- TREES_TEST=1 (MAP=turku): the aerial photo's trees (lib/roadnet R.trees,
-- baked by engine.forest). There are as many as the photo shows, none
-- stands on a road or in the river, the quality setting thins them, and a
-- car driven at one stops at its trunk (systems/trees).
local R = require "lib.roadnet"
local quality = require "lib.quality"
local settings = require "lib.settings"
local vehicle = require "lib.vehicle"
local input = require "lib.input"
local G = require "lib.state"
local trunks = require "systems.trees"

local function check(ok, what)
  if not ok then engine.quit(); error("TREES TEST FAILED: " .. what, 0) end
  print("  ok  " .. what)
end

local function standing()
  local n = 0
  for k = 1, #R.trees.x do if R.trees.on[k] then n = n + 1 end end
  return n
end

-- A tree on level open ground with nothing else within 40 m to the west of
-- it: a car comes at it from there along +x.
local function target()
  local T = R.trees
  for k = 1, #T.x, 7 do
    local x, z = T.x[k], T.z[k]
    if T.on[k] and not T.street[k] then
      local g0, ok = engine.terrain_height(x, z) or 0, true
      for d = 0, 40, 2 do
        local px = x - d
        local g = engine.terrain_height(px, z)
        if not g or math.abs(g - g0) > 0.8 or R.on_carriageway(px, z, 3) or R.wet(px, z) then ok = false break end
      end
      for j = 1, ok and #T.x or 0 do
        if ok and j ~= k and T.on[j] and T.x[j] > x - 44 and T.x[j] < x + 1 and math.abs(T.z[j] - z) < 4 then ok = false end
      end
      if ok then return k end
    end
  end
end

local t, run = 0, nil
engine.on("contact", function(a, b)
  if run and (a == run.car or b == run.car) then
    local other = a == run.car and b or a
    if engine.tag(other) == "tree" then run.hit = true end
  end
end)

engine.on("tick", function()
  t = t + 1
  if t == 5 then
    local T = R.trees
    local all, on_road, wet = #T.x, 0, 0
    for k = 1, all do
      if R.on_carriageway(T.x[k], T.z[k], 0.5) then on_road = on_road + 1 end
      if R.wet(T.x[k], T.z[k]) then wet = wet + 1 end
    end
    print(string.format("TREES all=%d standing=%d on_road=%d wet=%d", all, standing(), on_road, wet))
    check(all > 80000, string.format("the photo's trees: %d", all))
    check(on_road <= all / 1000, string.format("hardly any within half a metre of a road's asphalt: %d", on_road))
    check(wet == 0, "none in the water")
    local medium = standing()
    settings.set("quality", 1)
    local low = standing()
    settings.set("quality", 3)
    local high = standing()
    settings.set("quality", 2)
    check(low < medium and medium < high and high == all,
          string.format("the quality setting thins them: low %d, medium %d, high %d", low, medium, high))
    check(standing() == medium, "and back again")
    local k = target()
    check(k ~= nil, "a tree on open level ground to drive at")
    local x, z = T.x[k], T.z[k]
    run = {k = k, x = x, z = z, car = vehicle.spawn(x - 35, z, math.pi / 2, 1, nil, "car")}
    -- Driven as the player's car: the trunks come with it (systems/trees).
    if G.player then engine.despawn(G.player) end
    if G.vehicle then engine.despawn(G.vehicle) end
    G.player, G.vehicle = nil, run.car
    engine.emit("vehicle_enter", run.car)
    input.drive = function() return 0.6, 0, false end
    print(string.format("TREES driving at the tree at %.1f, %.1f (crown %d m)", x, z, T.d[k]))
  elseif run and t > 65 then
    if t == 65 + 60 * 10 then
      local cx = engine.pos(run.car)
      check(run.hit, "the car meets its trunk")
      check(cx < run.x - 1, string.format("and stops there, not through it (%.1f m short)", run.x - cx))
      local near = trunks.count()
      trunks.update(run.x + 100000, run.z)
      check(near > 0 and trunks.count() == 0,
            string.format("the %d trunks round the player are taken off again once the player is far away", near))
      print("TREES TEST PASSED")
      engine.quit()
    end
  end
end)
