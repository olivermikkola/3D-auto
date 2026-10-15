-- Turku Kauppatori & Ydinkeskusta 500m visual slice.
-- Spawns the modern wooden market pavilions, market stalls, taxi rank,
-- and market square lighting.
local U = require "lib.util"
local vehicle = require "lib.vehicle"

local K = {
  pavilions = {},
  stalls = {},
  taxis = {},
}

-- The three iconic Schauman & Nordgren timber Toripaviljongit
local PAVILIONS = {
  {name = "Eerikinkadun paviljonki", pos = {-139.4, 28.2}, size = {62.0, 4.2, 11.2}, yaw = 0.602},
  {name = "Kauppiaskadun paviljonki", pos = {-135.3, -63.2}, size = {38.0, 4.2, 12.0}, yaw = -0.956},
  {name = "Aurakadun paviljonki", pos = {-225.9, -0.9}, size = {38.0, 4.2, 12.0}, yaw = -0.966},
}

function K.build(map)
  if not map or (map.id ~= "turku" and map.name ~= "Turku") then return end

  local wood_roof = {0.84, 0.66, 0.40}
  local glass_wall = {0.25, 0.38, 0.48}
  local foundation = {0.58, 0.58, 0.60}
  local plaza_granite = {0.72, 0.70, 0.68}

  -- 0. Main Kauppatori paved granite plaza (replaces bare grass ground plane)
  engine.spawn{
    mesh = "cube",
    pos = {-175.0, U.ground(-175, -15) + 0.1, -15.0},
    yaw = 0.602,
    size = {135.0, 0.2, 115.0},
    color = plaza_granite,
    tag = "sidewalk",
    body = "static",
  }

  -- 1. Modern Toripaviljongit (glulam timber canopy with glass curtain walls)
  for _, pav in ipairs(PAVILIONS) do
    local px, pz = pav.pos[1], pav.pos[2]
    local py = U.ground(px, pz)
    local pw, ph, pd = pav.size[1], pav.size[2], pav.size[3]

    -- Low concrete foundation terrace
    local base_id = engine.spawn{
      mesh = "cube",
      pos = {px, py + 0.2, pz},
      yaw = pav.yaw,
      size = {pw + 2.0, 0.4, pd + 2.0},
      color = foundation,
      tag = "sidewalk",
      body = "static",
    }

    -- Panoramic glass interior cabin
    engine.spawn{
      mesh = "cube",
      pos = {px, py + ph / 2 + 0.2, pz},
      yaw = pav.yaw,
      size = {pw * 0.92, ph, pd * 0.88},
      color = glass_wall,
      tag = "building",
      body = "static",
    }

    -- Organic curved glulam wood canopy with cantilever overhang
    local roof_id = engine.spawn{
      mesh = "cube",
      pos = {px, py + ph + 0.4, pz},
      yaw = pav.yaw,
      size = {pw + 4.0, 0.8, pd + 4.0},
      color = wood_roof,
      tag = "roof",
      body = "static",
    }

    -- Upper pavilion timber terrace railing
    engine.spawn{
      mesh = "cube",
      pos = {px, py + ph + 1.1, pz},
      yaw = pav.yaw,
      size = {pw + 3.8, 0.6, pd + 3.8},
      color = {0.35, 0.35, 0.38},
      tag = "wall",
      body = "static",
    }

    -- Outdoor patio benches along the pavilion terrace
    local rx, rz = U.right(pav.yaw)
    for _, side in ipairs{-1, 1} do
      local bx = px + rx * side * (pd / 2 + 1.2)
      local bz = pz + rz * side * (pd / 2 + 1.2)
      engine.spawn{
        mesh = "park_bench",
        pos = {bx, U.ground(bx, bz) + 0.1, bz},
        yaw = pav.yaw,
        tag = "prop",
      }
    end

    K.pavilions[#K.pavilions + 1] = roof_id
  end

  -- 2. Torikojut (Market Stalls in the central market square)
  local stall_rows = {
    {-165, -15, 0.6},
    {-175, -20, 0.6},
    {-185, -25, 0.6},
    {-160, 5, 0.6},
    {-170, 0, 0.6},
    {-180, -5, 0.6},
  }
  for _, st in ipairs(stall_rows) do
    local sx, sz, syaw = st[1], st[2], st[3]
    local sy = U.ground(sx, sz)
    local sid = engine.spawn{
      mesh = "market_stall",
      pos = {sx, sy, sz},
      yaw = syaw,
      tag = "prop",
      body = "static",
    }
    K.stalls[#K.stalls + 1] = sid
  end

  -- 3. Kauppatori Taxi Rank (Eerikinkatu)
  local tx, tz = -180.0, 55.0
  local ty = U.ground(tx, tz)
  engine.spawn{
    mesh = "taxi_pole",
    pos = {tx - 2.0, ty, tz},
    yaw = 0.6,
    tag = "prop",
  }

  -- Spawn 2 parked yellow taxis at the rank
  local t1 = vehicle.spawn(tx, tz, 0.6, 3)
  local t2 = vehicle.spawn(tx + 6.0, tz + 4.0, 0.6, 3)
  K.taxis = {t1, t2}

  -- 4. Market Square perimeter street lamps
  local square_corners = {
    {-220, -50}, {-120, -70}, {-110, 40}, {-210, 60}
  }
  for _, sc in ipairs(square_corners) do
    engine.spawn{
      mesh = "lamp",
      pos = {sc[1], U.ground(sc[1], sc[2]), sc[2]},
      tag = "lamp",
    }
  end
end

return K
