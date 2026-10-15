-- Can you drive straight over a level crossing? For every place a track
-- crosses a road: rays down each lane, 30 m either side of the track, at
-- wheel (0.25 m) and bumper (0.7 m) height above the asphalt, must hit
-- nothing; a ray straight down must land on the road itself, not on
-- something lying on it. Prints RAIL_CROSSINGS=<n> and RAIL_CROSSING_OK,
-- or each blocked crossing and RAIL_CROSSING_FAILED. RAIL_CROSSING_LIST=1
-- lists them all.
local roadnet = require "lib.roadnet"

local MOVING = {car = true, ped = true, player = true, bus = true, cop = true, pickup = true}

engine.on("init", function()
  local NET = roadnet.net()
  local list, bad = NET and NET.level_crossings or {}, 0
  for k, c in ipairs(list) do
    local x, z, ei = c[1], c[2], c[3]
    local e = NET.edges[ei]
    local h = e.height or roadnet.ground
    -- The road's direction at the crossing.
    local best, dx, dz = math.huge, 1, 0
    for i = 2, #e.pts do
      local a, b = e.pts[i - 1], e.pts[i]
      local mx, mz = (a[1] + b[1]) / 2, (a[2] + b[2]) / 2
      local d = (mx - x) ^ 2 + (mz - z) ^ 2
      local l = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
      if d < best and l > 0.5 then best, dx, dz = d, (b[1] - a[1]) / l, (b[2] - a[2]) / l end
    end
    local why
    for _, side in ipairs{-0.25, 0.25} do
      local ox, oz = -dz * side * e.width, dx * side * e.width
      for _, up in ipairs{0.25, 0.7} do
        -- In 5 m steps, so the ray follows the road's grade.
        for s = -30, 25, 5 do
          local x0, z0 = x + ox + dx * s, z + oz + dz * s
          local x1, z1 = x0 + dx * 5, z0 + dz * 5
          local y0, y1 = h(x0, z0) + 0.08 + up, h(x1, z1) + 0.08 + up
          local id = engine.raycast(x0, y0, z0, x1 - x0, y1 - y0, z1 - z0, math.sqrt(25 + (y1 - y0) ^ 2))
          if id and not MOVING[engine.tag(id)] then
            why = why or string.format("%s at %.1f m height, %d m along", engine.tag(id), up, s)
          end
        end
      end
    end
    local id, dist = engine.raycast(x, h(x, z) + 3, z, 0, -1, 0, 4)
    if id and dist < 2.8 and not MOVING[engine.tag(id)] then
      why = why or string.format("%s %.2f m above the asphalt", engine.tag(id), 2.92 - dist)
    end
    if os.getenv("RAIL_CROSSING_LIST") then
      print(string.format("crossing %d at (%.0f, %.0f) on %s, road heading (%.2f, %.2f)", k, x, z, e.name or ei, dx, dz))
    end
    if why then
      bad = bad + 1
      print(string.format("level crossing %d at (%.0f, %.0f) on %s: %s", k, x, z, e.name or ei, why))
    end
  end
  print("RAIL_CROSSINGS=" .. #list)
  print(bad == 0 and "RAIL_CROSSING_OK" or "RAIL_CROSSING_FAILED " .. bad)
  engine.quit()
end)
