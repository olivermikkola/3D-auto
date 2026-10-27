-- Turku Kauppatori & Ydinkeskusta 500m visual slice.
-- Spawns the modern wooden market pavilions, market stalls, taxi rank,
-- and market square lighting.
local U = require "lib.util"
local vehicle = require "lib.vehicle"
local quality = require "lib.quality"

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

-- The stalls, in the square's own frame (u along its width, v along its
-- depth, metres from its middle): back-to-back pairs of rows at v = ROWS,
-- STALLS a side of a cross aisle about 7 m wide, PITCH apart.
local ROWS = {-26, -13, 0, 13, 26}
local STALLS, PITCH, AISLE = 8, 3.1, 1.5

-- What a stall sells: its awning, and the colours of what's on its table.
local GOODS = {
  {awning = {0.96, 0.45, 0.12}, goods = {{0.8, 0.1, 0.12}, {0.85, 0.15, 0.2}, {0.25, 0.5, 0.2}}},   -- strawberries
  {awning = {0.2, 0.5, 0.3}, goods = {{0.4, 0.65, 0.25}, {0.35, 0.6, 0.2}, {0.55, 0.75, 0.3}}},     -- peas and cucumbers
  {awning = {0.92, 0.92, 0.9}, goods = {{0.6, 0.45, 0.3}, {0.7, 0.55, 0.35}, {0.55, 0.4, 0.28}}},   -- new potatoes
  {awning = {0.75, 0.15, 0.2}, goods = {{0.95, 0.35, 0.55}, {0.95, 0.85, 0.2}, {0.6, 0.3, 0.75}}},  -- flowers
  {awning = {0.15, 0.3, 0.6}, goods = {{0.15, 0.2, 0.55}, {0.25, 0.15, 0.4}, {0.2, 0.25, 0.6}}},    -- blueberries
  {awning = {0.95, 0.8, 0.2}, goods = {{0.85, 0.6, 0.3}, {0.75, 0.5, 0.25}, {0.9, 0.75, 0.45}}},    -- bread and pastries
}

-- market_stall1.. (one per GOODS): the plain stall's table and awning,
-- the awning striped, three crates of goods on the table.
local function stall_meshes()
  for i, g in ipairs(GOODS) do
    local parts = {
      {mesh = "cube", pos = {0, 0.45, 0}, size = {2.4, 0.9, 1.4}, color = {0.62, 0.42, 0.25}},
      {mesh = "cube", pos = {0, 2.05, -0.05}, size = {2.7, 0.08, 1.8}, color = g.awning, pitch = -0.2},
      {mesh = "cube", pos = {0, 1.88, 0.86}, size = {2.7, 0.25, 0.04}, color = {0.95, 0.95, 0.95}},
    }
    for _, x in ipairs{-1.25, 1.25} do
      parts[#parts + 1] = {mesh = "cylinder", pos = {x, 1.2, 0.75}, size = {0.05, 1.5, 0.05}, color = {0.8, 0.8, 0.82}}
      parts[#parts + 1] = {mesh = "cylinder", pos = {x, 1.1, -0.75}, size = {0.05, 2.2, 0.05}, color = {0.8, 0.8, 0.82}}
    end
    for k, col in ipairs(g.goods) do
      parts[#parts + 1] = {mesh = "cube", pos = {(k - 2) * 0.75, 0.97, 0.2}, size = {0.65, 0.14, 0.5}, color = {0.7, 0.55, 0.35}}
      parts[#parts + 1] = {mesh = "cube", pos = {(k - 2) * 0.75, 1.07, 0.2}, size = {0.55, 0.08, 0.42}, color = col}
    end
    engine.mesh("market_stall" .. i, parts)
  end
end

function K.build(map)
  if not map or (map.id ~= "turku" and map.name ~= "Turku") then return end

  local wood_roof = {0.84, 0.66, 0.40}
  local glass_wall = {0.25, 0.38, 0.48}
  local foundation = {0.58, 0.58, 0.60}
  local plaza_granite = {0.56, 0.56, 0.57} -- grey granite (the aerial photo)

  -- 0. Main Kauppatori paved granite plaza (replaces bare grass ground plane).
  -- The square slopes about 2.5 m, so the slab is tilted to the ground's
  -- slope instead of lying flat with the hillside showing through half of it.
  -- Its west edge stops short of Aurakatu's kerb: further out, its corner
  -- stood up out of the carriageway and cars driving up Aurakatu jammed on it.
  local px, pz, pyaw, pw, pd = -172.3, -16.8, 0.602, 128.5, 115.0
  local c, s = math.cos(pyaw), math.sin(pyaw)
  local function at(u, v) return U.ground(px + c * pw * u + s * pd * v, pz - s * pw * u + c * pd * v) end
  local gu = (at(0.5, 0) - at(-0.5, 0)) / pw
  local gv = (at(0, 0.5) - at(0, -0.5)) / pd
  -- The slab's top at u, v metres from its middle.
  local function top(u, v) return at(0, 0) + 0.6 + gu * u + gv * v end
  engine.spawn{
    mesh = "cube",
    pos = {px, at(0, 0) + 0.3, pz},
    yaw = pyaw,
    pitch = -math.atan(gv),
    roll = math.atan(gu),
    size = {pw, 0.6, pd},
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

  -- 2. Torikojut: rows of market stalls in the middle of the square, back
  -- to back in pairs with wide aisles between, a cross aisle down the
  -- middle. Each sells something (the colour of its awning and what's on
  -- its table), and in front of each are places for people to stand.
  stall_meshes()
  K.spots = {taken = {}}
  local stalls = {}
  for _, v0 in ipairs(ROWS) do
    for _, side in ipairs{-1, 1} do
      for k = -STALLS, STALLS do
        if k ~= 0 then
          local u, v = k * PITCH + (k > 0 and AISLE or -AISLE), v0 + side * 0.75
          local sx, sz = px + c * u + s * v, pz - s * u + c * v
          -- The stall faces the aisle on its side (its front is its +z).
          local syaw = side > 0 and pyaw or pyaw + math.pi
          stalls[#stalls + 1] = {sx, sz, syaw, top(u, v)}
        end
      end
    end
  end
  local keep = quality.tier() == 1 and 2 or 1 -- the lowest tier: every other stall
  for i, st in ipairs(stalls) do
    if i % keep == 0 then
      local sx, sz, syaw, sy = st[1], st[2], st[3], st[4]
      K.stalls[#K.stalls + 1] = engine.spawn{mesh = "market_stall" .. math.floor(math.sin(i * 12.9898) * 43758.5453 % 1 * #GOODS + 1), pos = {sx, sy, sz},
                                             yaw = syaw, tag = "prop", body = "static"}
      local fx, fz = math.sin(syaw), math.cos(syaw)
      for _, along in ipairs{-0.7, 0.7} do
        local x, z = sx + fx * 1.6 - fz * along, sz + fz * 1.6 + fx * along
        K.spots[#K.spots + 1] = {x, z, syaw + math.pi, sy}
      end
    end
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
  local roadnet = require "lib.roadnet"
  for _, sc in ipairs(square_corners) do
    local lx, lz = roadnet.off_carriageway(sc[1], sc[2], 0.5) -- on the pavement, not the street
    if lx then
      engine.spawn{
        mesh = "lamp",
        pos = {lx, U.ground(lx, lz), lz},
        tag = "lamp",
      }
    end
  end
end

-- 5. People at the market by day: browsers (systems/peds) going from stall
-- to stall while the player is near enough to see them. They turn up out
-- of sight (40 m off), a few a second; at closing time those out of sight
-- go home.
K.SHOPPERS = {14, 32, 50}
local OPEN, CLOSE = 8, 18
local MIDDLE, NEAR = {-172.3, -16.8}, 150 -- (peds recycles walkers 160 m off)
K.shoppers = {}
local wait = 0
engine.on("tick", function(dt)
  wait = wait - dt
  if wait > 0 or not K.spots then return end
  wait = 1
  -- (A still picture has one frame: everyone at once, wherever, near its
  -- camera rather than the player.)
  local still = os.getenv("SHOT_CAM")
  local x, _, z = U.player_pos()
  if still then x, z = still:match("^([^,]+),[^,]+,([^,]+)") end
  x, z = tonumber(x), tonumber(z)
  if not x then return end
  local peds = require "systems.peds"
  local hour = require("lib.daynight").hour
  local open = hour >= OPEN and hour < CLOSE and U.dist2d(x, z, MIDDLE[1], MIDDLE[2]) < NEAR
  local n = 0
  for id in pairs(K.shoppers) do
    if not peds.peds[id] then
      K.shoppers[id] = nil -- knocked down, run off or recycled
    elseif not open then
      local sx, _, sz = engine.pos(id)
      if U.dist2d(x, z, sx, sz) > 40 then
        peds.peds[id], K.shoppers[id] = nil, nil
        engine.despawn(id)
      end
    else
      n = n + 1
    end
  end
  if not open then return end
  for _ = 1, still and 200 or 3 do
    if n >= quality.pick(K.SHOPPERS) then break end
    local k = peds.rand(#K.spots)
    local sp = K.spots[k]
    if not peds.peds[K.spots.taken[k]] and (still or U.dist2d(x, z, sp[1], sp[2]) > 40) then
      K.shoppers[peds.add_browser(K.spots, k)] = true
      n = n + 1
    end
  end
end)

return K
