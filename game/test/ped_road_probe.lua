-- Pedestrians keep to the pavement: round a junction by its corner, not out
-- across the other roads' lanes, and over a road only as a crossing (which
-- waits for cars). Samples everyone walking about four spots of town and
-- sorts whoever is on a carriageway by why. PED_ROAD_TEST=1 (MAP=turku)
local G = require "lib.state"
local U = require "lib.util"
local roadnet = require "lib.roadnet"
local peds = require "systems.peds"
local SPOTS = {{-150, 60}, {300, -200}, {-600, 400}, {900, 300}}
local co = coroutine.create(function()
  local n = {all = 0, crossing = 0, flee = 0, stray = 0}
  for _, s in ipairs(SPOTS) do
    local id = G.vehicle or G.player
    engine.set_pos(id, s[1], U.ground(s[1], s[2]) + 1.5, s[2])
    local t, k = engine.time() + 40, 0
    while engine.time() < t do
      k = k + 1
      if k % 30 == 0 and engine.time() > t - 30 then -- 10 s to settle in
        for pid, p in pairs(peds.peds) do
          local x, _, z = engine.pos(pid)
          n.all = n.all + 1
          if roadnet.on_carriageway(x, z, 0) then
            local why = p.state ~= "walk" and "flee" or p.crossing and "crossing" or "stray"
            n[why] = (n[why] or 0) + 1
          end
        end
      end
      coroutine.yield()
    end
  end
  print(string.format("PED_ROAD: %d looks, on a carriageway %d crossing, %d running from something, %d otherwise (%.1f%%)",
    n.all, n.crossing, n.flee, n.stray, 100 * n.stray / math.max(1, n.all)))
  if n.all < 2000 then error("PED_ROAD: too few pedestrians to tell", 0) end
  -- It was 8% when the way round a junction went through its middle, and
  -- 2-4% while newcomers passed to the right with no line to keep to and
  -- runners went back to the pavement straight down the road (now 0.2-0.5%).
  if n.stray > 0.015 * n.all then error("PED_ROAD: too many out on the road", 0) end
  print("PED_ROAD_OK")
  engine.quit()
end)
engine.on("tick", function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then engine.quit(); error(err, 0) end
end)
