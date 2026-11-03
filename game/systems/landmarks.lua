-- Turku's buildings the boxes from the map can't draw, made by hand where
-- the map puts them (maps/turku.lua leaves their boxes out):
--  - Ikituuri, Ylioppilaskylä's round tower (Pispalantie 14, 2011): twelve
--    floors of dark green and turquoise panels in a ring, bands of windows,
--    and a glass ground floor set back behind concrete columns.
--  - The Orthodox church on Kauppatori (Pyhän marttyyrikeisarinna Aleksandran
--    kirkko, Carlo Bassi, 1846): a yellow neoclassical hall, a portico of
--    six white columns under a pediment toward the square, and a green dome
--    on a drum with a lantern and a gilded cross.
--  - Turun taidemuseo on Puolalanmäki (Gustaf Nyström, 1904): brick faced
--    with red Skanssi granite. Its shape from the laser scans (tools/lidar.py):
--    a 21 x 37 m hall under a pitched sheet-metal roof (eaves ~12 m, ridge
--    ~17 m), a raised middle on its east side to ~20 m under glass (the
--    galleries are lit from above), and a lower wing to the west, where the
--    hill falls away. Its roofs' colours from the aerial photo.
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

-- The museum, in the frame of its walls (local x across the hall, z along
-- it), from its OpenStreetMap outline.
L.MUSEUM = {x = -449, z = -285, yaw = -0.965}

local function museum_mesh()
  local granite, plinth = {0.74, 0.62, 0.57}, {0.55, 0.47, 0.44}
  local metal, glass, copper = {0.56, 0.59, 0.63}, {0.42, 0.5, 0.58}, {0.32, 0.42, 0.4}
  local dark = {0.14, 0.15, 0.17}
  local x0, x1, z0, z1, eave, ridge = -10.4, 10.8, -18.4, 18.8, 12, 17.5
  local xm, zm = (x0 + x1) / 2, (z0 + z1) / 2
  local p = {
    -- The hall, down past the hill's fall to the west.
    {mesh = "cube", pos = {xm, (eave - 4) / 2, zm}, size = {x1 - x0, eave + 4, z1 - z0}, color = granite},
    {mesh = "cube", pos = {xm, -1.2, zm}, size = {x1 - x0 + 0.6, 2.4 + 4, z1 - z0 + 0.6}, color = plinth},
    {mesh = "cube", pos = {xm, eave - 0.3, zm}, size = {x1 - x0 + 0.8, 0.6, z1 - z0 + 0.8}, color = plinth}, -- the eaves' band
    -- Its roof: two slopes along it, the ridge a little east of the middle.
    {mesh = "wedge", pos = {(x0 + 0.2) / 2, eave + (ridge - eave) / 2, zm}, yaw = math.pi / 2,
     size = {z1 - z0 + 0.6, ridge - eave, 0.2 - x0 + 0.4}, color = metal},
    {mesh = "wedge", pos = {(0.2 + x1) / 2, eave + (ridge - eave) / 2, zm}, yaw = -math.pi / 2,
     size = {z1 - z0 + 0.6, ridge - eave, x1 - 0.2 + 0.4}, color = metal},
    -- The raised middle on the east side, under a glass roof.
    {mesh = "cube", pos = {8.6, (18.6 - 4) / 2, 0}, size = {10.2, 18.6 + 4, 20.4}, color = granite},
    {mesh = "cube", pos = {8.6, 18.3, 0}, size = {10.8, 0.6, 21}, color = plinth},
    {mesh = "wedge", pos = {6.1, 19.4, 0}, yaw = math.pi / 2, size = {19.4, 1.6, 4.8}, color = glass},
    {mesh = "wedge", pos = {11.1, 19.4, 0}, yaw = -math.pi / 2, size = {19.4, 1.6, 4.8}, color = glass},
    -- The west wing, flat-roofed, its roof gone green.
    {mesh = "cube", pos = {-14.7, (11.2 - 5) / 2, 0.4}, size = {8.4, 11.2 + 5, 18.2}, color = granite},
    {mesh = "cube", pos = {-14.7, -1.6, 0.4}, size = {9, 2.4 + 4, 18.8}, color = plinth},
    {mesh = "cube", pos = {-14.7, 11.4, 0.4}, size = {8.8, 0.4, 18.6}, color = copper},
    -- Its door: an arch's dark opening up a few steps.
    {mesh = "cube", pos = {-18.95, 2.6, 0.4}, size = {0.1, 4.2, 3}, color = dark},
    {mesh = "cube", pos = {-20.2, -0.4, 0.4}, size = {2.4, 1.2, 6}, color = plinth},
  }
  -- Windows: tall ones down the hall's sides on the lower floor (the upper
  -- galleries are lit from the roof), and on the wing.
  for k = -5, 5 do
    local z = zm + k * 3.2
    for _, x in ipairs{x0 - 0.04, x1 + 0.04} do
      if not (x > 0 and math.abs(z) < 10.5) then
        p[#p + 1] = {mesh = "cube", pos = {x, 3.6, z}, size = {0.08, 3.6, 1.5}, color = dark}
      end
    end
  end
  for k = -2, 2 do
    p[#p + 1] = {mesh = "cube", pos = {13.74, 4, k * 3.6}, size = {0.08, 4.4, 1.6}, color = dark}
    p[#p + 1] = {mesh = "cube", pos = {13.74, 10.5, k * 3.6}, size = {0.08, 3.4, 1.6}, color = dark}
    for _, z in ipairs{z0 - 0.04, z1 + 0.04} do
      p[#p + 1] = {mesh = "cube", pos = {xm + k * 3.6, 3.6, z}, size = {1.5, 3.6, 0.08}, color = dark}
    end
    if k ~= 0 then
      p[#p + 1] = {mesh = "cube", pos = {-18.95, 6.5, 0.4 + k * 3.6}, size = {0.08, 3, 1.4}, color = dark}
    end
  end
  return p
end

-- ---- Logomonsilta --------------------------------------------------------------
-- The footbridge from the station over the railway yard to Logomo (2021):
-- a glass tube on a dark frame, a black stair and lift tower at each end,
-- with a glass box out from the station end's, and black-roofed stairs down
-- from the ends (44 steps) and to the platforms, by lifts. Where
-- OpenStreetMap puts them (ways 687299560 and those joining it).
L.LOGOMONSILTA = {
  deck = {{-571.3, -469.3}, {-575.9, -466.2}, {-581.9, -473.1}, {-585.4, -477.0}, {-589.0, -481.7}, {-593.2, -487.9},
          {-595.9, -492.0}, {-599.9, -498.8}, {-603.4, -506.0}, {-607.2, -514.2}, {-610.3, -522.8}, {-611.7, -527.1},
          {-613.8, -534.8}, {-616.0, -545.2}, {-617.1, -553.4}, {-617.8, -563.8}, {-617.9, -570.7}, {-617.6, -577.5},
          {-611.4, -581.6}},
  -- {top, foot}: the ends' stairs, then the platforms'
  stairs = {{{-571.3, -469.3}, {-553.9, -480.9}}, {{-611.4, -581.6}, {-596.1, -591.5}},
            {{-588.4, -491.1}, {-570.9, -503.0}}, {{-596.8, -506.8}, {-579.1, -518.9}}, {{-603.8, -527.3}, {-585.9, -539.7}}},
  -- the platforms' stairs leave the deck here (side bridges)
  sides = {{{-593.2, -487.9}, {-588.4, -491.1}}, {{-602.0, -503.2}, {-596.8, -506.8}}, {{-610.3, -522.8}, {-603.8, -527.3}}},
  -- towers: {x, z, width, depth, yaw, height}; the ends' from the map's boxes
  towers = {{-581.4, -462.5, 5.1, 3, -2.552, 15}, {-624.4, -573.4, 5.1, 3, 0.569, 15},
            {-590.5, -493.3, 4.3, 2.2, -0.97, 12}, {-598.8, -509.1, 4.3, 2.2, -0.97, 12}, {-606.5, -529.1, 4.3, 2.2, -0.97, 12}},
  width = 6, rise = 7.6, -- inside; deck over the stairs' feet
}

local BLACK, FRAME, GLASS = {0.09, 0.09, 0.1}, {0.16, 0.16, 0.17}, {0.62, 0.74, 0.78, 0.28}
local CONCRETE, STEP = {0.62, 0.61, 0.58}, {0.55, 0.55, 0.53}

-- A box from a to b (world x, z, y at each end), w wide and h high, its
-- top `top` above the line a-b; into parts (solid = also a collider).
local function beam(out, ax, ay, az, bx, by, bz, w, h, top, color, solid)
  out.solid = out.solid or {}
  local len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
  local yaw, pitch = math.atan(bx - ax, bz - az), -math.atan(by - ay, len)
  local slant = math.sqrt(len * len + (by - ay) ^ 2)
  local p = {mesh = "cube", pos = {(ax + bx) / 2, (ay + by) / 2 + top - h / 2, (az + bz) / 2}, yaw = yaw, pitch = pitch,
             size = {w, h, slant + 0.05}, color = color}
  out[#out + 1] = p
  if solid then out.solid[#out.solid + 1] = p end
  return p
end

-- The tube along the points (x, z, y): floor, roof, frame and glass. The
-- glass walls stand solid but where `open` (points the side bridges leave
-- from) is within 3.5 m.
local function tube(out, glass, pts, w, open)
  for i = 2, #pts do
    local a, b = pts[i - 1], pts[i]
    local len = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
    if len > 0.1 then
      local rx, rz = (b[2] - a[2]) / len, -(b[1] - a[1]) / len -- right of the way
      beam(out, a[1], a[3], a[2], b[1], b[3], b[2], w + 0.6, 0.9, 0, BLACK)       -- the floor's dark underside
      beam(out, a[1], a[3], a[2], b[1], b[3], b[2], w, 0.3, 0.02, CONCRETE, true)  -- what you walk on
      beam(out, a[1], a[3], a[2], b[1], b[3], b[2], w + 0.8, 0.45, 3.3, BLACK)     -- the roof
      local n = math.max(1, math.floor(len / 2.4 + 0.5))
      for k = 0, n - 1 do
        local f0, f1 = k / n, (k + 1) / n
        local x0, z0, y0 = a[1] + (b[1] - a[1]) * f0, a[2] + (b[2] - a[2]) * f0, a[3] + (b[3] - a[3]) * f0
        local x1, z1, y1 = a[1] + (b[1] - a[1]) * f1, a[2] + (b[2] - a[2]) * f1, a[3] + (b[3] - a[3]) * f1
        for _, side in ipairs{-1, 1} do
          local ox, oz = rx * side * (w / 2 + 0.1), rz * side * (w / 2 + 0.1)
          local mx, mz = (x0 + x1) / 2 + ox, (z0 + z1) / 2 + oz
          local gap = false
          for _, o in ipairs(open) do
            if (mx - o[1]) ^ 2 + (mz - o[2]) ^ 2 < 3.5 ^ 2 then gap = true end
          end
          if not gap then
            glass[#glass + 1] = {mesh = "cube", pos = {mx, (y0 + y1) / 2 + 1.6, mz}, yaw = math.atan(b[1] - a[1], b[2] - a[2]),
                                 pitch = -math.atan(y1 - y0, len / n), size = {0.06, 2.8, len / n}, color = {1, 1, 1}}
            out.solid[#out.solid + 1] = {pos = {mx, (y0 + y1) / 2 + 1.6, mz}, yaw = math.atan(b[1] - a[1], b[2] - a[2]),
                                         size = {0.3, 2.8, len / n}}
            -- the handrail along the glass
            out[#out + 1] = {mesh = "cube", pos = {mx - rx * side * 0.1, (y0 + y1) / 2 + 1.05, mz - rz * side * 0.1},
                             yaw = math.atan(b[1] - a[1], b[2] - a[2]), pitch = -math.atan(y1 - y0, len / n),
                             size = {0.08, 0.08, len / n}, color = {0.7, 0.7, 0.68}}
          end
          -- a mullion where the panes meet
          out[#out + 1] = {mesh = "cube", pos = {x0 + ox, y0 + 1.6, z0 + oz}, size = {0.14, 3.0, 0.14}, color = FRAME}
        end
      end
      -- lit along the roof's underside
      beam(out, a[1], a[3], a[2], b[1], b[3], b[2], 0.5, 0.05, 3.05, {1, 0.95, 0.85}).emissive = 1
    end
  end
end

-- Covered stairs from `top` (x, z, y) down to `foot` (x, z, y): steps, black
-- walls and a black roof over them, and the ramp under your feet.
local function covered_stairs(out, top, foot, w)
  local len = math.sqrt((top[1] - foot[1]) ^ 2 + (top[2] - foot[2]) ^ 2)
  local rise = top[3] - foot[3]
  local n = math.max(2, math.floor(rise / 0.17 + 0.5))
  local yaw = math.atan(top[1] - foot[1], top[2] - foot[2])
  local rx, rz = math.cos(yaw), -math.sin(yaw)
  for k = 0, n - 1 do
    local f = (k + 0.5) / n
    local x, z = foot[1] + (top[1] - foot[1]) * f, foot[2] + (top[2] - foot[2]) * f
    local y = foot[3] + (k + 1) * rise / n
    local bottom = foot[3] - 0.3
    out[#out + 1] = {mesh = "cube", pos = {x, (y + bottom) / 2, z}, yaw = yaw, size = {w, y - bottom, len / n * 1.04}, color = STEP}
  end
  out.solid[#out.solid + 1] = beam({}, foot[1], foot[3], foot[2], top[1], top[3], top[2], w, 0.5, 0)
  for _, side in ipairs{-1, 1} do
    local ox, oz = rx * side * (w / 2 + 0.15), rz * side * (w / 2 + 0.15)
    beam(out, foot[1] + ox, foot[3], foot[2] + oz, top[1] + ox, top[3], top[2] + oz, 0.3, 3.2, 3.0, BLACK, true)
  end
  beam(out, foot[1], foot[3], foot[2], top[1], top[3], top[2], w + 0.9, 0.35, 3.3, BLACK)
  -- a strip of glass along the roof's middle, lit at night
  beam(out, foot[1], foot[3], foot[2], top[1], top[3], top[2], w * 0.4, 0.05, 3.32, {0.55, 0.62, 0.66}).emissive = 0.5
end

local function logomonsilta()
  local T = L.LOGOMONSILTA
  local G = function(x, z) return U.ground(x, z) end
  -- The deck's height: the end stairs' feet, plus the rise, sloping between.
  local s1, s2 = T.stairs[1][2], T.stairs[2][2]
  local y1, y2 = G(s1[1], s1[2]) + T.rise, G(s2[1], s2[2]) + T.rise
  local total, run = 0, {0}
  for i = 2, #T.deck do
    total = total + math.sqrt((T.deck[i][1] - T.deck[i - 1][1]) ^ 2 + (T.deck[i][2] - T.deck[i - 1][2]) ^ 2)
    run[i] = total
  end
  local pts = {}
  for i, p in ipairs(T.deck) do pts[i] = {p[1], p[2], y1 + (y2 - y1) * run[i] / total} end
  local function deck_y(x, z) -- at the nearest deck point
    local best, y = math.huge, y1
    for _, p in ipairs(pts) do
      local d = (p[1] - x) ^ 2 + (p[2] - z) ^ 2
      if d < best then best, y = d, p[3] end
    end
    return y
  end
  local out, glass = {solid = {}}, {}
  local open = {pts[2], pts[#pts - 1]} -- the bends at the ends, to the stairs
  for _, s in ipairs(T.sides) do open[#open + 1] = s[1] end
  tube(out, glass, pts, T.width, open)
  -- Landings at the deck's bends at its ends, and the side bridges to the
  -- platforms' stairs.
  for _, i in ipairs{2, #pts - 1} do
    local p = pts[i]
    out[#out + 1] = {mesh = "cube", pos = {p[1], p[3] - 0.13, p[2]}, size = {T.width + 0.6, 0.3, T.width + 0.6}, color = CONCRETE}
    out.solid[#out.solid + 1] = out[#out]
    out[#out + 1] = {mesh = "cube", pos = {p[1], p[3] + 3.1, p[2]}, size = {T.width + 1.2, 0.45, T.width + 1.2}, color = BLACK}
  end
  for _, s in ipairs(T.sides) do
    local y = deck_y(s[1][1], s[1][2])
    tube(out, glass, {{s[1][1], s[1][2], y}, {s[2][1], s[2][2], y}}, 3.2, {s[1], s[2]})
  end
  for i, s in ipairs(T.stairs) do
    local top, foot = s[1], s[2]
    covered_stairs(out, {top[1], top[2], deck_y(top[1], top[2])}, {foot[1], foot[2], G(foot[1], foot[2])}, i <= 2 and 3.4 or 2.6)
  end
  -- The towers, black, with a lit band where the deck meets them; at the
  -- station end, a glass box out over the street at the deck's level.
  for _, t in ipairs(T.towers) do
    local g = G(t[1], t[2])
    out[#out + 1] = {mesh = "cube", pos = {t[1], g + t[6] / 2, t[2]}, yaw = t[5], size = {t[3], t[6], t[4]}, color = BLACK}
    out.solid[#out.solid + 1] = out[#out]
    out[#out + 1] = {mesh = "cube", pos = {t[1], deck_y(t[1], t[2]) + 1.5, t[2]}, yaw = t[5], size = {t[3] + 0.06, 2.6, t[4] + 0.06},
                     color = {0.5, 0.6, 0.62}, emissive = 0.3}
  end
  -- The glass box: the station end's landing, glazed all round over a
  -- black floor and roof, with a thin brass-coloured edge.
  local e = pts[2]
  local bw = T.width + 1.4
  glass[#glass + 1] = {mesh = "cube", pos = {e[1], e[3] + 1.75, e[2]}, size = {bw, 3.4, bw}, color = {1, 1, 1}}
  for _, y in ipairs{-0.35, 3.6} do
    out[#out + 1] = {mesh = "cube", pos = {e[1], e[3] + y, e[2]}, size = {bw + 0.3, 0.5, bw + 0.3}, color = BLACK}
    out[#out + 1] = {mesh = "cube", pos = {e[1], e[3] + y, e[2]}, size = {bw + 0.36, 0.12, bw + 0.36}, color = {0.72, 0.6, 0.32}}
  end
  -- Pairs of dark columns under the deck every few points.
  for i = 3, #pts - 2, 2 do
    local a, b = pts[i - 1], pts[i + 1]
    local len = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
    local rx, rz = (b[2] - a[2]) / len, -(b[1] - a[1]) / len
    for _, side in ipairs{-1, 1} do
      local x, z = pts[i][1] + rx * side * 2.2, pts[i][2] + rz * side * 2.2
      local g = G(x, z)
      out[#out + 1] = {mesh = "cube", pos = {x, (g + pts[i][3] - 0.9) / 2, z}, size = {0.6, pts[i][3] - 0.9 - g, 0.6}, color = FRAME}
      out.solid[#out.solid + 1] = out[#out]
    end
  end
  -- Baked round the deck's middle, absolute heights; the glass its own
  -- see-through entity; what you stand on and bump into, unseen boxes.
  local mid = pts[math.floor(#pts / 2)]
  local cx, cz = mid[1], mid[2]
  local function local_parts(list)
    local r = {}
    for _, p in ipairs(list) do
      local q = {}
      for k, v in pairs(p) do q[k] = v end
      q.pos = {p.pos[1] - cx, p.pos[2], p.pos[3] - cz}
      r[#r + 1] = q
    end
    return r
  end
  engine.mesh("logomonsilta", local_parts(out))
  engine.mesh("logomonsilta_glass", local_parts(glass))
  L.logomonsilta_id = engine.spawn{mesh = "logomonsilta", pos = {cx, 0, cz}, tag = "bridge"}
  engine.spawn{mesh = "logomonsilta_glass", pos = {cx, 0, cz}, color = GLASS, tag = "bridge"}
  for _, p in ipairs(out.solid) do
    engine.spawn{mesh = "cube", pos = p.pos, yaw = p.yaw, pitch = p.pitch, size = p.size, visible = false, body = "static",
                 tag = "bridge"}
  end
  print(string.format("logomonsilta: %.0f m long, deck %.1f-%.1f m up, %d parts, %d solid", total, y1, y2, #out + #glass, #out.solid))
end

-- ---- Louhi --------------------------------------------------------------------
-- The way into Louhi, the car park in the rock under Puolalanmäki and
-- Kauppatori, at the foot of Puolalanportaat: a concrete portal in a face
-- of granite, LOUHI over it, the 2.2 m height bar hung across the drive and
-- a blue P by it. (OpenStreetMap node 26706967; the tunnel runs 400 m on
-- to Kauppatori, toward `to`.) Not open: the hill is solid ground here.
L.LOUHI = {x = -511, z = -369, to = {-302, -75}}

local function louhi()
  local T = L.LOUHI
  local fx, fz = T.to[1] - T.x, T.to[2] - T.z
  local l = math.sqrt(fx * fx + fz * fz)
  fx, fz = fx / l, fz / l -- into the hill
  local rx, rz = fz, -fx   -- across
  local yaw = math.atan(fx, fz)
  -- The face 2 m out from the node, where the hill starts to rise; the
  -- drive's level in front of it.
  local cx, cz = T.x - fx * 2, T.z - fz * 2
  local floor = U.ground(T.x - fx * 6, T.z - fz * 6)
  local function at(u, v) return cx + fx * u + rx * v, cz + fz * u + rz * v end
  local ROCK, ROCK2, CONC, DARK = {0.5, 0.46, 0.44}, {0.44, 0.41, 0.4}, {0.66, 0.65, 0.62}, {0.03, 0.03, 0.035}
  local W, H = 6.2, 3.2 -- the opening
  local parts, solid = {}, {}
  local function box(u, v, y, w, h, d, color, extra)
    local x, z = at(u, v)
    local p = {mesh = "cube", pos = {x, y, z}, yaw = yaw, size = {w, h, d}, color = color}
    for k, val in pairs(extra or {}) do p[k] = val end
    parts[#parts + 1] = p
    return p
  end
  -- The rock it's cut into, standing out of the slope (and what you bump);
  -- no wider than the frame: Puolalanportaat come down either side of it.
  -- What you bump starts 3 m in: through the opening you're in Louhi
  -- (systems/louhi) before you reach it; either side, the frame.
  box(5, 0, floor + 3.6, W + 1.6, 7.2, 10, ROCK)
  solid[#solid + 1] = {pos = {at(6.5, 0)}, size = {W + 1.6, 7.2, 7}}
  solid[#solid].pos = {solid[#solid].pos[1], floor + 3.6, solid[#solid].pos[2]}
  for _, side in ipairs{-1, 1} do
    local x, z = at(1.25, side * (W / 2 + 0.4))
    solid[#solid + 1] = {pos = {x, floor + 3.6, z}, size = {0.8, 7.2, 3.5}}
  end
  -- its top broken, as a blasted face is
  box(4, -1.6, floor + 7.4, 4.2, 1.4, 7, ROCK2, {roll = 0.12, pitch = 0.1})
  box(6, 1.8, floor + 7.2, 4, 1.2, 6, ROCK2, {roll = -0.15})
  -- The concrete frame round the opening, and the dark way in.
  box(-0.15, 0, floor + H + 0.6, W + 1.6, 1.2, 0.5, CONC)          -- lintel
  box(-0.15, -(W / 2 + 0.4), floor + H / 2, 0.8, H, 0.5, CONC)     -- sides
  box(-0.15, W / 2 + 0.4, floor + H / 2, 0.8, H, 0.5, CONC)
  box(0.1, 0, floor + H / 2, W, H, 0.3, DARK)
  box(0.05, 0, floor + H - 0.2, W - 0.6, 0.08, 0.1, {1, 0.92, 0.75}, {emissive = 0.8}) -- lights inside
  box(0.05, 0, floor + 0.04, W, 0.1, 0.35, {0.3, 0.3, 0.31})       -- the ramp going down
  -- Wing walls either side, out to the drive.
  for _, side in ipairs{-1, 1} do
    box(-2.5, side * (W / 2 + 0.6), floor + 0.9, 0.4, 1.8, 5, CONC)
  end
  -- LOUHI over the opening, white on a dark band, lit at night.
  box(-0.42, 0, floor + H + 0.6, 4.2, 0.95, 0.06, {0.12, 0.13, 0.15})
  local lx, lz = at(-0.45, 0)
  parts[#parts + 1] = {text = "LOUHI", pos = {lx - fx * 0.05, floor + H + 0.6, lz - fz * 0.05}, yaw = yaw + math.pi, height = 0.75, depth = 0.08,
                       color = {0.95, 0.95, 0.92}, emissive = 0.6}
  -- The height bar on two posts across the drive, striped yellow and black,
  -- 2.2 m clear.
  for k = -3, 3 do
    box(-6, k * 0.9, floor + 2.35, 0.9, 0.3, 0.3, k % 2 == 0 and {0.95, 0.8, 0.1} or {0.08, 0.08, 0.08})
  end
  for _, side in ipairs{-1, 1} do box(-6, side * 3.4, floor + 1.25, 0.2, 2.5, 0.2, {0.3, 0.3, 0.32}) end
  local hx, hz = at(-6.2, 0)
  parts[#parts + 1] = {text = "2,2 m", pos = {hx, floor + 2.35, hz}, yaw = yaw + math.pi, height = 0.2, depth = 0.04,
                       color = {0.08, 0.08, 0.08}}
  -- The blue P on a post by the drive.
  box(-9, 3.2, floor + 1.4, 0.1, 2.8, 0.1, {0.4, 0.4, 0.42})
  box(-9.06, 3.2, floor + 2.6, 0.75, 0.75, 0.05, {0.1, 0.3, 0.75})
  local px, pz = at(-9.12, 3.2)
  parts[#parts + 1] = {text = "P", pos = {px, floor + 2.6, pz}, yaw = yaw + math.pi, height = 0.55, depth = 0.03,
                       color = {1, 1, 1}}
  -- Baked round the face's middle.
  for _, p in ipairs(parts) do p.pos = {p.pos[1] - cx, p.pos[2] - floor, p.pos[3] - cz} end
  engine.mesh("louhi", parts)
  L.louhi_id = engine.spawn{mesh = "louhi", pos = {cx, floor, cz}, tag = "building"}
  for _, p in ipairs(solid) do
    engine.spawn{mesh = "cube", pos = p.pos, yaw = yaw, size = p.size, visible = false, body = "static", tag = "building"}
  end
end

local made = false
function L.build(map)
  if not map or map.id ~= "turku" then return end
  if not made then
    engine.mesh("ikituuri", ikituuri_mesh())
    engine.mesh("orthodox_church", church_mesh())
    engine.mesh("taidemuseo", museum_mesh())
    made = true
  end
  local T = L.IKITUURI
  local y = U.ground(T.x, T.z)
  L.ikituuri_id = engine.spawn{mesh = "ikituuri", pos = {T.x, y, T.z}, tag = "building"}
  -- What you drive into: an octagon round the ring, of four bars across
  -- it. (Two squares, one turned 45 degrees, made a star whose points
  -- stood 16 m out, 4 m into Pispalantie.)
  local a = T.r * 0.97
  for i = 0, 3 do
    engine.spawn{mesh = "cube", pos = {T.x, y + T.h / 2, T.z}, yaw = i * math.pi / 4,
                 size = {2 * a, T.h, 2 * a * math.tan(math.pi / 8)}, visible = false, body = "static", tag = "building"}
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

  local M = L.MUSEUM
  local my = U.ground(M.x, M.z)
  logomonsilta()
  louhi()

  L.museum_id = engine.spawn{mesh = "taidemuseo", pos = {M.x, my, M.z}, yaw = M.yaw, tag = "building"}
  -- What you drive into: the hall with its raised middle, and the wing.
  local function solid(u, v, w, h, d)
    local ux, uz = math.cos(M.yaw), -math.sin(M.yaw) -- local +x
    local vx, vz = math.sin(M.yaw), math.cos(M.yaw)  -- local +z
    engine.spawn{mesh = "cube", pos = {M.x + ux * u + vx * v, my + h / 2 - 4, M.z + uz * u + vz * v}, yaw = M.yaw,
                 size = {w, h + 4, d}, visible = false, body = "static", tag = "building"}
  end
  solid(0.2, 0.2, 21.2, 17, 37.2)
  solid(8.6, 0, 10.2, 19, 20.4)
  solid(-14.7, 0.4, 8.4, 11.2, 18.2)
end

return L
