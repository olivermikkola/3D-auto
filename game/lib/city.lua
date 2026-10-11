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
    parts = {{mesh = "cube", size = {1, h, 1}, color = {0.35, 0.45, 0.55}}}
    for f = 1, floors - 1 do
      parts[#parts + 1] = {mesh = "cube", pos = {0, -h / 2 + f * 3.5, 0}, size = {1.01, 0.3, 1.01}, color = {0.85, 0.87, 0.9}}
    end
  else
    parts = {{mesh = "cube", size = {1, h, 1}, color = {1, 1, 1}}}
    for f = 0, floors - 1 do
      parts[#parts + 1] = {mesh = "cube", pos = {0, -h / 2 + f * 3.5 + 1.9, 0}, size = {1.01, 1.4, 0.94}, color = {0.25, 0.3, 0.38}}
      parts[#parts + 1] = {mesh = "cube", pos = {0, -h / 2 + f * 3.5 + 1.9, 0}, size = {0.94, 1.4, 1.01}, color = {0.25, 0.3, 0.38}}
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

local function building(x, z, w, d, floors)
  local style = math.random() < 0.25 and "glass" or "brick"
  local h = floors * 3.5
  local c = palette[math.random(#palette)]
  static{mesh = building_mesh(style, floors), pos = {x, CURB + h / 2, z}, size = {w, h, d}, scale = {w, 1, d},
         color = style == "glass" and {1, 1, 1} or c, tag = "building"}
end

local function fill_buildings(cx, cz, ci, cj)
  -- Taller downtown.
  local center = 1 - (math.abs(ci - (N - 1) / 2) + math.abs(cj - (N - 1) / 2)) / N
  local inner = BLOCK - 6
  local split = math.random() < 0.5
  local lots = split and {{-1, -1}, {1, -1}, {-1, 1}, {1, 1}} or {{0, -1}, {0, 1}}
  for _, l in ipairs(lots) do
    local w = split and inner / 2 - 1.5 or inner - 2
    local d = inner / 2 - 1.5
    local floors = math.max(2, math.floor((2 + math.random() * 6) * (0.5 + center * 1.8)))
    building(cx + l[1] * inner / 4 * (split and 1 or 0), cz + l[2] * inner / 4, w, d, floors)
  end
end

local function park(cx, cz)
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
  local L = {N = N, P = P, road = ROAD, block = BLOCK, origin = O, size = N * P + ROAD, kinds = {}}
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
      L.kinds[i .. "," .. j] = kind
      if kind == "buildings" then fill_buildings(cx, cz, i, j)
      elseif kind == "park" then park(cx, cz)
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
