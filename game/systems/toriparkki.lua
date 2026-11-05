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
M.CROSS = {27.5, 134} -- (the west one's middle clear of the stairs down from pavilion A)
local BAYS_FROM, BAYS_TO = 30.5, 128

local plan_cores
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
  -- (The roads take a cop to the junction nearest the way in, but it may
  -- be a dead end the cop can't get to from where it is: Yliopistonkatu's
  -- end at the mouth is one, reached only from Aurakatu's far side; from the
  -- other end its drivable bit stops 66 m off at another, the walking street
  -- between. Cops there searched round it and never came in. From the next
  -- junction out, they steer, down the walking street if that's the way.)
  local city = require "lib.city"
  local ox, oz = Lh.hall_xz(P.outside[1], P.outside[2])
  local near = 45
  if city.network() then
    local best = math.huge
    for _, id in ipairs(city.junctions()) do
      local jx, jz = city.pos(id)
      local d = U.dist2d(ox, oz, jx, jz)
      if d > 5 and d < best then best = d end
    end
    if best < 75 then near = math.max(near, best + 10) end
  end
  print(string.format("toriparkki: cops steer in from %.0f m out", near))
  function P.approach(x, z)
    local a, c = Lh.hall_ab(x, z)
    if U.dist2d(x, z, ox, oz) > near then return "goal", ox, ys, oz end
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
  plan_cores(Lh)
end

-- ---- on foot: the stairs down from the pavilions (Oliver's map, OSM) ------------
-- Three of the square's pavilions (systems/kauppatori) have Toriparkki's
-- stairs in them, their doors where OpenStreetMap has them (nodes
-- 9535109001 "A", 9376767483 "B", 9164387452 "C", each on the side toward
-- the middle of the square). Each is a walled box 2.9 m wide behind its
-- door: a landing at the square's height, a flight down, a landing at the
-- bottom open to the car park. The square's ground is about as high as the
-- car park's ceiling, so the boxes stand where they take least room: A in
-- the west end's cross aisle against the door side, B and C in bays.
--   unit, OSM entrance (along, across), the pavilion, which way out of the
--   bottom: "front" (the door's side) or "back".
M.UNITS = {
  {unit = "A", at = {22.9, 89.2}, pav = "Aurakadun toripaviljonki", exit = "front", street = "KAUPPATORI"},
  {unit = "B", at = {55.7, 155.3}, pav = "Eerikinkadun toripaviljonki", exit = "back", street = "KAUPPATORI"},
  {unit = "C", at = {126.6, 99.8}, pav = "Kauppiaskadun toripaviljonki", exit = "back", street = "KAUPPATORI"},
  -- The ways under the streets (Oliver's map; OSM's layer -1 stubs where
  -- they leave the car park, ways 1443872641 and 1443872644): to Forum's
  -- staircase door on Eerikinkatu (node 4765209338) and Wiklund's door on
  -- Kauppiaskatu (node 5222924302), each down its own stairs at the far end.
  {unit = "FORUM", at = {35, 194}, exit = "front", dir = -1, street = "EERIKINKATU", sign = "FORUM  KOP-KOLMIO"},
  {unit = "WIKLUND", at = {158, 137}, exit = "front", street = "KAUPPIASKATU", sign = "WIKLUND",
   shops = {{"PRISMA", "-"}, {"ALKO", "+"}}},
}
M.CORES = {}
M.WALKS = {}       -- the corridors under the streets: {r = rect, axis, y0, y1}
M.BODY_GAPS = {west = {}, east = {}, south = {}}
local CORE_W, LAND, BOTTOM, TREAD, RISE = 2.9, 2.4, 3.0, 0.29, 0.17

-- A building's walls in the hall's frame: OpenStreetMap's footprint (the
-- map's), by name, or the one at (a, c).
local function footprint_rect(Lh, name, at)
  for _, f in ipairs(Lh.map and Lh.map.footprints or {}) do
    local a, c = Lh.hall_ab(f[1], f[2])
    local fx, fz = math.sin(f[5]), math.cos(f[5])
    local z_along = math.abs(fx * Lh.HALL.a[1] + fz * Lh.HALL.a[2]) > 0.7
    local ha, hc = (z_along and f[4] or f[3]) / 2, (z_along and f[3] or f[4]) / 2
    local R = {a0 = a - ha, a1 = a + ha, c0 = c - hc, c1 = c + hc}
    if name and f[8] == name then return R end
    if not name and inside(R, at[1], at[2], 1.5) then return R end
  end
end

function plan_cores(Lh)
  for _, u in ipairs(M.UNITS) do
    local R = footprint_rect(Lh, u.pav, u.at)
    if R then
      -- the door: in the face nearest OSM's entrance
      local ea, ec = u.at[1], u.at[2]
      local faces = {{"along", R.a0, -1, math.abs(ea - R.a0)}, {"along", R.a1, 1, math.abs(ea - R.a1)},
                     {"across", R.c0, -1, math.abs(ec - R.c0)}, {"across", R.c1, 1, math.abs(ec - R.c1)}}
      table.sort(faces, function(p, q) return p[4] < q[4] end)
      local f = faces[1]
      local d = {axis = f[1], at = f[2], out = f[3], c = f[1] == "along" and ec or ea, name = "Toriparkki " .. u.unit}
      -- (outside a pavilion, the square's paving, 0.6 m thick: systems/kauppatori)
      local ys = U.ground(Lh.door_xz(d, 1, 0)) + (u.pav and 0.6 or 0)
      d.ys = ys
      -- The box: across its width from the door face in; along its length
      -- (s) from the landing at the door to the bottom, `dir` the way it goes.
      local dir = u.dir or 1
      local n = math.max(2, math.ceil((ys - Y) / RISE))
      local s0 = d.c - dir * 1.2
      local C = {unit = u.unit, u = u, pavilion = u.pav ~= nil, door = d, n = n, ys = ys, dir = dir,
                 w0 = math.min(d.at, d.at - d.out * CORE_W), w1 = math.max(d.at, d.at - d.out * CORE_W),
                 s0 = s0, top = s0 + dir * LAND, exit = u.exit}
      C.foot = C.top + dir * n * TREAD
      C.s1 = C.foot + dir * BOTTOM
      -- (s, w) to (along, across), and a rectangle of it
      local function ac(sv, wv) if d.axis == "along" then return wv, sv end return sv, wv end
      C.ac = ac
      function C.rect(sa, sb, wa, wb)
        local a0, c0 = ac(sa, wa)
        local a1, c1 = ac(sb, wb)
        return {a0 = math.min(a0, a1), a1 = math.max(a0, a1), c0 = math.min(c0, c1), c1 = math.max(c0, c1)}
      end
      C.R = C.rect(C.s0, C.s1, C.w0, C.w1)
      -- the way out of the bottom: the exit face, and outside it
      C.exit_w = (u.exit == "front") == (d.out > 0) and C.w1 or C.w0
      C.exit_out = C.exit_w == C.w1 and 1 or -1
      local A = Lh.AREAS
      local land, flight = C.rect(C.s0, C.top, C.w0, C.w1), C.rect(C.top, C.foot, C.w0, C.w1)
      A[#A + 1] = {a0 = land.a0, a1 = land.a1, c0 = land.c0, c1 = land.c1, y0 = ys}
      -- (area floors rise from a0 / c0: going the other way, the other way round)
      A[#A + 1] = {a0 = flight.a0, a1 = flight.a1, c0 = flight.c0, c1 = flight.c1, y0 = dir > 0 and ys or Y, y1 = dir > 0 and Y or ys,
                   axis = d.axis == "along" and "across" or "along"}
      local bottom = C.rect(C.foot, C.s1, C.w0, C.w1)
      A[#A + 1] = {a0 = bottom.a0, a1 = bottom.a1, c0 = bottom.c0, c1 = bottom.c1, y0 = Y}
      Lh.DOORS[#Lh.DOORS + 1] = d
      local wm = (C.w0 + C.w1) / 2
      local sm = (C.foot + C.s1) / 2
      C.sm = sm
      local pts = {}
      for _, q in ipairs{{sm, C.exit_w + C.exit_out * 3}, {sm, wm}, {C.foot - dir * 0.3, wm}, {C.top - dir * 0.3, wm}, {d.c, d.at - d.out * 0.5}} do
        local a, c = ac(q[1], q[2])
        pts[#pts + 1] = {a, c}
      end
      C.route = {pts = pts, w = CORE_W, door = d}
      Lh.ROUTES[#Lh.ROUTES + 1] = C.route
      M.CORES[#M.CORES + 1] = C
    end
  end
  -- The ways under the streets, from the bottoms of the far stairs to the
  -- car park's walls.
  for _, C in ipairs(M.CORES) do
    if not C.pavilion then
      local lo, hi = math.min(C.foot, C.s1), math.max(C.foot, C.s1)
      local r, mouth, into
      if C.door.axis == "along" then -- (Wiklund: east, along)
        r = {a0 = BODY.a1 + 0.25, a1 = C.exit_w, c0 = lo, c1 = hi}
        M.BODY_GAPS.east[#M.BODY_GAPS.east + 1] = {lo, hi}
        mouth, into = {BODY.a1 - 3, (lo + hi) / 2}, {BODY.a1 + 2, (lo + hi) / 2}
        M.WALKS[#M.WALKS + 1] = {r = r, axis = "along", y0 = Y, y1 = Y, C = C}
      else                            -- (Forum: south, across)
        r = {a0 = lo, a1 = hi, c0 = BODY.c1 + 0.25, c1 = C.exit_w}
        M.BODY_GAPS.south[#M.BODY_GAPS.south + 1] = {lo, hi}
        mouth, into = {(lo + hi) / 2, BODY.c1 - 3}, {(lo + hi) / 2, BODY.c1 + 2}
        M.WALKS[#M.WALKS + 1] = {r = r, axis = "across", y0 = Y, y1 = Y, C = C}
      end
      Lh.AREAS[#Lh.AREAS + 1] = {a0 = r.a0, a1 = r.a1, c0 = r.c0, c1 = r.c1, y0 = Y}
      table.insert(C.route.pts, 1, into)
      table.insert(C.route.pts, 1, mouth)
      C.mouth = mouth
    end
  end
  -- And to Hansa: west under Aurakatu at 106..110 across (OSM's stubs, ways
  -- 1443872639 / 1443872636), then north to Hansa's level -1 (systems/hansa,
  -- which leaves its wall open there).
  local hansa = require "systems.hansa"
  local HF = 2.2
  local H1 = {a0 = -39.5, a1 = BODY.a0 - 0.25, c0 = 106, c1 = 110}
  local H2 = {a0 = -43.5, a1 = -39.5, c0 = 70.25, c1 = 110}
  M.HANSA = {H1 = H1, H2 = H2, HF = HF}
  Lh.AREAS[#Lh.AREAS + 1] = {a0 = H1.a0, a1 = H1.a1, c0 = H1.c0, c1 = H1.c1, y0 = HF, y1 = Y, axis = "along"}
  Lh.AREAS[#Lh.AREAS + 1] = {a0 = H2.a0, a1 = H2.a1, c0 = H2.c0, c1 = H2.c1, y0 = HF}
  M.BODY_GAPS.west[#M.BODY_GAPS.west + 1] = {H1.c0, H1.c1}
  Lh.HANSA_LINK = {H2.a0, H2.a1}
  M.WALKS[#M.WALKS + 1] = {r = H1, axis = "along", y0 = HF, y1 = Y}
  M.WALKS[#M.WALKS + 1] = {r = H2, axis = "across", y0 = HF, y1 = HF, closed = "c1", open_a1 = {H1.c0, H1.c1}}
  if hansa.door then
    M.hansa_route = {pts = {{BODY.a0 + 3, 108}, {-41.5, 108}, {-41.5, 64}, {-48, 64}, {-48, hansa.top + 1}, {-48, 100.8}, {-9.6, 100.8}},
                     w = 3.5, door = hansa.door}
    Lh.ROUTES[#Lh.ROUTES + 1] = M.hansa_route
  end
end

-- Is (a, c) in a stair box (or the way out of its bottom), with a margin?
local function in_core(a, c, m)
  for _, C in ipairs(M.CORES) do
    if inside(C.R, a, c, m) then return true end
    -- (and 6 m clear outside its way-out side, all along it: room to drive past)
    local e = C.rect(C.s0, C.s1, C.exit_w, C.exit_w + C.exit_out * 6)
    if inside(e, a, c, m) then return true end
  end
  return false
end
M.in_core = in_core

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

-- One stair box, into the car park's kit `k`.
local TILE, STEP, SIGN = {0.62, 0.6, 0.57}, {0.5, 0.49, 0.47}, {0.1, 0.3, 0.75}
function M.build_core(Lh, k, C)
  local d, ys, dir = C.door, C.ys, C.dir
  local along = d.axis == "across" -- (the box's length runs along the hall)
  local CEIL = 3.0
  -- a box from sa to sb along the stairs (either way), wa to wb across, y0 to y1 up
  local function block(sa, sb, wa, wb, y0, y1, color, solid, em)
    local r = C.rect(sa, sb, wa, wb)
    return k.box((r.a0 + r.a1) / 2, (r.c0 + r.c1) / 2, (y0 + y1) / 2, r.a1 - r.a0, r.c1 - r.c0, y1 - y0, color, solid, em)
  end
  -- a slab sloping from ya at sa to yb at sb, its top there
  local function slope(sa, sb, ya, yb, wa, wb, h, color, solid, em)
    if sa > sb then sa, sb, ya, yb = sb, sa, yb, ya end
    local wm, ww = (wa + wb) / 2, math.abs(wb - wa)
    if along then return k.slab(sa, sb, ya, yb, wm, ww, h, color, solid, em) end
    return k.slab_x(sa, sb, ya, yb, wm, ww, h, color, solid, em)
  end
  local w0, w1, wm = C.w0, C.w1, (C.w0 + C.w1) / 2
  local back, front_end = C.s0 - dir * 0.25, C.s1 + dir * 0.25
  -- floors: the landing, the flight (steps to see, a ramp underfoot), the bottom
  block(C.s0, C.top, w0, w1, ys - 0.6, ys, TILE, true).floor = true
  slope(C.top, C.foot, ys, Y, w0, w1, 0.4, STEP, true).floor = true
  block(C.foot, C.s1, w0, w1, Y - 0.3, Y + 0.01, TILE, not C.pavilion).floor = true
  local rise = (ys - Y) / C.n
  for i = 0, C.n - 1 do
    block(C.top + dir * i * TREAD, C.top + dir * (i + 1) * TREAD, w0 + 0.05, w1 - 0.05, ys - (i + 1) * rise - 0.02, ys - i * rise,
          i % 2 == 0 and STEP or TILE)
  end
  -- walls: both long sides, the ends; the bottom's way out open 2.6 m high
  local top_y = ys + CEIL + 0.3
  for _, w in ipairs{w0, w1} do
    local t = w == w0 and -0.25 or 0.25
    if w == C.exit_w then
      block(back, C.foot, w, w + t, Y, top_y, CONC, true)
      block(C.foot, front_end, w, w + t, Y + 2.6, top_y, CONC, true)
    else
      block(back, front_end, w, w + t, Y, top_y, CONC, true)
    end
  end
  block(back, C.s0, w0, w1, ys - 0.6, top_y, CONC2, true)
  block(C.s1, front_end, w0, w1, Y, top_y, CONC2, true)
  -- ceilings following the stairs down, a lit strip under them
  block(C.s0, C.top, w0, w1, ys + CEIL, ys + CEIL + 0.3, CONC2, true)
  slope(C.top, C.foot, ys + CEIL + 0.3, Y + CEIL + 0.3, w0, w1, 0.3, CONC2, true)
  block(C.foot, C.s1, w0, w1, Y + CEIL, Y + CEIL + 0.3, CONC2, true)
  slope(C.top, C.foot, ys + CEIL - 0.02, Y + CEIL - 0.02, wm - 0.12, wm + 0.12, 0.04, STRIP, false, 1)
  -- handrail on the far side, daylight in the door's glass
  local far = C.exit_w == w1 and w0 or w1
  slope(C.top, C.foot, ys + 0.9, Y + 0.9, far + (far == w0 and 0.08 or -0.08), far + (far == w0 and 0.14 or -0.14), 0.06, {0.25, 0.26, 0.28})
  local dw = d.at - d.out * 0.02
  block(d.c - 0.7, d.c + 0.7, dw - 0.02, dw + 0.02, ys + 0.1, ys + 2.3, {0.85, 0.88, 0.9}, false, 1)
  -- over the way out of the bottom: which way up
  local sm = C.sm
  local ew = C.exit_w + C.exit_out * 0.27
  -- (into a way under the street, 3 m high, lower: clear of its ceiling)
  local sy = C.pavilion and Y + 3.1 or Y + 2.55
  block(sm - 1.45, sm + 1.45, ew - 0.02, ew + 0.02, sy - 0.25, sy + 0.25, SIGN)
  local a, c = C.ac(sm, C.exit_w + C.exit_out * 0.3)
  local face = d.axis == "along" and (C.exit_out > 0 and "+a" or "-a") or (C.exit_out > 0 and "+c" or "-c")
  local label = C.pavilion and (C.unit .. " " .. C.u.street) or C.u.street
  k.text(a, c, sy - 0.05, face, label, 0.26, nil, 0.4)
end

-- A corridor under a street: floor (rising y0 to y1 the way `axis` goes),
-- its two long walls, a ceiling 3 m up, a lit strip; its ends left open
-- (or `closed` = "c1": shut at that end), `open_a1` a gap in its a1 wall.
local WALK_H = 3.0
function M.build_walk(k, W)
  local r, axis, y0, y1 = W.r, W.axis, W.y0, W.y1
  local box, slab, slab_x = k.box, k.slab, k.slab_x
  local am, cm = (r.a0 + r.a1) / 2, (r.c0 + r.c1) / 2
  if axis == "along" then
    local w = r.c1 - r.c0
    slab(r.a0, r.a1, y0, y1, cm, w + 0.5, 0.6, TILE, true).floor = true
    for _, c in ipairs{r.c0 - 0.25, r.c1 + 0.25} do
      slab(r.a0, r.a1, y0 + WALK_H, y1 + WALK_H, c, 0.5, WALK_H + 0.6, CONC, true)
    end
    slab(r.a0, r.a1, y0 + WALK_H + 0.3, y1 + WALK_H + 0.3, cm, w + 1, 0.3, CONC2, true)
    slab(r.a0, r.a1, y0 + WALK_H - 0.02, y1 + WALK_H - 0.02, cm, 0.25, 0.04, STRIP, false, 1)
  else
    local w = r.a1 - r.a0
    slab_x(r.c0, r.c1, y0, y1, am, w + 0.5, 0.6, TILE, true).floor = true
    local function side(a, gap)
      if not gap then slab_x(r.c0, r.c1, y0 + WALK_H, y1 + WALK_H, a, 0.5, WALK_H + 0.6, CONC, true) return end
      slab_x(r.c0, gap[1], y0 + WALK_H, y1 + WALK_H, a, 0.5, WALK_H + 0.6, CONC, true)
      slab_x(gap[2], r.c1 + (W.closed and 0.5 or 0), y0 + WALK_H, y1 + WALK_H, a, 0.5, WALK_H + 0.6, CONC, true)
    end
    side(r.a0 - 0.25)
    side(r.a1 + 0.25, W.open_a1)
    slab_x(r.c0, r.c1, y0 + WALK_H + 0.3, y1 + WALK_H + 0.3, am, w + 1, 0.3, CONC2, true)
    slab_x(r.c0, r.c1, y0 + WALK_H - 0.02, y1 + WALK_H - 0.02, am, 0.25, 0.04, STRIP, false, 1)
    if W.closed == "c1" then box(am, r.c1 + 0.25, (y1 + y1 + WALK_H) / 2, w + 1, 0.5, WALK_H, CONC2, true) end
  end
  -- shop fronts along it near the far end (Wiklund's level -1: OSM's names)
  for i, sh in ipairs(W.C and W.C.u.shops or {}) do
    local c = sh[2] == "-" and r.c0 or r.c1
    local inward = sh[2] == "-" and 1 or -1
    local a0, a1 = r.a1 - 2 - i * 7, r.a1 - 2 - (i - 1) * 7 - 1
    box((a0 + a1) / 2, c + inward * 0.06, y1 + 1.1, a1 - a0, 0.06, 2.2, {0.3, 0.36, 0.4}, false, 0.15)
    -- (the name low enough to clear the 3 m ceiling: its top row hid in it)
    box((a0 + a1) / 2, c + inward * 0.08, y1 + 2.5, a1 - a0, 0.1, 0.5, {0.14, 0.15, 0.17})
    k.text((a0 + a1) / 2, c + inward * 0.14, y1 + 2.45, inward > 0 and "+c" or "-c", sh[1], 0.3, {0.98, 0.97, 0.94}, 0.7)
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
  for _, r in ipairs{L1, L2, ARM} do floor(r); ceiling(r) end
  floor(BODY)
  -- the body's ceiling less the stair boxes (their own ceilings follow the stairs)
  local pieces = {BODY}
  for _, C in ipairs(M.CORES) do
    local h, out = C.R, {}
    for _, r in ipairs(pieces) do
      if h.a1 <= r.a0 or h.a0 >= r.a1 or h.c1 <= r.c0 or h.c0 >= r.c1 then out[#out + 1] = r
      else
        if h.a0 > r.a0 then out[#out + 1] = {a0 = r.a0, a1 = h.a0, c0 = r.c0, c1 = r.c1} end
        if h.a1 < r.a1 then out[#out + 1] = {a0 = h.a1, a1 = r.a1, c0 = r.c0, c1 = r.c1} end
        local a0, a1 = math.max(r.a0, h.a0), math.min(r.a1, h.a1)
        if h.c0 > r.c0 then out[#out + 1] = {a0 = a0, a1 = a1, c0 = r.c0, c1 = h.c0} end
        if h.c1 < r.c1 then out[#out + 1] = {a0 = a0, a1 = a1, c0 = h.c1, c1 = r.c1} end
      end
    end
    pieces = out
  end
  for _, r in ipairs(pieces) do
    box((r.a0 + r.a1) / 2, (r.c0 + r.c1) / 2, Y + H + 0.25, r.a1 - r.a0, r.c1 - r.c0, 0.5, CONC2, true)
  end
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
  -- (with the ways under the streets open in them, 2.6 m high, a lintel over)
  local function gapped(lo, hi, gaps, put)
    local from = lo
    table.sort(gaps, function(p, q) return p[1] < q[1] end)
    for _, g in ipairs(gaps) do
      put(from, g[1], Y, H)
      put(g[1], g[2], Y + 2.6, H - 2.6)
      from = g[2]
    end
    put(from, hi, Y, H)
  end
  gapped(BODY.c0, BODY.c1 + 0.5, M.BODY_GAPS.west, function(c0, c1, y, h) wall_c(c0, c1, BODY.a0 - 0.25, h, y) end)
  gapped(BODY.c0, BODY.c1 + 0.5, M.BODY_GAPS.east, function(c0, c1, y, h) wall_c(c0, c1, BODY.a1 + 0.25, h, y) end)
  gapped(BODY.a0 - 0.5, BODY.a1 + 0.5, M.BODY_GAPS.south, function(a0, a1, y, h) wall_a(a0, a1, BODY.c1 + 0.25, h, y) end)
  -- over each, in the car park: where it goes
  local function over(a, c, face, along_wall, s)
    local w = #s * 0.24 + 0.8
    if along_wall then box(a, c, Y + 3.1, w, 0.04, 0.5, BLUE) else box(a, c, Y + 3.1, 0.04, w, 0.5, BLUE) end
    k.text(a, c, Y + 3.1, face, s, 0.3, nil, 0.4)
  end
  for _, C in ipairs(M.CORES) do
    if C.mouth then
      if C.door.axis == "along" then over(BODY.a1 - 0.05, C.mouth[2], "-a", false, C.u.sign)
      else over(C.mouth[1], BODY.c1 - 0.05, "-c", true, C.u.sign) end
    end
  end
  over(BODY.a0 + 0.05, (M.HANSA.H1.c0 + M.HANSA.H1.c1) / 2, "+a", false, "HANSA")
  wall_a(BODY.a0 - 0.5, ARM.a0, BODY.c0 - 0.25)
  local bays = {}
  for m = 0, 6 do
    local base = 55.5 + 16.5 * m
    for _, row in ipairs{{base + 2.5, -1}, {base + 14, 1}} do
      for a = BAYS_FROM, BAYS_TO, 2.5 do
        if not in_core(a, row[1], 2.6) then
          bays[#bays + 1] = {along = a, across = row[1], nose = row[2]}
          box(a - 1.25, row[1], Y + 0.01, 0.1, 5, 0.02, LINE)
        end
      end
    end
    if m < 6 then
      for a = BAYS_FROM + 2, BAYS_TO - 2, 8 do
        if not in_core(a, base + 16.5, 0.8) then box(a, base + 16.5, Y + H / 2, 0.6, 0.6, H, PILLAR, true) end
      end
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

  for _, C in ipairs(M.CORES) do M.build_core(Lh, k, C) end
  for _, W in ipairs(M.WALKS) do M.build_walk(k, W) end

  local ox, oz = Lh.hall_xz(80, 110)
  bake(Lh, "toriparkki", k, {ox, Y, oz}, Lh.LAYER)
  for _, C in ipairs(M.CORES) do Lh.street_door(C.door, C.pavilion and ("TORIPARKKI " .. C.unit) or "TORIPARKKI", true) end

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
  for _, W in ipairs(M.WALKS) do
    local r = W.r
    if W.axis == "along" then
      for a = r.a0 + 5, r.a1 - 2, 12 do lamp(a, (r.c0 + r.c1) / 2, W.y0 + 2.6) end
    else
      for c = r.c0 + 5, r.c1 - 2, 12 do lamp((r.a0 + r.a1) / 2, c, W.y0 + 2.6) end
    end
  end
  for _, C in ipairs(M.CORES) do
    local wm = (C.w0 + C.w1) / 2
    local a, c = C.ac(C.top, wm)
    lamp(a, c, C.ys + 2.6)
    a, c = C.ac(C.sm, wm)
    lamp(a, c, Y + 2.6)
  end
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
