-- EduCity (Joukahaisenkatu 7, Kupittaa, 2020; Pekka Mäki, Johan Roman, Leena
-- Arola): Turun ammattikorkeakoulu's main building, on the campus's
-- pedestrian street, joined to ICT-City by a bridge. Its walls are handmade
-- grey Kolumba tiles (maps/turku.lua's outline_looks); inside, the big atrium
-- under a skylight of printed glass, wooden "dice" jutting from the galleries
-- (for the sound), and the Stairway of Skills down from the foyer to the
-- restaurant. (Arkkitehti 1/2021.)
--
-- On foot: in by the glass door on Joukahaisenkatu, the atrium in layer 1
-- (as the Kauppahalli): coffee at the foyer's café, lunch down the stairs,
-- and a hackathon at the long tables on the atrium floor, at any hour.
-- Inside, the cops lose sight of you.
local G = require "lib.state"
local U = require "lib.util"
local health = require "lib.health"
local wanted = require "lib.wanted"

local M = {built = false, shops = {}}

-- The frame: `along` the Joukahaisenkatu wall (OSM outline, its corners at
-- (1494.5, 292.3) and (1534.9, 324.7)), `in` from it into the building.
-- The atrium fills along -24..24, in 1..29, inside the outline.
local OX, OZ = 1514.7, 308.5
local AX, AZ = 0.7800, 0.6257
local CX, CZ = -AZ, AX
local LAYER = 1
M.LAYER = LAYER
local function xz(a, c) return OX + AX * a + CX * c, OZ + AZ * a + CZ * c end
local function ac(x, z)
  local dx, dz = x - OX, z - OZ
  return dx * AX + dz * AZ, dx * CX + dz * CZ
end
M.xz, M.ac = xz, ac

-- Heights, from the floor (M.HF, the ground at the door, set at build).
local ROOF = 22       -- the skylight over the atrium
local LOW = -3.5      -- the restaurant's floor, down the Stairway of Skills
local GALLERY = 4.2   -- a floor of galleries round the atrium every this
M.LOW = LOW
-- The floors: the foyer and the hackathon's floor, the stairs, the restaurant.
M.AREAS = {
  {a0 = -24, a1 = 24, c0 = 1, c1 = 9, y = 0},       -- foyer
  {a0 = 4, a1 = 24, c0 = 9, c1 = 29, y = 0},        -- the atrium floor (hackathon)
  {a0 = -24, a1 = 4, c0 = 9, c1 = 17, stairs = true}, -- Stairway of Skills, 0 -> LOW
  {a0 = -24, a1 = 4, c0 = 17, c1 = 29, y = LOW},    -- restaurant
}
M.DOOR = {a = 0, c_out = -1.6, c_in = 2.6}

local yaw_a, yaw_c = math.atan(AX, AZ), math.atan(CX, CZ)
local function kit()
  local k = {parts = {}, solids = {}}
  local function put(p, solid)
    k.parts[#k.parts + 1] = p
    if solid then k.solids[#k.solids + 1] = p end
    return p
  end
  -- a box `l` along by `w` in, `h` tall, centred at (a, c, y)
  function k.box(a, c, y, l, w, h, color, solid, emissive)
    local x, z = xz(a, c)
    return put({mesh = "cube", pos = {x, y, z}, yaw = yaw_a, size = {w, h, l}, color = color, emissive = emissive}, solid)
  end
  -- sloping in: from (c0, y0) to (c1, y1), `l` along, its top surface on that line
  function k.slope(a, l, c0, c1, y0, y1, h, color, solid)
    local dc, dy = c1 - c0, y1 - y0
    local pitch = math.atan(dy, dc)
    local x, z = xz(a, (c0 + c1) / 2)
    return put({mesh = "cube", pos = {x, (y0 + y1) / 2 - h / 2 * math.cos(pitch), z}, yaw = yaw_c, pitch = -pitch,
                size = {l, h, math.sqrt(dc * dc + dy * dy)}, color = color}, solid)
  end
  local FACE = {["+a"] = {1, 0}, ["-a"] = {-1, 0}, ["+c"] = {0, 1}, ["-c"] = {0, -1}}
  function k.text(a, c, y, face, s, height, color, emissive)
    local f = FACE[face]
    local x, z = xz(a + f[1] * 0.03, c + f[2] * 0.03)
    local fx, fz = AX * f[1] + CX * f[2], AZ * f[1] + CZ * f[2]
    put{text = s, pos = {x, y, z}, yaw = math.atan(fx, fz), height = height, depth = 0.03, color = color or {1, 1, 1}, emissive = emissive}
  end
  return k
end

local function spawn(name, k, layer)
  engine.mesh(name, k.parts)
  engine.spawn{mesh = name, pos = {0, 0, 0}, layer = layer, tag = "building"}
  for _, s in ipairs(k.solids) do
    engine.spawn{mesh = "cube", pos = s.pos, yaw = s.yaw, pitch = s.pitch, size = s.size, visible = false,
                 body = "static", tag = s.tag or "wall", layer = layer}
  end
end

local TILE = {0.64, 0.62, 0.58}
local DARK = {0.16, 0.17, 0.19}
local GLASS = {0.55, 0.66, 0.72}
local WHITE = {0.94, 0.94, 0.92}
local AMK = {0.86, 0.1, 0.32} -- Turku AMK's raspberry

-- Outside, in layer 0: the glass entrance and its canopy, EDUCITY up on the
-- wall, the bridge to ICT-City over the campus street.
local function build_outside(y)
  local k = kit()
  local a = M.DOOR.a
  k.box(a, -0.1, y + 1.6, 7.0, 0.3, 3.2, {0.2, 0.22, 0.25})              -- the glazed front
  for s = -3, 3, 1.5 do k.box(a + s, -0.28, y + 1.6, 0.12, 0.08, 3.2, {0.82, 0.83, 0.84}) end
  k.box(a, -0.3, y + 1.25, 2.4, 0.1, 2.5, GLASS, false, 0.35)            -- the doors, lit
  k.box(a, -1.6, y + 3.5, 9.0, 3.4, 0.3, {0.8, 0.8, 0.79})               -- canopy
  k.box(a, -2.9, y + 3.1, 9.0, 0.1, 0.5, AMK)
  k.text(a, -3.0, y + 3.1, "-c", "TURUN AMK  -  EDUCITY", 0.32, WHITE, 0.5)
  -- the name, big, high on the wall over the street
  k.box(-6, -0.12, y + 33.5, 22, 0.2, 3.6, DARK)
  k.text(-6, -0.22, y + 33.5, "-c", "EDUCITY", 2.6, WHITE, 1)
  k.box(0, -3.0, y + 4.6, 9.0, 0.3, 1.6, WHITE)
  k.text(0, -3.15, y + 4.6, "-c", "EDUCITY", 1.1, AMK, 0.6)
  -- bikes in a rack by the door
  for s = 6, 11, 1.2 do
    k.box(s, -2.4, y + 0.45, 0.06, 1.7, 0.9, {0.15, 0.15, 0.16})
  end
  spawn("educity_outside", k, 0)
  -- (the bridge in world terms: from ICT-City's corner across the street)
  local x0, z0, x1, z1 = 1443.0, 335.0, 1452.5, 347.0
  local gy = math.max(U.ground(x0, z0), U.ground(x1, z1))
  local len = math.sqrt((x1 - x0) ^ 2 + (z1 - z0) ^ 2)
  local by = math.atan(x1 - x0, z1 - z0)
  local mx, mz = (x0 + x1) / 2, (z0 + z1) / 2
  engine.mesh("educity_bridge", {
    {mesh = "cube", pos = {0, 0, 0}, size = {3.6, 0.5, len}, color = {0.7, 0.71, 0.72}},
    {mesh = "cube", pos = {0, 1.6, 0}, size = {3.5, 2.7, len - 0.2}, color = GLASS, emissive = 0.15},
    {mesh = "cube", pos = {0, 3.1, 0}, size = {3.7, 0.35, len}, color = {0.6, 0.62, 0.64}},
  })
  engine.spawn{mesh = "educity_bridge", pos = {mx, gy + 8.0, mz}, yaw = by, tag = "building"}
end

-- The atrium, in layer 1.
local function build_inside(y)
  local k = kit()
  local CONC = {0.66, 0.65, 0.62}
  local TIMBER = {0.72, 0.55, 0.36}
  local SLAT = {0.62, 0.46, 0.3}
  -- floors (solid, "ground": walking on them isn't hitting a wall)
  local function floor(a0, a1, c0, c1, fy, color)
    local p = k.box((a0 + a1) / 2, (c0 + c1) / 2, fy - 0.25, a1 - a0, c1 - c0, 0.5, color, true)
    p.tag = "ground"
  end
  floor(-24, 24, 1, 9, y, {0.5, 0.52, 0.55})
  floor(4, 24, 9, 29, y, {0.5, 0.52, 0.55})
  floor(-24, 4, 17, 29, y + LOW, {0.48, 0.47, 0.45})
  -- colourful floors (Arkkitehti: "colourful floors and textiles")
  for i, col in ipairs{{0.95, 0.72, 0.18}, {0.2, 0.62, 0.62}, AMK, {0.35, 0.52, 0.85}} do
    k.box(-18 + i * 7, 5, y + 0.02, 5, 3, 0.04, col)
  end
  k.box(14, 19, y + 0.02, 18, 18, 0.04, {0.3, 0.55, 0.58})
  -- the Stairway of Skills: wide timber steps you sit on, a ramp under them
  local n = 12
  for i = 0, n - 1 do
    local c = 9 + (i + 0.5) * 8 / n
    local top = y + LOW * (i + 1) / n
    local h = top - (y + LOW) + 0.05
    k.box(-10, c, (y + LOW) + h / 2 + 0.0, 28, 8 / n, h, i % 2 == 0 and TIMBER or SLAT)
    if i % 3 == 1 then -- cushions where people sit
      for s = -22, 2, 6 do k.box(s, c, top + 0.08, 1.4, 0.5, 0.16, ({AMK, {0.95, 0.72, 0.18}, {0.2, 0.62, 0.62}})[1 + (s + i) % 3]) end
    end
  end
  local ramp = k.slope(-10, 28, 9, 17, y, y + LOW, 0.4, TIMBER, true)
  k.parts[#k.parts] = nil -- the ramp's only to walk on (the steps are what you see)
  ramp.tag = "ground"
  -- the drop at the hackathon floor's edge and the foyer's: a glass rail
  k.box(4.1, 19, y + 0.55, 0.1, 20, 1.1, GLASS, true, 0.2)
  k.box(4.1, 19, y + 1.1, 0.12, 20, 0.06, DARK)
  -- under the hackathon floor's edge, the drop's wall
  k.box(4.0, 23, y + LOW / 2, 0.4, 12, -LOW, CONC, true)
  -- walls: concrete below, slatted timber, all the way to the roof
  local wy, wh = y + (LOW + ROOF) / 2, ROOF - LOW + 1
  k.box(0, 0.75, wy, 49, 0.5, wh, CONC, true)
  k.box(0, 29.25, wy, 49, 0.5, wh, CONC, true)
  k.box(-24.25, 15, wy, 0.5, 29, wh, CONC, true)
  k.box(24.25, 15, wy, 0.5, 29, wh, CONC, true)
  for s = -23, 23, 0.6 do k.box(s, 28.95, y + LOW + 2.2, 0.25, 0.12, 4.4, SLAT) end
  -- the way out: daylight in the door
  k.box(M.DOOR.a, 1.02, y + 1.25, 2.4, 0.04, 2.5, {0.85, 0.9, 0.95}, false, 1)
  k.text(M.DOOR.a, 1.1, y + 3.0, "+c", "JOUKAHAISENKATU", 0.3, DARK)
  -- galleries round the atrium every floor, glass in front, and the wooden
  -- dice jutting out of them
  local fl = 0
  for gy = y + GALLERY, y + ROOF - 3, GALLERY do
    fl = fl + 1
    k.box(0, 3.0, gy, 48, 4.5, 0.45, CONC)           -- over the foyer
    k.box(0, 27.0, gy, 48, 4.5, 0.45, CONC)
    k.box(-22.0, 15, gy, 4.5, 19.5, 0.45, CONC)
    k.box(22.0, 15, gy, 4.5, 19.5, 0.45, CONC)
    k.box(0, 5.3, gy + 0.75, 39, 0.06, 1.1, GLASS, false, 0.15)
    k.box(0, 24.7, gy + 0.75, 39, 0.06, 1.1, GLASS, false, 0.15)
    -- people along the galleries' windows, lit at night: the floors are busy
    for s = -20, 20, 5 do k.box(s, 28.9, gy + 1.6, 3.2, 0.05, 1.8, {0.95, 0.9, 0.75}, false, 0.6) end
  end
  for i, d in ipairs{{-14, 5, 1}, {8, 5, 2}, {-4, 25, 1}, {16, 25, 3}, {-19.5, 12, 3}, {19.5, 20, 2}, {2, 5, 4}, {-12, 25, 4}} do
    local a, c, f = d[1], d[2], d[3]
    local out = c < 15 and 1.6 or -1.6
    if math.abs(a) > 19 then out = 0 end
    k.box(a + (a > 19 and -1.6 or a < -19 and 1.6 or 0), c + out, y + f * GALLERY + 1.6, 3.2, 3.2, 3.0,
          i % 2 == 0 and TIMBER or SLAT)
    k.box(a + (a > 19 and -1.6 or a < -19 and 1.6 or 0), c + out * 1.5, y + f * GALLERY + 1.6, 1.6, 0.06, 1.4, GLASS, false, 0.3)
  end
  -- the skylight: printed glass in a grid of beams
  k.box(0, 15, y + ROOF + 0.4, 49, 29, 0.2, {0.92, 0.95, 0.98}, false, 0.7)
  for s = -21, 21, 6 do k.box(s, 15, y + ROOF + 0.1, 0.4, 29, 0.6, WHITE) end
  for c = 3, 27, 6 do k.box(0, c, y + ROOF + 0.1, 49, 0.4, 0.6, WHITE) end

  -- the foyer café (by the door, to the left) and the restaurant (down the stairs)
  k.box(-15, 3.2, y + 0.55, 7, 1.2, 1.1, SLAT, true)
  k.box(-15, 3.2, y + 1.15, 7.2, 1.4, 0.08, WHITE)
  k.box(-17, 2.0, y + 1.35, 0.6, 0.4, 0.4, {0.2, 0.2, 0.22})            -- the coffee machine
  k.box(-15, 1.05, y + 2.6, 6, 0.06, 0.6, DARK)
  k.text(-15, 1.1, y + 2.6, "+c", "KAMPUSKAHVILA", 0.34, {0.95, 0.72, 0.18}, 0.6)
  M.shops[1] = {name = "KAMPUSKAHVILA", item = "KAHVI JA PULLA", price = 3, heal = 20, a = -15, c = 4.6, y = y}
  k.box(-10, 27.6, y + LOW + 0.55, 14, 1.2, 1.1, CONC, true)
  k.box(-10, 27.6, y + LOW + 1.15, 14.2, 1.4, 0.08, {0.4, 0.42, 0.44})
  for s = -15, -5, 2.5 do k.box(s, 27.6, y + LOW + 1.3, 1.6, 0.8, 0.2, ({{0.85, 0.5, 0.2}, {0.4, 0.65, 0.3}, {0.9, 0.85, 0.7}})[1 + math.floor(s) % 3]) end
  k.box(-10, 28.9, y + LOW + 3.0, 10, 0.06, 0.7, DARK)
  k.text(-10, 28.85, y + LOW + 3.0, "-c", "RAVINTOLA - LOUNAS", 0.36, WHITE, 0.6)
  M.shops[2] = {name = "RAVINTOLA", item = "PÄIVÄN LOUNAS", price = 9, heal = 60, a = -10, c = 26.0, y = y + LOW}
  -- the restaurant's tables
  for a = -21, 1, 5.5 do
    for c = 19.5, 23.5, 4 do
      k.box(a, c, y + LOW + 0.72, 3.6, 1.0, 0.06, WHITE)
      k.box(a, c, y + LOW + 0.36, 0.2, 0.2, 0.72, DARK)
    end
  end

  -- the hackathon: long tables of laptops, a big screen, pizza and drinks
  local SCREEN = {0.25, 0.75, 0.95}
  for row = 0, 3 do
    local c = 12 + row * 4.2
    k.box(14, c, y + 0.74, 16, 1.4, 0.06, WHITE, true)
    for _, s in ipairs{7, 21} do k.box(s, c, y + 0.37, 0.1, 1.2, 0.74, DARK) end
    for s = 7.5, 20.5, 1.6 do
      for _, side in ipairs{-1, 1} do
        k.box(s, c + side * 0.3, y + 0.79, 0.34, 0.24, 0.02, {0.7, 0.72, 0.74})         -- the laptop
        k.box(s, c + side * 0.42, y + 0.92, 0.34, 0.02, 0.24,
              (row + math.floor(s)) % 4 == 0 and {0.1, 0.1, 0.12} or SCREEN, false, 0.9) -- its screen
      end
    end
    -- cans and a pizza box or two
    k.box(9 + row * 2.5, c, y + 0.83, 0.08, 0.08, 0.13, {0.15, 0.6, 0.25})
    k.box(16 + row, c + 0.1, y + 0.8, 0.45, 0.45, 0.05, {0.85, 0.75, 0.55})
  end
  k.box(23.9, 19, y + 4.0, 0.15, 9, 4.5, {0.05, 0.06, 0.08})                 -- the big screen
  k.box(23.8, 19, y + 4.0, 0.05, 8.6, 4.1, {0.08, 0.15, 0.3}, false, 0.8)
  k.text(23.75, 19, y + 5.0, "-a", "HACKATHON", 0.9, WHITE, 1)
  k.text(23.75, 19, y + 3.6, "-a", "24 H - TURUN AMK", 0.45, SCREEN, 1)
  k.box(22.6, 10.5, y + 0.9, 0.7, 2.4, 1.8, {0.85, 0.85, 0.87}, true)         -- drinks fridge
  k.box(22.24, 10.5, y + 1.0, 0.04, 2.0, 1.4, {0.2, 0.55, 0.35}, false, 0.6)
  k.box(21.0, 25.5, y + 0.6, 2.2, 1.0, 0.06, WHITE, true)                      -- the pizza table
  for p = 0, 4 do k.box(21.0, 25.5, y + 0.66 + p * 0.06, 0.48, 0.48, 0.05, {0.88, 0.78, 0.58}) end
  M.shops[3] = {name = "HACKATHON", item = "PIZZA JA ENERGIAJUOMA", price = 0, heal = 25, a = 20.5, c = 24.0, y = y}

  spawn("educity_inside", k, LAYER)
  -- people: at the laptops, on the stairs, at lunch
  local n = 0
  local function ped(a, c, py, yaw)
    n = n + 1
    local x, z = xz(a, c)
    engine.spawn{mesh = "ped" .. (1 + n % 9), pos = {x, py + 0.9, z}, yaw = yaw, size = {0.7, 1.8, 0.7},
                 layer = LAYER, tag = "ped"}
  end
  for row = 0, 3 do
    for s = 8.3, 20, 3.2 do ped(s, 12 + row * 4.2 + ((s + row) % 2 < 1 and -1.0 or 1.0), y - 0.3, (s + row) % 2 < 1 and yaw_c or yaw_c + math.pi) end
  end
  for _, p in ipairs{{-20, 13.3}, {-14, 10.7}, {-6, 14.0}, {-1, 11.3}} do
    ped(p[1], p[2], y + LOW * (p[2] - 9) / 8 - 0.2, yaw_c + math.pi)
  end
  for _, a in ipairs{-21, -15.5, -4.5} do ped(a, 18.6, y + LOW, yaw_c) end
  ped(-15, 2.0, y, yaw_c)        -- the barista
  ped(-10, 28.4, y + LOW, yaw_c + math.pi) -- at the lunch counter
  -- lights: few, big (the skylight carries the day)
  for _, l in ipairs{{-12, 5, 0}, {12, 5, 0}, {14, 18, 0}, {-10, 23, LOW}, {0, 15, ROOF - 4}} do
    local x, z = xz(l[1], l[2])
    engine.light{pos = {x, y + l[3] + 3.5, z}, color = {1.0, 0.95, 0.88}, intensity = 1.1, radius = 18, layer = LAYER}
  end
  for _, s in ipairs(M.shops) do s.x, s.z = xz(s.a, s.c) end
end

function M.build(map)
  if not map or map.id ~= "turku" or M.built then return end
  M.built = true
  local d = M.DOOR
  d.out_x, d.out_z = xz(d.a, d.c_out)
  d.in_x, d.in_z = xz(d.a, d.c_in)
  M.HF = U.ground(d.out_x, d.out_z)
  d.y = M.HF
  engine.synth("educity_coffee", {wave = "noise", freq = 900, freq_end = 300, dur = 0.18,
                                  attack = 0.01, release = 0.12, volume = 0.3, lowpass = 0.4})
  build_outside(M.HF)
  build_inside(M.HF)
end

-- Where the floor is at (a, c) inside, or nil off them.
function M.floor_at(a, c)
  for _, r in ipairs(M.AREAS) do
    if a >= r.a0 and a <= r.a1 and c >= r.c0 and c <= r.c1 then
      if r.stairs then return M.HF + LOW * (c - r.c0) / (r.c1 - r.c0) end
      return M.HF + r.y
    end
  end
end

local function through_door()
  if not G.player or G.vehicle or not engine.exists(G.player) then return end
  local px, py, pz = engine.pos(G.player)
  local d = M.DOOR
  local layer = engine.layer(G.player) or 0
  if layer == 0 then
    if U.dist2d(px, pz, d.out_x, d.out_z) < 1.6 and math.abs(py - d.y) < 2.5 then
      engine.play("door", {volume = 0.5})
      engine.set_pos(G.player, d.in_x, d.y + 0.9, d.in_z)
      engine.set_vel(G.player, 0, 0, 0)
      engine.set_layer(G.player, LAYER)
      engine.view_layer(LAYER)
      U.message("EDUCITY - TURUN AMK", 3)
      engine.emit("interior_enter", "educity")
      if wanted.stars() > 0 then
        wanted.seen = false
        wanted.hiding = true
      end
    end
  elseif layer == LAYER then
    local a, c = ac(px, pz)
    if math.abs(a - d.a) < 3 and c < 1.9 and c > -1 and math.abs(py - d.y) < 2.5 then
      engine.play("door", {volume = 0.5})
      engine.set_pos(G.player, d.out_x, d.y + 0.9, d.out_z)
      engine.set_vel(G.player, 0, 0, 0)
      engine.set_layer(G.player, 0)
      engine.view_layer(0)
      wanted.hiding = nil
      engine.emit("interior_exit", "educity")
    end
  end
end

function M.inside(id)
  id = id or G.player
  if not id or not engine.exists(id) or (engine.layer(id) or 0) ~= LAYER then return false end
  local x, _, z = engine.pos(id)
  local a, c = ac(x, z)
  return a > -25 and a < 25 and c > 0 and c < 30
end

function M.current_shop()
  if not M.inside() then return end
  local px, py, pz = engine.pos(G.player)
  for _, s in ipairs(M.shops) do
    if U.dist2d(px, pz, s.x, s.z) < 2.2 and math.abs(py - s.y) < 2.5 then return s end
  end
end

local function buy(s)
  if G.cash < s.price then
    U.message(string.format("TARVITSET $%d", s.price), 2)
    engine.play("click", {ui = true})
    return
  end
  G.cash = G.cash - s.price
  health.heal_player(s.heal)
  engine.play("buy", {ui = true})
  engine.play("educity_coffee", {volume = 0.4})
  U.message(string.format("+%d HP: %s%s", s.heal, s.item, s.price > 0 and string.format(" (-$%d)", s.price) or " (hackathonin tarjoama)"), 3)
  if s.price > 0 then engine.emit("purchase", s.price) end
end

engine.on("key", function(k, down)
  if not down or (k ~= "r" and k ~= "e") then return end
  local s = M.current_shop()
  if s then buy(s) end
end)

engine.on("tick", function(dt)
  if not M.built then return end
  through_door()
  if wanted.stars() > 0 and M.inside() then
    local x, z = xz(0, 15)
    wanted.unseen(dt * 1.5, x, z)
  end
end)

engine.on("frame", function()
  local s = M.current_shop()
  if not s then return end
  local prompt = s.price > 0 and string.format("R: %s - %s ($%d, +%d HP)", s.name, s.item, s.price, s.heal)
                 or string.format("R: %s - %s (ilmainen, +%d HP)", s.name, s.item, s.heal)
  local w, h = engine.screen()
  local tw = engine.text_width(prompt, 18)
  engine.rect((w - tw) / 2 - 12, h - 135, tw + 24, 30, 0, 0, 0, 0.75)
  engine.text(prompt, (w - tw) / 2, h - 129, 18, 0.95, 0.85, 0.4, 1.0)
end)

engine.on("minimap", function(map_fn)
  if not M.built then return end
  local x, z = xz(0, 15)
  local mx, my = map_fn(x, z)
  engine.rect(mx - 4, my - 4, 8, 8, AMK[1], AMK[2], AMK[3], 1)
  engine.text("E", mx + 6, my - 6, 10, AMK[1], AMK[2], AMK[3], 1)
end)

return M
