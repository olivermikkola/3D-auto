-- Toriparkki, the car park under Kauppatori's east half (docs/UNDERGROUND.md,
-- piece 5), joined to Louhi: drive on from Louhi's hall through its east
-- end, or in down Toriparkki's own ramp from the street. Layer 1, laid out
-- in Louhi's hall frame (systems/louhi: along, across), which it's squared
-- to as Hansa is.
--
-- From OpenStreetMap: the car park (way 1207799675, level -2, 620 places,
-- 3 m high): a 120 x 123 m body, along 19.5..139 and across 48..171, and an
-- arm out to the ramp, along 112..156, across 33.6..48; the ramp (way
-- 1035382220, "incline down", retaining walls either side, way 1128206551)
-- up from 156 to the street at 208 along, 37.5 across. The link to Louhi
-- is the game's.
local G = require "lib.state"
local U = require "lib.util"

local M = {}

local Y, H = 2.0, 4.0 -- the floor (Louhi's), its height (the real one is 3)
local L1 = {a0 = 97.65, a1 = 121, c0 = 1.5, c1 = 12}    -- out of Louhi's east end
local L2 = {a0 = 109, a1 = 121, c0 = 12, c1 = 33.6}   -- round into the arm
local ARM = {a0 = 109, a1 = 156, c0 = 33.6, c1 = 48}
local BODY = {a0 = 19.5, a1 = 139, c0 = 48, c1 = 171}
local RAMP = {a0 = 156, a1 = 217, c0 = 33.7, c1 = 41.2}
local MOUTH, RAMP_FOOT = 203, 160 -- the portal's face; where the ramp's down
-- Aisles down the body (across), between rows of bays; across them at each
-- end (along).
M.AISLES = {51.75}
for m = 0, 6 do M.AISLES[#M.AISLES + 1] = 63.75 + 16.5 * m end
M.CROSS = {24.5, 134}

local function inside(r, a, c, m) m = m or 0; return a > r.a0 - m and a < r.a1 + m and c > r.c0 - m and c < r.c1 + m end

function M.plan(Lh)
  M.Lh = Lh
  local mid = (RAMP.c0 + RAMP.c1) / 2
  local ys = U.ground(Lh.hall_xz(MOUTH + 3, mid))
  M.ys = ys
  local A = Lh.AREAS
  for _, r in ipairs{L1, L2, ARM, BODY} do A[#A + 1] = {a0 = r.a0, a1 = r.a1, c0 = r.c0, c1 = r.c1, y0 = Y} end
  A[#A + 1] = {a0 = RAMP.a0, a1 = RAMP_FOOT, c0 = RAMP.c0, c1 = RAMP.c1, y0 = Y}
  A[#A + 1] = {a0 = RAMP_FOOT, a1 = MOUTH, c0 = RAMP.c0, c1 = RAMP.c1, y0 = Y, y1 = ys, axis = "along"}
  A[#A + 1] = {a0 = MOUTH, a1 = RAMP.a1, c0 = RAMP.c0, c1 = RAMP.c1, y0 = ys}
  Lh.GAPS.east[#Lh.GAPS.east + 1] = {L1.c0, L1.c1}

  -- The way in from the street.
  local P = {axis = "along", at = MOUTH, out = 1, c = mid, w = RAMP.c1 - RAMP.c0, ys = ys, order = 5, outside = {MOUTH + 7, mid},
             name = "Toriparkki"}
  -- Up top, after you down here: by the roads to the street outside, then in.
  function P.approach(x, z)
    local a, c = Lh.hall_ab(x, z)
    local ox, oz = Lh.hall_xz(P.outside[1], P.outside[2])
    if U.dist2d(x, z, ox, oz) > 45 then return "goal", ox, ys, oz end
    if a > MOUTH + 3 and math.abs(c - mid) > 1.2 then return "steer", ox, oz, 8 end
    local tx, tz = Lh.hall_xz(math.min(a, MOUTH + 6) - 12, mid)
    return "steer", tx, tz, 10
  end
  Lh.PORTALS[#Lh.PORTALS + 1] = P
  M.portal = P

  -- Cops down here (systems/louhi, chase): Louhi's hall, the link, here.
  Lh.ORDER.link, Lh.ORDER.tori = 3, 4
  Lh.ZONES[#Lh.ZONES + 1] = function(x, z)
    local a, c = Lh.hall_ab(x, z)
    if inside(L1, a, c, 0.5) or inside(L2, a, c, 0.5) then return "link" end
    if inside(ARM, a, c, 0.5) or inside(BODY, a, c, 0.5) or inside(RAMP, a, c, 1) then return "tori" end
    return nil
  end
  local function to(a, c, sp) local x, z = Lh.hall_xz(a, c); return x, z, sp end
  function Lh.HALL_ON(x, z)
    local a = Lh.hall_ab(x, z)
    if a < 84 then return to(90, 6.5, 10) end
    return to(110, 6.5, 10)
  end
  Lh.LEAVE.link = function(x, z, way)
    local a, c = Lh.hall_ab(x, z)
    if way > 0 then
      if a < 112 then return to(115, 6.5, 10) end
      return to(115, 42, 10)
    end
    if c > 12.5 then return to(115, 5, 10) end
    return to(88, 6.5, 10)
  end
  Lh.LEAVE.tori = function(x, z, way)
    local a, c = Lh.hall_ab(x, z)
    if way > 0 then
      if a > 140 and math.abs(c - mid) < 3 then return to(MOUTH + 12, mid, 12) end
      local ta, tc = M.nav(a, c, 150, mid)
      return to(ta, tc, 10)
    end
    if U.dist2d(a, c, 115, 42) < 5 then return to(115, 20, 10) end
    local ta, tc = M.nav(a, c, 115, 42)
    return to(ta, tc, 10)
  end
  Lh.WITHIN.tori = function(x, z, px, pz)
    local a, c = Lh.hall_ab(x, z)
    local ta, tc = M.nav(a, c, Lh.hall_ab(px, pz))
    return to(ta, tc, 10)
  end
end

-- Driving round the body: from (a, c) toward (ta, tc), the next point to
-- make for, keeping to the aisles (the bays between them are full of cars
-- and pillars). The arm and the ramp are open.
local function corridor(a, c) return a > BODY.a1 or c < BODY.c0 end
local function aisle_of(c)
  local best, bd = M.AISLES[1], math.huge
  for _, ac in ipairs(M.AISLES) do
    if math.abs(ac - c) < bd then best, bd = ac, math.abs(ac - c) end
  end
  return best
end
function M.nav(a, c, ta, tc)
  if corridor(a, c) and corridor(ta, tc) then return ta, tc end
  if corridor(a, c) then
    -- out of the arm into the first aisle, then on
    if c < BODY.c0 + 1 then return math.min(math.max(a, 116), 135), M.AISLES[1] + 1 end
    return M.nav(math.min(a, 135), M.AISLES[1], ta, tc)
  end
  if corridor(ta, tc) then
    if math.abs(c - M.AISLES[1]) < 3 or a > M.CROSS[2] - 5 then return 125, 42 end
    return M.nav(a, c, 125, M.AISLES[1])
  end
  local in_cross = a < M.CROSS[1] + 5 or a > M.CROSS[2] - 5
  if math.abs(c - tc) < 3.5 then return ta, tc end
  local row = aisle_of(tc)
  if in_cross then
    local ca = a < M.CROSS[1] + 5 and M.CROSS[1] or M.CROSS[2]
    if math.abs(c - row) < 2 then return ta, row end
    return ca, row
  end
  -- along this aisle to the end nearer the way there
  local best, bd
  for _, ca in ipairs(M.CROSS) do
    local d = math.abs(a - ca) + math.abs(ca - ta)
    if not bd or d < bd then best, bd = ca, d end
  end
  return best, aisle_of(c)
end

local CONC, CONC2, ASPHALT, LINE, PILLAR = {0.55, 0.55, 0.53}, {0.45, 0.45, 0.44}, {0.2, 0.2, 0.21}, {0.85, 0.85, 0.8}, {0.62, 0.6, 0.56}
local STRIP, BLUE, YELLOW = {1, 0.97, 0.9}, {0.1, 0.3, 0.75}, {0.95, 0.8, 0.1}

local function bake(Lh, name, k, o, layer)
  local baked = {}
  for i, p in ipairs(k.parts) do
    local q = {}
    for key, val in pairs(p) do if key ~= "floor" then q[key] = val end end
    q.pos = {p.pos[1] - o[1], p.pos[2] - o[2], p.pos[3] - o[3]}
    baked[i] = q
  end
  engine.mesh(name, baked)
  engine.spawn{mesh = name, pos = o, layer = layer, tag = "building"}
  for _, p in ipairs(k.solids) do
    engine.spawn{mesh = "cube", pos = p.pos, yaw = p.yaw, pitch = p.pitch, size = p.size, visible = false, body = "static",
                 tag = p.floor and "ground" or layer == 0 and "building" or "wall", layer = layer}
  end
end

function M.build(Lh)
  local k = Lh.kit()
  local box, slab = k.box, k.slab
  local ys = M.ys
  local mid = (RAMP.c0 + RAMP.c1) / 2
  local function floor(r) box((r.a0 + r.a1) / 2, (r.c0 + r.c1) / 2, Y - 0.5, r.a1 - r.a0 + 1, r.c1 - r.c0 + 1, 1, ASPHALT, true).floor = true end
  local function ceiling(r) box((r.a0 + r.a1) / 2, (r.c0 + r.c1) / 2, Y + H + 0.25, r.a1 - r.a0 + 1, r.c1 - r.c0 + 1, 0.5, CONC2, true) end
  local function wall_a(a0, a1, c, h, y) y = y or Y; h = h or H; box((a0 + a1) / 2, c, y + h / 2, a1 - a0, 0.5, h, CONC, true) end
  local function wall_c(c0, c1, a, h, y) y = y or Y; h = h or H; box(a, (c0 + c1) / 2, y + h / 2, 0.5, c1 - c0, h, CONC2, true) end

  -- The link from Louhi, and the arm.
  for _, r in ipairs{L1, L2, ARM, BODY} do floor(r); ceiling(r) end
  wall_a(L1.a0 - 0.25, L1.a1 + 0.5, L1.c0 - 0.25)
  wall_a(L1.a0 - 0.25, L2.a0, L1.c1 + 0.25)
  wall_c(L1.c0 - 0.5, L2.c1, L1.a1 + 0.25)
  wall_c(L1.c1, L2.c1, L2.a0 - 0.25)
  box((L1.a0 + L1.a1) / 2, (L1.c0 + L1.c1) / 2, Y + H - 0.03, L1.a1 - L1.a0 - 2, 0.3, 0.06, STRIP, false, 1)
  box((L2.a0 + L2.a1) / 2, (L2.c0 + L2.c1) / 2, Y + H - 0.03, 0.3, L2.c1 - L2.c0 - 2, 0.06, STRIP, false, 1)
  -- the arm: its west end, its sides, its east end beside the ramp
  wall_c(ARM.c0, ARM.c1, ARM.a0 - 0.25)
  wall_a(L2.a1, RAMP.a0, ARM.c0 - 0.25)
  wall_a(BODY.a1, ARM.a1 + 0.5, ARM.c1 + 0.25)
  wall_c(RAMP.c1, ARM.c1 + 0.5, ARM.a1 + 0.25)

  -- The body: its walls (the near one open to the arm), bays in rows down
  -- the aisles, pillars between the rows, lit strips over the aisles.
  wall_c(BODY.c0, BODY.c1 + 0.5, BODY.a0 - 0.25)
  wall_c(BODY.c0, BODY.c1 + 0.5, BODY.a1 + 0.25)
  wall_a(BODY.a0 - 0.5, BODY.a1 + 0.5, BODY.c1 + 0.25)
  wall_a(BODY.a0 - 0.5, ARM.a0, BODY.c0 - 0.25)
  local bays = {}
  for m = 0, 6 do
    local base = 55.5 + 16.5 * m
    for _, row in ipairs{{base + 2.5, -1}, {base + 14, 1}} do
      for a = M.CROSS[1] + 6, M.CROSS[2] - 6, 2.5 do
        bays[#bays + 1] = {along = a, across = row[1], nose = row[2]}
        box(a - 1.25, row[1], Y + 0.01, 0.1, 5, 0.02, LINE)
      end
    end
    if m < 6 then
      for a = M.CROSS[1] + 8, M.CROSS[2] - 8, 8 do box(a, base + 16.5, Y + H / 2, 0.6, 0.6, H, PILLAR, true) end
    end
  end
  for _, ac in ipairs(M.AISLES) do
    for a = BODY.a0 + 6, BODY.a1 - 6, 12 do box(a, ac, Y + H - 0.03, 4, 0.3, 0.06, STRIP, false, 1) end
  end

  -- The ramp: flat at the foot, up to the street at the mouth, flat on out
  -- past it (where you come down from the street).
  local function ramp_run(a0, a1, y0, y1, ...) return slab(a0, a1, y0, y1, mid, ...) end
  ramp_run(RAMP.a0, RAMP_FOOT, Y, Y, RAMP.c1 - RAMP.c0 + 1, 1, ASPHALT, true).floor = true
  ramp_run(RAMP_FOOT, MOUTH, Y, ys, RAMP.c1 - RAMP.c0 + 1, 1, ASPHALT, true).floor = true
  ramp_run(MOUTH, RAMP.a1, ys, ys, RAMP.c1 - RAMP.c0 + 1, 1, ASPHALT, true).floor = true
  for _, r in ipairs{{RAMP.a0, RAMP_FOOT, Y, Y}, {RAMP_FOOT, MOUTH, Y, ys}, {MOUTH, RAMP.a1, ys, ys}} do
    ramp_run(r[1], r[2], r[3] + H + 0.5, r[4] + H + 0.5, RAMP.c1 - RAMP.c0 + 1.5, 0.5, CONC2, true)
    ramp_run(r[1], r[2], r[3] + H - 0.02, r[4] + H - 0.02, 0.3, 0.06, STRIP, false, 1)
    slab(r[1], r[2], r[3] + H, r[4] + H, RAMP.c1 + 0.25, 0.5, H, CONC2, true)
    slab(r[1], r[2], r[3] + H, r[4] + H, RAMP.c0 - 0.25, 0.5, H, CONC, true)
  end
  -- the way out, bright: daylight at the mouth
  box(MOUTH + 0.6, mid, ys + H / 2, 0.05, RAMP.c1 - RAMP.c0, H, {0.85, 0.88, 0.9}, false, 1)

  -- Signs: in Louhi over the way through, here over the way back, and the
  -- way out.
  box(L1.a0 - 0.3, (L1.c0 + L1.c1) / 2, Y + 3.2, 0.04, 7, 0.55, BLUE)
  k.text(L1.a0 - 0.33, (L1.c0 + L1.c1) / 2, Y + 3.2, "-a", "TORIPARKKI", 0.34, nil, 0.4)
  box((L2.a0 + L2.a1) / 2, L2.c1 + 0.3, Y + 3.2, 7, 0.04, 0.55, BLUE)
  k.text((L2.a0 + L2.a1) / 2, L2.c1 + 0.33, Y + 3.2, "+c", "LOUHI", 0.34, nil, 0.4)
  box(RAMP_FOOT - 2, mid, Y + 3.4, 0.04, 4, 0.5, {0.1, 0.55, 0.25})
  k.text(RAMP_FOOT - 2.03, mid, Y + 3.4, "-a", "ULOS", 0.32, nil, 0.4)

  local ox, oz = Lh.hall_xz(80, 110)
  bake(Lh, "toriparkki", k, {ox, Y, oz}, Lh.LAYER)

  -- Lamps (the nearest 16 lit): over the aisles, the link, the ramp.
  local function lamp(a, c, y)
    local x, z = Lh.hall_xz(a, c)
    engine.light{pos = {x, y or Y + H - 0.3, z}, color = {0.95, 1, 0.95}, intensity = 1.2, radius = 20, layer = Lh.LAYER}
  end
  for _, ac in ipairs(M.AISLES) do
    for a = BODY.a0 + 12, BODY.a1 - 6, 24 do lamp(a, ac) end
  end
  lamp(108, 6.5)
  lamp(115, 22)
  lamp(135, 41)
  for _, a in ipairs{150, 168, 186, 200} do
    local f = a <= RAMP_FOOT and Y or Y + (ys - Y) * (a - RAMP_FOOT) / (MOUTH - RAMP_FOOT)
    lamp(a, mid, f + H - 0.3)
  end

  -- Parked cars in a tenth of the bays, the same ones every time. Static
  -- until you get in one or shove it (systems/parking): dozens of resting
  -- car bodies slowed the whole game down by a sixth.
  local parking = require "systems.parking"
  local s = 11
  M.cars = {}
  local bx, bz = Lh.hall_xz(0, 1)
  local cx0, cz0 = Lh.hall_xz(0, 0)
  bx, bz = bx - cx0, bz - cz0
  for _, b in ipairs(bays) do
    s = (s * 1103515245 + 12345) % 2147483648
    if s % 10 == 0 then
      local x, z = Lh.hall_xz(b.along, b.across)
      M.cars[#M.cars + 1] = parking.park_at(x, Y, z, math.atan(bx * b.nose, bz * b.nose), 1 + s % 8, Lh.LAYER)
    end
  end
  M.bays = bays

  -- Up top: the ramp's mouth, covered over back to where it goes under
  -- the square: its face, TORIPARKKI and 3,0 m over it, solid from 6 m in.
  local t = Lh.kit()
  local tb = t.box
  local w = RAMP.c1 - RAMP.c0
  local roof = ys + 3.6
  tb(MOUTH + 0.25, RAMP.c0 - 0.5, ys + 1.8, 0.5, 1, 3.6, CONC, false)
  tb(MOUTH + 0.25, RAMP.c1 + 0.5, ys + 1.8, 0.5, 1, 3.6, CONC, false)
  tb(MOUTH + 0.25, mid, ys + 3.3, 0.5, w, 0.6, CONC, false)
  tb((RAMP.a0 + MOUTH) / 2, mid, roof + 0.2, MOUTH - RAMP.a0 + 0.5, w + 2, 0.4, CONC2, false)
  for _, c in ipairs{RAMP.c0 - 0.5, RAMP.c1 + 0.5} do
    tb((RAMP.a0 + MOUTH) / 2, c, ys + 1.8, MOUTH - RAMP.a0, 1, 3.6, CONC2, false)
  end
  tb(MOUTH - 1.5, mid, ys + 1.5, 0.1, w, 3, {0.05, 0.05, 0.06}, false) -- dark inside
  tb(MOUTH - 0.2, mid, ys + 2.85, 0.4, w - 0.4, 0.08, {1, 0.92, 0.75}, false, 0.8)
  tb(MOUTH + 0.52, mid, ys + 4.1, 0.06, 5, 0.8, {0.12, 0.13, 0.15})
  t.text(MOUTH + 0.55, mid, ys + 4.1, "+a", "TORIPARKKI", 0.55, {0.95, 0.95, 0.92}, 0.6)
  for i = -3, 3 do tb(MOUTH + 4, mid + i * 1.05, ys + 3.15, 0.3, 1.05, 0.3, i % 2 == 0 and YELLOW or {0.08, 0.08, 0.08}) end
  for _, side in ipairs{-1, 1} do tb(MOUTH + 4, mid + side * (w / 2 + 0.3), ys + 1.6, 0.2, 0.2, 3.2, {0.3, 0.3, 0.32}) end
  t.text(MOUTH + 4.18, mid, ys + 3.15, "+a", "3,0 m", 0.2, {0.08, 0.08, 0.08})
  -- (what you hit up top: from 6 m in, all of it; the sides out to the face.
  -- A car's well past the face, and down in layer 1, before its nose gets there.)
  local solid = {}
  local function s_box(a, c, cy, l, ww, h)
    local x, z = Lh.hall_xz(a, c)
    solid[#solid + 1] = {pos = {x, cy, z}, yaw = math.atan(Lh.HALL.a[1], Lh.HALL.a[2]), size = {ww, h, l}}
  end
  s_box((RAMP.a0 + MOUTH - 6) / 2, mid, ys + 1.5, MOUTH - 6 - RAMP.a0, w, 5) -- (as wide as the ramp under it, no more)
  for _, c in ipairs{RAMP.c0 - 0.5, RAMP.c1 + 0.5} do s_box(MOUTH - 3, c, ys + 1.8, 6.5, 1, 3.6) end
  local px, pz = Lh.hall_xz(MOUTH, mid)
  local tp = {parts = t.parts, solids = {}}
  bake(Lh, "toriparkki_mouth", tp, {px, ys, pz}, 0)
  for _, p in ipairs(solid) do
    engine.spawn{mesh = "cube", pos = p.pos, yaw = p.yaw, size = p.size, visible = false, body = "static", tag = "building"}
  end
end

return M
