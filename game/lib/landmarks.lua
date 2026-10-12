-- One-off places the procedural blocks can't make: a TV tower and an Art
-- Deco skyscraper you can steer by from anywhere in the city, and a
-- multi-storey car park you can drive to the top of (and off the top of). lib/city calls these for their
-- blocks; each returns {name, letter, x, z} for the minimap.
local M = {}
local CURB = 0.2

local function static(t)
  t.body = "static"
  return engine.spawn(t)
end

-- ---- TV tower --------------------------------------------------------------------
function M.tower(cx, cz)
  local H = 80
  engine.mesh("tv_tower", {
    {mesh = "cylinder", size = {3.6, H, 3.6}, color = {0.82, 0.82, 0.8}},
    {mesh = "cylinder", pos = {0, -H / 2 + 2, 0}, size = {9, 4, 9}, color = {0.6, 0.6, 0.62}},
    {mesh = "cylinder", pos = {0, 20, 0}, size = {13, 5, 13}, color = {0.75, 0.75, 0.78}},
    {mesh = "cylinder", pos = {0, 20, 0}, size = {13.3, 1.6, 13.3}, color = {0.95, 0.8, 0.45}, emissive = 1},
    {mesh = "cylinder", pos = {0, 24, 0}, size = {9, 1.2, 9}, color = {0.85, 0.2, 0.15}},
    {mesh = "cylinder", pos = {0, H / 2 + 9, 0}, size = {0.6, 18, 0.6}, color = {0.85, 0.2, 0.15}},
    {mesh = "sphere", pos = {0, H / 2 + 18.5, 0}, size = 1.2, color = {1, 0.15, 0.1}, emissive = 1},
  })
  engine.spawn{mesh = "cube", pos = {cx, CURB + 0.01, cz}, size = {32, 0.04, 32}, color = {0.7, 0.68, 0.64}}
  static{mesh = "tv_tower", pos = {cx, CURB + H / 2, cz}, size = {3.6, H, 3.6}, scale = 1, tag = "landmark"}
  -- Low walls round the base, and floodlights on it after dark.
  static{mesh = "cylinder", pos = {cx, CURB + 0.5, cz}, size = {12, 1, 12}, color = {0.55, 0.55, 0.57}}
  for _, c in ipairs{{1, 1}, {-1, 1}, {1, -1}, {-1, -1}} do
    engine.light{pos = {cx + c[1] * 7, CURB + 1, cz + c[2] * 7}, dir = {-c[1] * 0.3, 1, -c[2] * 0.3}, cone = 25,
                 radius = 70, intensity = 1.5, color = {0.9, 0.9, 1}}
  end
  engine.light{pos = {cx, CURB + H + 18.5, cz}, color = {1, 0.15, 0.1}, radius = 25, intensity = 3}
  return {name = "TV TOWER", letter = "T", x = cx, z = cz}
end

-- ---- the Empire: the tallest thing in Midtown -------------------------------------
-- Limestone setbacks stepping up to a lit crown and a mooring mast. Each tier
-- is its own collider; the mesh hangs off the base.
local EMPIRE = {{40, 30, 6}, {34, 25, 20}, {26, 19, 18}, {17, 13, 6}, {11, 9, 3}} -- width, depth, floors
M.EMPIRE_FLOOR = 3.5

function M.empire(cx, cz)
  local F = M.EMPIRE_FLOOR
  local stone, glass = {0.8, 0.76, 0.66}, {0.3, 0.33, 0.38}
  local base = EMPIRE[1][3] * F
  local parts, y0 = {}, -base / 2
  for t, tier in ipairs(EMPIRE) do
    local w, d, h = tier[1], tier[2], tier[3] * F
    parts[#parts + 1] = {mesh = "cube", pos = {0, y0 + h / 2, 0}, size = {w, h, d}, color = stone}
    -- Vertical strips of windows, the way the real thing reads from the street.
    for k = 1, math.floor(w / 3) - 1 do
      parts[#parts + 1] = {mesh = "cube", pos = {-w / 2 + k * 3, y0 + h / 2, 0}, size = {1.1, h - 1, d + 0.06}, color = glass,
                           emissive = (k + t) % 3 == 0 and 0.7 or 0}
    end
    for k = 1, math.floor(d / 3) - 1 do
      parts[#parts + 1] = {mesh = "cube", pos = {0, y0 + h / 2, -d / 2 + k * 3}, size = {w + 0.06, h - 1, 1.1}, color = glass,
                           emissive = (k + t) % 4 == 0 and 0.7 or 0}
    end
    parts[#parts + 1] = {mesh = "cube", pos = {0, y0 + h + 0.3, 0}, size = {w + 0.4, 0.6, d + 0.4}, color = {0.66, 0.62, 0.54}}
    y0 = y0 + h
  end
  -- The crown, floodlit at night, and the mast.
  parts[#parts + 1] = {mesh = "cube", pos = {0, y0 + 3, 0}, size = {7, 6, 6}, color = {1, 0.85, 0.5}, emissive = 1}
  parts[#parts + 1] = {mesh = "cylinder", pos = {0, y0 + 9, 0}, size = {3, 6, 3}, color = {0.85, 0.85, 0.88}}
  parts[#parts + 1] = {mesh = "cylinder", pos = {0, y0 + 22, 0}, size = {0.6, 20, 0.6}, color = {0.8, 0.8, 0.82}}
  parts[#parts + 1] = {mesh = "sphere", pos = {0, y0 + 32.5, 0}, size = 1, color = {1, 0.15, 0.1}, emissive = 1}
  engine.mesh("empire", parts)
  engine.spawn{mesh = "cube", pos = {cx, CURB + 0.01, cz}, size = {44, 0.04, 34}, color = {0.7, 0.68, 0.64}}
  static{mesh = "empire", pos = {cx, CURB + base / 2, cz}, size = {EMPIRE[1][1], base, EMPIRE[1][2]}, scale = 1, tag = "landmark"}
  local y = CURB + base
  for t = 2, #EMPIRE do
    local w, d, h = EMPIRE[t][1], EMPIRE[t][2], EMPIRE[t][3] * F
    static{pos = {cx, y + h / 2, cz}, size = {w, h, d}, visible = false, tag = "landmark"}
    y = y + h
  end
  engine.light{pos = {cx, y + 4, cz}, color = {1, 0.8, 0.45}, radius = 30, intensity = 2.5}
  engine.light{pos = {cx, y + 32.5, cz}, color = {1, 0.15, 0.1}, radius = 20, intensity = 3}
  return {name = "EMPIRE", letter = "E", x = cx, z = cz, top = y}
end

-- ---- multi-storey car park --------------------------------------------------------
-- Three decks over a ground floor, stacked ramps up the east and west sides:
--   ground -> east ramp (heading north) -> deck 1, cross west ->
--   west ramp (heading south) -> deck 2, cross east -> east ramp -> roof.
-- The ramps on the east side are a full deck height apart, so cars clear.
M.DECK = 4.5
local CORE, STRIP_IN, STRIP_OUT, ZEND = 9, 9, 15, 14

-- A sloped slab whose top runs from (z0, y0) to (z1, y1) along x = x.
local function slope(x, z0, y0, z1, y1, width, t, color)
  local len, rise = math.abs(z1 - z0), y1 - y0
  local a = math.atan(rise, len)
  local l = math.sqrt(len * len + rise * rise)
  static{mesh = "cube", pos = {x, (y0 + y1) / 2 - t / 2 * math.cos(a), (z0 + z1) / 2}, size = {width, t, l},
         yaw = z1 > z0 and 0 or math.pi, pitch = -a, color = color, tag = "carpark"}
end

-- A flat slab whose top is at height y.
local function deck(x0, x1, z0, z1, y, color)
  static{mesh = "cube", pos = {(x0 + x1) / 2, y - 0.25, (z0 + z1) / 2}, size = {x1 - x0, 0.5, z1 - z0}, color = color,
         tag = "carpark"}
end

function M.carpark(cx, cz)
  local D, T = M.DECK, 0.5
  local concrete, ramp_c, stripe = {0.68, 0.67, 0.64}, {0.58, 0.57, 0.55}, {0.95, 0.85, 0.2}
  local y1, y2, y3 = CURB + D, CURB + 2 * D, CURB + 3 * D
  local E, W = cx + (STRIP_IN + STRIP_OUT) / 2, cx - (STRIP_IN + STRIP_OUT) / 2
  local SW = STRIP_OUT - STRIP_IN
  engine.spawn{mesh = "cube", pos = {cx, CURB + 0.01, cz}, size = {32, 0.04, 32}, color = {0.36, 0.36, 0.38}}

  -- Decks across the middle, with landings in the ramp strips where ramps arrive and leave.
  for _, y in ipairs{y1, y2, y3} do deck(cx - CORE, cx + CORE, cz - ZEND, cz + ZEND, y, concrete) end
  deck(cx + STRIP_IN, cx + STRIP_OUT, cz - ZEND, cz - 10, y1, concrete) -- deck 1: east ramp arrives
  deck(cx - STRIP_OUT, cx - STRIP_IN, cz - ZEND, cz - 10, y1, concrete) -- deck 1: west ramp leaves
  deck(cx - STRIP_OUT, cx - STRIP_IN, cz + 10, cz + ZEND, y2, concrete) -- deck 2: west ramp arrives
  deck(cx + STRIP_IN, cx + STRIP_OUT, cz + 10, cz + ZEND, y2, concrete) -- deck 2: east ramp leaves
  deck(cx + STRIP_IN, cx + STRIP_OUT, cz - ZEND, cz - 10, y3, concrete) -- roof: east ramp arrives

  slope(E, cz + 12, CURB, cz - 10, y1, SW, T, ramp_c) -- in from the south street
  slope(W, cz - 10, y1, cz + 10, y2, SW, T, ramp_c)
  slope(E, cz + 10, y2, cz - 10, y3, SW, T, ramp_c)

  -- Columns under the decks (not in any driving line), edge stripes, lights.
  for _, px in ipairs{-CORE + 0.4, CORE - 0.4} do
    for _, pz in ipairs{-ZEND + 0.4, 0, ZEND - 0.4} do
      static{mesh = "cube", pos = {cx + px, CURB + 1.5 * D, cz + pz}, size = {0.6, 3 * D, 0.6}, color = concrete, tag = "carpark"}
    end
  end
  for _, y in ipairs{y1, y2, y3} do
    for _, side in ipairs{-1, 1} do
      engine.spawn{mesh = "cube", pos = {cx, y + 0.01, cz + side * (ZEND - 0.2)}, size = {2 * CORE, 0.02, 0.25}, color = stripe}
    end
    engine.light{pos = {cx, y - 0.6, cz}, color = {1, 0.95, 0.8}, radius = 14, intensity = 1.2}
  end
  -- A kicker on the roof's south edge: the reason to drive up here.
  local id = require("lib.city").ramp(cx, cz + ZEND - 3.5, 0, 5, 7, 0.3)
  local x, y, z = engine.pos(id)
  engine.set_pos(id, x, y + y3 - CURB, z)
  -- A glowing P on a pole so you can find it at night.
  static{mesh = "cube", pos = {cx - CORE + 1, y3 + 2.5, cz - ZEND + 1}, size = {0.3, 5, 0.3}, color = {0.3, 0.3, 0.32}}
  engine.spawn{mesh = "cube", pos = {cx - CORE + 1, y3 + 5.5, cz - ZEND + 1}, size = {2.4, 2.4, 0.3}, color = {0.15, 0.45, 1}, glow = 1}
  return {name = "CAR PARK", letter = "C", x = cx, z = cz, roof = y3}
end

return M
