-- Procedural city: a grid of blocks separated by roads. Returns the layout
-- so other systems (traffic, missions, minimap) can reason about streets.
local C = {}

local N, BLOCK, ROAD = 8, 36, 14
local P = BLOCK + ROAD        -- block pitch
local O = -N * P / 2          -- coordinate of road line 0
local CURB = 0.2

local palette = {
  {0.85, 0.82, 0.76}, {0.72, 0.68, 0.62}, {0.70, 0.45, 0.35}, {0.62, 0.66, 0.70},
  {0.90, 0.88, 0.80}, {0.55, 0.52, 0.50}, {0.78, 0.60, 0.45}, {0.68, 0.74, 0.78},
}

-- One baked mesh per (style, floors). Footprint is 1x1 (scaled per building),
-- height is real so window bands keep a sane spacing.
local baked = {}
local function building_mesh(style, floors)
  local name = style .. floors
  if baked[name] then return name end
  local h = floors * 3.5
  local parts
  if style == "glass" then
    parts = {{mesh = "cube", size = {1, h, 1}, color = {0.35, 0.45, 0.55}, emissive = 0.08}}
    for f = 1, floors - 1 do
      parts[#parts + 1] = {mesh = "cube", pos = {0, -h / 2 + f * 3.5, 0}, size = {1.01, 0.3, 1.01}, color = {0.85, 0.87, 0.9}}
    end
  else
    parts = {{mesh = "cube", size = {1, h, 1}, color = {1, 1, 1}}}
    for f = 0, floors - 1 do
      -- About a third of the floors have their lights on at night.
      local lit = (f * 7 + floors * 3) % 3 == 0
      local glass = lit and {0.34, 0.31, 0.25} or {0.25, 0.3, 0.38}
      parts[#parts + 1] = {mesh = "cube", pos = {0, -h / 2 + f * 3.5 + 1.9, 0}, size = {1.01, 1.4, 0.94}, color = glass, emissive = lit and 1 or 0}
      parts[#parts + 1] = {mesh = "cube", pos = {0, -h / 2 + f * 3.5 + 1.9, 0}, size = {0.94, 1.4, 1.01}, color = glass, emissive = lit and 1 or 0}
    end
  end
  parts[#parts + 1] = {mesh = "cube", pos = {0, h / 2 + 0.3, 0}, size = {1.02, 0.6, 1.02}, color = {0.6, 0.6, 0.6}}
  parts[#parts + 1] = {mesh = "cube", pos = {0.2, h / 2 + 1.0, -0.15}, size = {0.25, 1.0, 0.2}, color = {0.7, 0.7, 0.7}}
  engine.mesh(name, parts)
  baked[name] = true
  return name
end

local function static(t)
  t.body = t.body or "static"
  return engine.spawn(t)
end

local function building(x, z, w, d, floors, glass, c)
  local style = glass and "glass" or "brick"
  local h = floors * 3.5
  static{mesh = building_mesh(style, floors), pos = {x, CURB + h / 2, z}, size = {w, h, d}, scale = {w, 1, d},
         color = glass and {1, 1, 1} or c, tag = "building"}
end

-- Cheap deterministic noise for details, so they never touch math.random
-- (and so never move anything that was already placed by it).
local function hash(a, b, k)
  return ((a * 73856093) ~ (b * 19349663) ~ (k * 83492791)) % 1000 / 1000
end

-- ---- industrial: warehouses with sawtooth roofs, containers, smokestacks ----
local METAL = {{0.55, 0.6, 0.65}, {0.62, 0.42, 0.32}, {0.75, 0.72, 0.62}, {0.4, 0.5, 0.45}}
local CONTAINER = {{0.75, 0.2, 0.15}, {0.15, 0.35, 0.65}, {0.2, 0.55, 0.3}, {0.85, 0.6, 0.15}, {0.5, 0.5, 0.52}}

local function warehouse_mesh(v, h)
  local name = "warehouse" .. v .. "_" .. h
  if baked[name] then return name end
  local c = METAL[v]
  local parts = {{mesh = "cube", size = {1, h, 1}, color = c}}
  -- Ribs of the cladding, a roller door and a strip of high windows.
  for k = -2, 2 do
    parts[#parts + 1] = {mesh = "cube", pos = {k * 0.2, 0, 0}, size = {0.02, h, 1.01}, color = {c[1] * 0.8, c[2] * 0.8, c[3] * 0.8}}
  end
  parts[#parts + 1] = {mesh = "cube", pos = {0, -h / 2 + 2.2, 0}, size = {0.35, 4.4, 1.02}, color = {0.3, 0.3, 0.32}}
  parts[#parts + 1] = {mesh = "cube", pos = {0, h / 2 - 1.2, 0}, size = {1.01, 0.8, 0.9}, color = {0.3, 0.33, 0.3}, emissive = v % 2}
  -- Sawtooth roof: wedges whose steep (glazed) faces all look the same way.
  for k = 0, 3 do
    parts[#parts + 1] = {mesh = "wedge", pos = {0, h / 2 + 0.8, -0.375 + k * 0.25}, size = {1, 1.6, 0.25}, color = {0.45, 0.45, 0.47}}
  end
  engine.mesh(name, parts)
  baked[name] = true
  return name
end

local function warehouse(x, z, w, d, floors, glass, ci, cj, k)
  local h = 6 + (floors % 3) * 2
  local v = 1 + (floors + ci + cj) % #METAL
  -- The shed takes most of the lot; containers fill the yard beside it.
  local ww = w * 0.72
  static{mesh = warehouse_mesh(v, h), pos = {x - (w - ww) / 2, CURB + h / 2, z}, size = {ww, h, d}, scale = {ww, 1, d},
         tag = "building"}
  local yx = x + w / 2 - (w - ww) / 2
  local slots = math.floor(d / 3.2)
  local stack_slot = glass and k == 1 and slots - 1 -- one lot in some blocks gets a smokestack
  -- The yard's containers are baked into one mesh with one collider over the row.
  local cw = math.min(w - ww - 0.6, 6)
  local parts, z0, z1, top = {}, nil, nil, 0
  for n = 0, slots - 1 do
    local sz = z - d / 2 + 1.6 + n * 3.2
    if n == stack_slot then
      static{mesh = "smokestack", pos = {yx, CURB + 14, sz}, size = {2.2, 28, 2.2}, scale = 1, tag = "building"}
    elseif hash(ci, cj, k * 16 + n) < 0.75 then
      local stack = hash(cj, ci, k * 16 + n) < 0.35 and 2 or 1
      for st = 1, stack do
        local cc = CONTAINER[1 + math.floor(hash(ci + st, cj, k * 16 + n) * #CONTAINER)]
        parts[#parts + 1] = {mesh = "cube", pos = {0, 1.3 + (st - 1) * 2.6, sz - z}, size = {cw, 2.6, 2.6}, color = cc}
        parts[#parts + 1] = {mesh = "cube", pos = {0, 1.3 + (st - 1) * 2.6, sz - z}, size = {cw + 0.02, 0.15, 2.62},
                             color = {cc[1] * 0.7, cc[2] * 0.7, cc[3] * 0.7}}
      end
      z0, z1, top = math.min(z0 or sz, sz), math.max(z1 or sz, sz), math.max(top, stack * 2.6)
    end
  end
  if #parts > 0 then
    -- Parts sit relative to the row's middle, which is where the collider goes.
    local mid = (z0 + z1) / 2
    for _, pt in ipairs(parts) do pt.pos[2], pt.pos[3] = pt.pos[2] - top / 2, pt.pos[3] - (mid - z) end
    local name = string.format("containers_%d_%d_%d", ci, cj, k)
    engine.mesh(name, parts)
    static{mesh = name, pos = {yx, CURB + top / 2, mid}, size = {cw, top, z1 - z0 + 2.6}, scale = 1, tag = "container"}
  end
end

-- ---- residential: houses with pitched roofs, yards and trees ------------------
local ROOF = {{0.55, 0.22, 0.18}, {0.3, 0.3, 0.33}, {0.45, 0.32, 0.22}}

local function house_mesh(stories, wall, roof)
  local name = string.format("house%d_%d_%d", stories, wall, roof)
  if baked[name] then return name end
  local h, rh = stories * 3, 2.4
  local rc = ROOF[roof]
  local parts = {{mesh = "cube", size = {1, h, 1}, color = palette[wall]}}
  for f = 0, stories - 1 do
    local lit = (f + wall + roof) % 2 == 0
    local glass = lit and {0.34, 0.31, 0.25} or {0.25, 0.3, 0.38}
    parts[#parts + 1] = {mesh = "cube", pos = {0, -h / 2 + f * 3 + 1.7, 0}, size = {0.7, 1.1, 1.02}, color = glass, emissive = lit and 1 or 0}
  end
  parts[#parts + 1] = {mesh = "cube", pos = {0.3, -h / 2 + 1.1, 0}, size = {0.14, 2.2, 1.03}, color = {0.4, 0.26, 0.16}} -- doors
  -- Gable roof: two wedges back to back, with eaves.
  parts[#parts + 1] = {mesh = "wedge", pos = {0, h / 2 + rh / 2, -0.27}, size = {1.08, rh, 0.56}, color = rc}
  parts[#parts + 1] = {mesh = "wedge", pos = {0, h / 2 + rh / 2, 0.27}, size = {1.08, rh, 0.56}, yaw = math.pi, color = rc}
  parts[#parts + 1] = {mesh = "cube", pos = {0.3, h / 2 + rh * 0.7, 0.15}, size = {0.08, rh * 0.8, 0.08}, color = {0.5, 0.3, 0.25}}
  engine.mesh(name, parts)
  baked[name] = true
  return name
end

local function houses(x, z, w, d, floors, glass, ci, cj, k)
  engine.spawn{mesh = "cube", pos = {x, CURB + 0.02, z}, size = {w + 1, 0.04, d + 1}, color = {0.35, 0.55, 0.28}, tag = "yard"}
  -- Wide lots get a pair of houses; each sits back from the street with a tree out front.
  local n = w > 18 and 2 or 1
  for m = 1, n do
    local hx = x + (m - (n + 1) / 2) * (w / n)
    local stories = 1 + floors % 2
    local hw, hd = math.min(9, w / n - 3), 7
    local wall = 1 + math.floor(hash(ci, cj, k * 4 + m) * #palette)
    local roof = 1 + (glass and 1 or 0) + (k + m) % 2
    static{mesh = house_mesh(stories, wall, roof), pos = {hx, CURB + stories * 1.5, z}, size = {hw, stories * 3, hd},
           scale = {hw, 1, hd}, tag = "building"}
    local side = hash(cj, ci, k * 4 + m) < 0.5 and -1 or 1
    static{mesh = "tree", pos = {hx + side * (hw / 2 + 1.5), CURB, z + side * (d / 2 - 1.5)}, size = {0.5, 6, 0.5},
           scale = 0.7 + hash(ci, cj, k + m) * 0.4, tag = "tree"}
  end
end

-- Districts: industry along the east edge, houses along the south, downtown
-- everywhere else. Every lot makes the same math.random draws in the same
-- order whatever it becomes, so street-level layout never shifts.
function C.district(i, j)
  if i >= N - 2 then return "industrial" end
  if j >= N - 2 then return "residential" end
  return "downtown"
end

-- dry: make the random draws but build nothing (a landmark takes the block).
local function fill_buildings(cx, cz, ci, cj, dry)
  -- Taller downtown.
  local center = 1 - (math.abs(ci - (N - 1) / 2) + math.abs(cj - (N - 1) / 2)) / N
  local inner = BLOCK - 6
  local split = math.random() < 0.5
  local lots = split and {{-1, -1}, {1, -1}, {-1, 1}, {1, 1}} or {{0, -1}, {0, 1}}
  local district = C.district(ci, cj)
  for k, l in ipairs(lots) do
    local w = split and inner / 2 - 1.5 or inner - 2
    local d = inner / 2 - 1.5
    local floors = math.max(2, math.floor((2 + math.random() * 6) * (0.5 + center * 1.8)))
    local glass = math.random() < 0.25
    local c = palette[math.random(#palette)]
    local x, z = cx + l[1] * inner / 4 * (split and 1 or 0), cz + l[2] * inner / 4
    if dry then -- nothing
    elseif district == "industrial" then warehouse(x, z, w, d, floors, glass, ci, cj, k)
    elseif district == "residential" then houses(x, z, w, d, floors, glass, ci, cj, k)
    else building(x, z, w, d, floors, glass, c) end
  end
end

local function park(cx, cz, dry)
  if dry then
    for _ = 1, 9 do math.random(); math.random(); math.random() end
    return
  end
  engine.spawn{mesh = "cube", pos = {cx, CURB + 0.01, cz}, size = {BLOCK - 5, 0.04, BLOCK - 5}, color = {0.3, 0.55, 0.25}}
  for _ = 1, 9 do
    local x, z = cx + (math.random() - 0.5) * (BLOCK - 8), cz + (math.random() - 0.5) * (BLOCK - 8)
    static{mesh = "tree", pos = {x, CURB, z}, size = {0.5, 6, 0.5}, scale = 0.8 + math.random() * 0.5, tag = "tree"}
  end
end

-- A ramp is just a tilted static box, buried at the low end so cars roll on.
-- yaw is the direction it launches you; pitch is the incline in radians.
function C.ramp(x, z, yaw, width, length, incline)
  local t = 0.6
  local y = CURB - 0.03 + length / 2 * math.sin(incline) - t / 2 * math.cos(incline)
  local name = string.format("ramp_%g_%g", width, length)
  local parts = {{mesh = "cube", size = {width, t, length}, color = {0.95, 0.55, 0.1}}}
  for k = 1, math.floor(length / 2.5) do
    parts[#parts + 1] = {mesh = "cube", pos = {0, 0.01, -length / 2 + k * 2.5 - 0.6}, size = {width + 0.02, t, 0.6}, color = {0.15, 0.15, 0.15}}
  end
  engine.mesh(name, parts)
  return engine.spawn{mesh = name, pos = {x, y, z}, yaw = yaw, pitch = -incline, size = {width, t, length}, scale = 1,
                      body = "static", tag = "ramp"}
end

function C.stunt_park(cx, cz)
  engine.spawn{mesh = "cube", pos = {cx, CURB + 0.01, cz}, size = {BLOCK - 4, 0.04, BLOCK - 4}, color = {0.36, 0.36, 0.38}}
  C.ramp(cx, cz - 4, 0, 7, 16, 0.3)              -- big kicker, launches north
  C.ramp(cx - 11, cz + 8, math.pi, 4, 8, 0.38)    -- small ones on the sides
  C.ramp(cx + 11, cz + 8, math.pi, 4, 8, 0.38)
end

function C.node(k, l) return O + k * P, O + l * P end
function C.block_center(i, j) return O + (i + 0.5) * P, O + (j + 0.5) * P end

function C.build()
  local L = {N = N, P = P, road = ROAD, block = BLOCK, origin = O, size = N * P + ROAD, kinds = {}, curb = CURB}
  local W = N * P + ROAD + 200

  -- Ground and invisible boundary walls.
  static{mesh = "cube", pos = {0, -0.5, 0}, size = {W, 1, W}, color = {0.22, 0.22, 0.24}, tag = "ground"}
  local edge = N * P / 2 + ROAD / 2
  for _, s in ipairs{{1, 0}, {-1, 0}, {0, 1}, {0, -1}} do
    static{pos = {s[1] * edge, 5, s[2] * edge}, size = {s[1] == 0 and 2 * edge or 1, 10, s[2] == 0 and 2 * edge or 1}, visible = false, tag = "wall"}
  end

  -- Dashed yellow center lines along every street segment.
  for k = 0, N do
    for l = 0, N - 1 do
      for dash = 0, 5 do
        local t = (dash + 0.5) / 6
        local a = O + (l + 0.15 + 0.7 * t) * P
        local x = O + k * P
        engine.spawn{mesh = "plane", pos = {x, 0.02, a}, size = {0.25, 1, 3}, color = {0.9, 0.75, 0.2}}
        engine.spawn{mesh = "plane", pos = {a, 0.02, x}, size = {3, 1, 0.25}, color = {0.9, 0.75, 0.2}}
      end
    end
  end

  L.plaza = {3, 4}
  L.lot = {4, 3}
  L.stunt = {5, 4}
  L.tower = {4, 4}
  L.carpark = {2, 4}
  L.landmarks = {}
  engine.mesh("smokestack", {
    {mesh = "cylinder", size = {2.2, 28, 2.2}, color = {0.6, 0.55, 0.5}},
    {mesh = "cylinder", pos = {0, 11, 0}, size = {2.25, 2, 2.25}, color = {0.8, 0.15, 0.1}},
    {mesh = "cylinder", pos = {0, 6, 0}, size = {2.25, 2, 2.25}, color = {0.9, 0.9, 0.88}},
    {mesh = "cylinder", pos = {0, 13.6, 0}, size = {1.6, 0.8, 1.6}, color = {0.2, 0.2, 0.2}},
  })
  for i = 0, N - 1 do
    for j = 0, N - 1 do
      local cx, cz = C.block_center(i, j)
      static{mesh = "cube", pos = {cx, CURB / 2, cz}, size = {BLOCK, CURB, BLOCK}, color = {0.62, 0.62, 0.6}, tag = "sidewalk"}
      local kind
      if i == L.plaza[1] and j == L.plaza[2] then kind = "plaza"
      elseif i == L.lot[1] and j == L.lot[2] then kind = "lot"
      elseif i == L.stunt[1] and j == L.stunt[2] then kind = "stunt"
      elseif math.random() < 0.12 then kind = "park"
      else kind = "buildings" end
      -- A landmark takes its block whatever the dice said, after rolling them the same way.
      local landmark = (i == L.tower[1] and j == L.tower[2] and "tower") or (i == L.carpark[1] and j == L.carpark[2] and "carpark")
      if landmark then
        if kind == "buildings" then fill_buildings(cx, cz, i, j, true) elseif kind == "park" then park(cx, cz, true) end
        kind = landmark
      end
      L.kinds[i .. "," .. j] = kind
      if kind == "buildings" then fill_buildings(cx, cz, i, j)
      elseif kind == "park" then park(cx, cz)
      elseif kind == "tower" then L.landmarks[#L.landmarks + 1] = require("lib.landmarks").tower(cx, cz)
      elseif kind == "carpark" then L.landmarks[#L.landmarks + 1] = require("lib.landmarks").carpark(cx, cz)
      elseif kind == "plaza" then
        engine.spawn{mesh = "cube", pos = {cx, CURB + 0.01, cz}, size = {BLOCK - 4, 0.04, BLOCK - 4}, color = {0.75, 0.68, 0.55}}
      elseif kind == "stunt" then C.stunt_park(cx, cz)
      elseif kind == "lot" then
        engine.spawn{mesh = "cube", pos = {cx, CURB + 0.01, cz}, size = {BLOCK - 4, 0.04, BLOCK - 4}, color = {0.3, 0.3, 0.32}}
        for s = -3, 3 do
          engine.spawn{mesh = "plane", pos = {cx + s * 4 + 2, CURB + 0.04, cz}, size = {0.15, 1, 6}, color = {0.9, 0.9, 0.9}}
        end
      end
      -- Street lamps on the corners.
      for _, c in ipairs{{1, 1}, {-1, 1}, {1, -1}, {-1, -1}} do
        static{mesh = "lamp", pos = {cx + c[1] * (BLOCK / 2 - 1), CURB, cz + c[2] * (BLOCK / 2 - 1)},
               yaw = math.atan(c[1], c[2]), size = {0.3, 10, 0.3}, tag = "lamp"}
      end
    end
  end
  return L
end

return C
