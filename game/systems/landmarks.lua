-- Turku's buildings the boxes from the map can't draw, made by hand where
-- the map puts them (maps/turku.lua leaves their boxes out):
--  - Ikituuri, Ylioppilaskylä's round tower (Pispalantie 14, 2011): twelve
--    floors of dark green and turquoise panels in a ring, bands of windows,
--    and a glass ground floor set back behind concrete columns.
--  - The Orthodox church on Kauppatori (Pyhän marttyyrikeisarinna Aleksandran
--    kirkko, Carlo Bassi, 1846): a yellow neoclassical hall, a portico of
--    six white columns under a pediment toward the square, and a green dome
--    on a drum with a lantern and a gilded cross.
local U = require "lib.util"

local L = {}

-- Ikituuri's ring, from its OpenStreetMap outline (way 649702860).
L.IKITUURI = {x = 872.5, z = -1012.6, r = 11.7, h = 43}

local function ikituuri_mesh()
  local T = L.IKITUURI
  local parts = {}
  local N, R, H = 24, T.r, T.h
  local GROUND, FLOOR = 4.6, (T.h - 4.6) / 11
  local green, teal = {0.13, 0.33, 0.27}, {0.24, 0.55, 0.5}
  local glass = {0.12, 0.17, 0.19}
  local w = 2 * math.pi * R / N + 0.12 -- a panel's width, overlapping its neighbours a little
  for k = 0, N - 1 do
    local a = (k + 0.5) * 2 * math.pi / N
    local sx, sz = math.sin(a), math.cos(a)
    -- The panels, alternately green and turquoise, from the first floor up.
    parts[#parts + 1] = {mesh = "cube", pos = {sx * R, GROUND + (H - GROUND) / 2, sz * R}, yaw = a,
                         size = {w, H - GROUND, 0.4}, color = k % 2 == 0 and green or teal}
    -- A window on each floor, standing proud of the panel.
    for f = 0, 10 do
      local lit = (k * 5 + f * 3) % 7 < 2
      parts[#parts + 1] = {mesh = "cube", pos = {sx * (R + 0.22), GROUND + f * FLOOR + 1.7, sz * (R + 0.22)}, yaw = a,
                           size = {w * 0.72, 1.6, 0.06}, color = lit and {0.34, 0.31, 0.25} or glass,
                           emissive = lit and 1 or 0}
    end
  end
  -- The core (the roof, and what's seen between the panels' edges), and a
  -- parapet and plant room on top.
  parts[#parts + 1] = {mesh = "cylinder", pos = {0, GROUND + (H - GROUND) / 2, 0}, size = {2 * R - 0.6, H - GROUND - 0.2, 2 * R - 0.6},
                       color = {0.55, 0.57, 0.56}}
  parts[#parts + 1] = {mesh = "cylinder", pos = {0, H + 1.4, 0}, size = {9, 2.8, 9}, color = {0.62, 0.63, 0.62}}
  -- The ground floor: glass set back, and a ring of columns under the panels.
  parts[#parts + 1] = {mesh = "cylinder", pos = {0, GROUND / 2, 0}, size = {2 * R - 3.4, GROUND, 2 * R - 3.4}, color = glass, emissive = 0.15}
  parts[#parts + 1] = {mesh = "cylinder", pos = {0, GROUND - 0.25, 0}, size = {2 * R + 0.3, 0.5, 2 * R + 0.3}, color = {0.7, 0.7, 0.68}}
  for k = 0, 11 do
    local a = k * 2 * math.pi / 12
    parts[#parts + 1] = {mesh = "cylinder", pos = {math.sin(a) * (R - 0.6), GROUND / 2, math.cos(a) * (R - 0.6)},
                         size = {0.7, GROUND, 0.7}, color = {0.72, 0.72, 0.7}}
  end
  return parts
end

-- The church, on the map's box for it (footprint 29.6 x 21.7 m): its
-- front, the portico, toward the square (local -z).
L.CHURCH = {x = -220.1, z = -87.4, yaw = -2.538, w = 29.6, d = 21.7}

local function church_mesh()
  local T = L.CHURCH
  local yellow, white = {0.93, 0.84, 0.6}, {0.95, 0.94, 0.9}
  local copper, gold = {0.38, 0.58, 0.5}, {0.92, 0.75, 0.25}
  local dark = {0.16, 0.17, 0.2}
  local W, D = T.w - 3, T.d - 6 -- the hall, the portico in front
  local zc = (T.d - D) / 2 -- the hall's middle, back from the box's
  local front = -T.d / 2
  local p = {
    {mesh = "cube", pos = {0, 0.4, zc}, size = {W + 0.8, 0.8, D + 0.8}, color = {0.62, 0.6, 0.57}}, -- plinth
    {mesh = "cube", pos = {0, 6.4, zc}, size = {W, 11.2, D}, color = yellow},
    {mesh = "cube", pos = {0, 12.3, zc}, size = {W + 0.7, 0.8, D + 0.7}, color = white}, -- cornice
    {mesh = "cube", pos = {0, 13.1, zc}, size = {W - 1, 0.8, D - 1}, color = {0.5, 0.52, 0.5}}, -- the low roof
    -- The drum and the dome, the lantern on it and the cross.
    {mesh = "cylinder", pos = {0, 16.2, zc}, size = {11, 6, 11}, color = yellow},
    {mesh = "cylinder", pos = {0, 19.3, zc}, size = {11.6, 0.6, 11.6}, color = white},
    {mesh = "sphere", pos = {0, 19.4, zc}, size = {11, 9, 11}, color = copper},
    {mesh = "cylinder", pos = {0, 24.6, zc}, size = {2, 2.4, 2}, color = yellow},
    {mesh = "sphere", pos = {0, 25.8, zc}, size = {2.4, 2, 2.4}, color = copper},
    {mesh = "cube", pos = {0, 28.2, zc}, size = {0.18, 3.2, 0.18}, color = gold},
    {mesh = "cube", pos = {0, 28.9, zc}, size = {1.3, 0.16, 0.16}, color = gold},
    -- The portico: steps, six columns, the beam over them and the pediment.
    {mesh = "cube", pos = {0, 0.5, front + 3}, size = {16, 1, 6}, color = {0.7, 0.68, 0.64}},
    {mesh = "cube", pos = {0, 10.4, front + 3}, size = {15, 1.6, 5.4}, color = white},
    {mesh = "wedge", pos = {-3.75, 12.4, front + 3}, yaw = math.pi / 2, size = {5.4, 2.4, 7.5}, color = white},
    {mesh = "wedge", pos = {3.75, 12.4, front + 3}, yaw = -math.pi / 2, size = {5.4, 2.4, 7.5}, color = white},
    -- The door.
    {mesh = "cube", pos = {0, 3.2, zc - D / 2 - 0.03}, size = {2.4, 4.4, 0.08}, color = {0.35, 0.22, 0.14}},
  }
  for k = 0, 5 do
    p[#p + 1] = {mesh = "cylinder", pos = {-6.25 + k * 2.5, 5.3, front + 1.2}, size = {1, 8.6, 1}, color = white}
  end
  -- Tall windows down the sides and on the drum.
  for k = -2, 2 do
    for _, sx in ipairs{-1, 1} do
      p[#p + 1] = {mesh = "cube", pos = {sx * (W / 2 + 0.03), 6.5, zc + k * D / 5.5}, size = {0.08, 4, 1.4}, color = dark}
    end
    p[#p + 1] = {mesh = "cube", pos = {k * W / 5.5, 6.5, zc + D / 2 + 0.03}, size = {1.4, 4, 0.08}, color = dark}
  end
  for k = 0, 7 do
    local a = k * math.pi / 4
    p[#p + 1] = {mesh = "cube", pos = {math.sin(a) * 5.45, 16.4, zc + math.cos(a) * 5.45}, yaw = a, size = {0.9, 2.6, 0.12}, color = dark}
  end
  return p
end

local made = false
function L.build(map)
  if not map or map.id ~= "turku" then return end
  if not made then
    engine.mesh("ikituuri", ikituuri_mesh())
    engine.mesh("orthodox_church", church_mesh())
    made = true
  end
  local T = L.IKITUURI
  local y = U.ground(T.x, T.z)
  L.ikituuri_id = engine.spawn{mesh = "ikituuri", pos = {T.x, y, T.z}, tag = "building"}
  -- What you drive into: an octagon of two boxes round the ring.
  for _, yaw in ipairs{0, math.pi / 4} do
    engine.spawn{mesh = "cube", pos = {T.x, y + T.h / 2, T.z}, yaw = yaw, size = {2 * T.r * 0.97, T.h, 2 * T.r * 0.97},
                 visible = false, body = "static", tag = "building"}
  end

  local C = L.CHURCH
  local cy = U.ground(C.x, C.z)
  L.church_id = engine.spawn{mesh = "orthodox_church", pos = {C.x, cy, C.z}, yaw = C.yaw, tag = "building"}
  -- The hall, and the portico's steps and columns as one block.
  local fx, fz = math.sin(C.yaw), math.cos(C.yaw) -- local +z
  local zc = 3
  engine.spawn{mesh = "cube", pos = {C.x + fx * zc, cy + 7, C.z + fz * zc}, yaw = C.yaw, size = {C.w - 3, 14, C.d - 6},
               visible = false, body = "static", tag = "building"}
  engine.spawn{mesh = "cube", pos = {C.x - fx * (C.d / 2 - 3), cy + 6, C.z - fz * (C.d / 2 - 3)}, yaw = C.yaw, size = {16, 12, 6},
               visible = false, body = "static", tag = "building"}
end

return L
