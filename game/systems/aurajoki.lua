-- Aurajoki river waterways, historical bridge decks, riverside restaurant boats,
-- and the iconic autonomous Föri cable ferry.
local U = require "lib.util"
local vehicle = require "lib.vehicle"

local A = {
  bridges = {},
  riverboats = {},
  fori = nil,
}

-- Bridge specifications across the Aurajoki in Turku
local BRIDGES = {
  {name = "Tuomiokirkkosilta", pos = {280, -180}, yaw = -0.75, width = 16, len = 52, height = 3.6, arches = 3},
  {name = "Auransilta", pos = {120, -70}, yaw = -0.72, width = 14, len = 48, height = 3.4, arches = 3},
  {name = "Teatterisilta", pos = {-60, 40}, yaw = -0.70, width = 6, len = 45, height = 3.2, arches = 1, pedestrian = true},
  {name = "Myllysilta", pos = {-280, 180}, yaw = -0.68, width = 18, len = 56, height = 3.8, arches = 3},
  {name = "Martinsilta", pos = {-520, 340}, yaw = -0.65, width = 16, len = 54, height = 3.6, arches = 3},
}

-- Föri terminal endpoints across the Aurajoki
local FORI_ROUTE = {
  bank_east = {-765, 495},  -- Tervatori (Itäinen Rantakatu)
  bank_west = {-835, 545},  -- Wechterinkuja (Läntinen Rantakatu)
  yaw = 0.62,
}

function A.build(map)
  if not map or (map.id ~= "turku" and map.name ~= "Turku") then return end

  -- 1. Aurajoki River Quays & Water surface segments
  local water_color = {0.14, 0.24, 0.28}
  local stone_quay = {0.45, 0.46, 0.48}
  local river_pts = {
    {450, -320}, {280, -180}, {120, -70}, {-60, 40},
    {-280, 180}, {-520, 340}, {-800, 520}, {-1200, 780}, {-1600, 1050}
  }

  for i = 2, #river_pts do
    local p0, p1 = river_pts[i - 1], river_pts[i]
    local mx, mz = (p0[1] + p1[1]) / 2, (p0[2] + p1[2]) / 2
    local yaw = math.atan(p1[1] - p0[1], p1[2] - p0[2])
    local len = U.dist2d(p0[1], p0[2], p1[1], p1[2])

    -- Water surface
    engine.spawn{
      mesh = "cube",
      pos = {mx, -0.2, mz},
      yaw = yaw,
      size = {46, 0.4, len * 1.05},
      color = water_color,
      tag = "water",
      body = "static",
    }

    -- Stone river quays on both banks
    for _, side in ipairs{-1, 1} do
      local rx, rz = U.right(yaw)
      local qx = mx + rx * side * 23.5
      local qz = mz + rz * side * 23.5
      engine.spawn{
        mesh = "cube",
        pos = {qx, 0.4, qz},
        yaw = yaw,
        size = {1.8, 1.6, len * 1.02},
        color = stone_quay,
        tag = "sidewalk",
        body = "static",
      }
    end
  end

  -- 2. Build Physical Bridges
  local concrete = {0.68, 0.68, 0.72}
  local railing = {0.2, 0.22, 0.25}
  for _, b in ipairs(BRIDGES) do
    local bx, bz = b.pos[1], b.pos[2]
    local by = b.height or 3.5
    local byaw = b.yaw or 0
    local rx, rz = U.right(byaw)

    -- Solid bridge deck for vehicle & pedestrian traffic
    engine.spawn{
      mesh = "cube",
      pos = {bx, by, bz},
      yaw = byaw,
      size = {b.width, 0.5, b.len},
      color = concrete,
      tag = "bridge",
      body = "static",
    }

    -- Bridge parapet / cast-iron railings on both edges
    for _, side in ipairs{-1, 1} do
      engine.spawn{
        mesh = "cube",
        pos = {bx + rx * side * (b.width / 2 - 0.2), by + 0.6, bz + rz * side * (b.width / 2 - 0.2)},
        yaw = byaw,
        size = {0.2, 0.9, b.len},
        color = railing,
        tag = "wall",
        body = "static",
      }
    end

    -- Bridge piers / arches in water
    for p_offset = -b.len / 3, b.len / 3, b.len / 3 do
      engine.spawn{
        mesh = "cube",
        pos = {bx, by / 2, bz + p_offset},
        yaw = byaw,
        size = {b.width * 0.9, by, 3.2},
        color = stone_quay,
        tag = "wall",
        body = "static",
      }
    end
    A.bridges[#A.bridges + 1] = b
  end

  -- 3. Riverside Restaurant / Bar Boats moored along Aurajoki quays
  local boat_moorings = {
    {pos = {70, -25}, yaw = -0.72, name = "Donna"},
    {pos = {-150, 95}, yaw = -0.70, name = "Papa Joe"},
    {pos = {-410, 255}, yaw = -0.66, name = "Svarte Rudolf"},
  }
  for _, m in ipairs(boat_moorings) do
    local bid = engine.spawn{
      mesh = "riverboat",
      pos = {m.pos[1], 0.1, m.pos[2]},
      yaw = m.yaw,
      tag = "prop",
      body = "static",
    }
    A.riverboats[#A.riverboats + 1] = bid
  end

  -- 4. Spawn The Föri (City Cable Ferry)
  local f_start = FORI_ROUTE.bank_east
  local fori_id = engine.spawn{
    mesh = "fori",
    pos = {f_start[1], 0.25, f_start[2]},
    yaw = FORI_ROUTE.yaw,
    size = {10.5, 1.2, 9.2},
    tag = "ferry",
    body = "kinematic",
  }
  A.fori = {
    id = fori_id,
    target = 1, -- 0 for bank_east, 1 for bank_west
    progress = 0.0,
    pause = 5.0, -- pause at wharf for boarding
  }
end

-- Update Föri ferry position across Aurajoki
function A.tick(dt)
  if not A.fori then return end
  local f = A.fori
  if f.pause > 0 then
    f.pause = f.pause - dt
    return
  end

  local speed = 0.08 * dt -- crossing takes ~12.5 seconds
  if f.target == 1 then
    f.progress = math.min(1.0, f.progress + speed)
    if f.progress >= 1.0 then
      f.target = 0
      f.pause = 6.0 -- boarding pause on west bank
    end
  else
    f.progress = math.max(0.0, f.progress - speed)
    if f.progress <= 0.0 then
      f.target = 1
      f.pause = 6.0 -- boarding pause on east bank
    end
  end

  local p0, p1 = FORI_ROUTE.bank_east, FORI_ROUTE.bank_west
  local cur_x = p0[1] + (p1[1] - p0[1]) * f.progress
  local cur_z = p0[2] + (p1[2] - p0[2]) * f.progress
  if engine.exists(f.id) then
    engine.set_pos(f.id, cur_x, 0.25, cur_z)
  end
end

engine.on("tick", function(dt)
  A.tick(dt or (1/60))
end)

return A
