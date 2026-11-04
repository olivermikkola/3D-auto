-- Louhi, the car park in the rock under Puolalanmäki (docs/UNDERGROUND.md,
-- piece 2): through the portal on Ajurinkatu (systems/landmarks, L.LOUHI),
-- 360 m of tunnel down to the hall at level -2 under Kauppatori's west
-- end, where OpenStreetMap has them (ways 1193257263, 1193258578). All of
-- it in layer 1 (engine::Entity::layer): under the hill, out of the
-- terrain's way, drawn only while you're down there.
--
-- Crossing the portal's mouth takes you (and what you drive) down into
-- layer 1, and backing out of it up again; cops follow the same way
-- (systems/police), the helicopter can't see you down here (systems/heli).
local G = require "lib.state"
local U = require "lib.util"
local L = require "systems.landmarks"

local M = {}
M.LAYER = 1
M.HALL_Y = 2.0 -- the hall's floor: level -2, some 7 m under the square
M.W = 7.0      -- the tunnel's width, wall to wall
M.H = 4.0      -- and its height (the real one is 2.4: room for the camera)
-- The hall: a 195 x 35 m rectangle, its long side toward Kauppatori.
M.HALL = {c = {-290.05, -61.55}, a = {0.8275, -0.5612}, len = 195.3, wid = 35.3}

-- Into the mouth (past the face, between the walls), down; back out past
-- 1.5 m in front of it, up. (The 2 m between keeps a car on the line from
-- flicking between the two.)
M.DOWN_AT, M.UP_AT = 0.5, -1.5

M.built = false
M.cars = {}
-- What's down here because of Louhi (the player, their car, cops, the
-- parked cars): found outside it in layer 1 (after a respawn, a teleport),
-- it's put back up top. Anything else another system put in layer 1 is
-- left be.
M.took = setmetatable({}, {__mode = "k"})

-- The tunnel's frame: from the portal's face (u = 0) into the hill along f,
-- v across it (as landmarks.louhi lays the portal out).
local T
local function frame()
  local P = L.LOUHI
  local fx, fz = P.to[1] - P.x, P.to[2] - P.z
  local l = math.sqrt(fx * fx + fz * fz)
  fx, fz = fx / l, fz / l
  local cx, cz = P.x - fx * 2, P.z - fz * 2
  -- The floor where you come down, as high as the street there (the hill
  -- starts rising at the face).
  local floor = U.ground(cx + fx * M.DOWN_AT, cz + fz * M.DOWN_AT)
  -- Where it meets the hall's near wall: b is the hall's short axis, the
  -- tunnel's way on across it.
  local H = M.HALL
  local bx, bz = -H.a[2], H.a[1]
  if bx * fx + bz * fz < 0 then bx, bz = -bx, -bz end
  local hx, hz = H.c[1] - bx * H.wid / 2, H.c[2] - bz * H.wid / 2
  local u_end = (hx - cx) * fx + (hz - cz) * fz
  T = {fx = fx, fz = fz, rx = fz, rz = -fx, cx = cx, cz = cz, floor = floor, u_end = u_end,
       yaw = math.atan(fx, fz), bx = bx, bz = bz}
  return T
end

-- (u, v) in the tunnel's frame.
local function local_uv(x, z)
  local dx, dz = x - T.cx, z - T.cz
  return dx * T.fx + dz * T.fz, dx * T.rx + dz * T.rz
end
local function at(u, v) return T.cx + T.fx * u + T.rx * v, T.cz + T.fz * u + T.rz * v end

-- The tunnel floor's height u metres in: level outside the mouth, down at
-- an even grade, level for the last 10 m into the hall.
local FLAT_IN = 10
function M.floor_at(u)
  if u <= 0 then return T.floor end
  local slope_end = T.u_end - FLAT_IN
  if u >= slope_end then return M.HALL_Y end
  return T.floor + (M.HALL_Y - T.floor) * u / slope_end
end

-- Is (x, z) down here: in the tunnel or the hall (with a margin)?
function M.inside(x, z, margin)
  if not T then return false end
  margin = margin or 0
  local u, v = local_uv(x, z)
  if u > -14 - margin and u < T.u_end + 2 and math.abs(v) < M.W / 2 + margin then return true end
  local H = M.HALL
  local dx, dz = x - H.c[1], z - H.c[2]
  local along = dx * H.a[1] + dz * H.a[2]
  local across = dx * T.bx + dz * T.bz
  if math.abs(along) < H.len / 2 + margin and math.abs(across) < H.wid / 2 + margin then return true end
  return M.area_floor(x, z, margin + 0.5) ~= nil
end

-- The floor's height at (x, z) down here, or nil outside.
function M.ground(x, z)
  if not M.inside(x, z, 1) then return nil end
  local sy = M.area_floor(x, z)
  if sy then return sy end
  local u, v = local_uv(x, z)
  if math.abs(v) < M.W / 2 + 1 and u < T.u_end then return M.floor_at(u) end
  return M.HALL_Y
end

local CONC, CONC2, ASPHALT, LINE, PILLAR = {0.55, 0.55, 0.53}, {0.45, 0.45, 0.44}, {0.2, 0.2, 0.21}, {0.85, 0.85, 0.8}, {0.62, 0.6, 0.56}
local STRIP = {1, 0.97, 0.9}
M.CEIL = {0.26, 0.26, 0.27} -- the hall's and the tunnel's ceiling: dark, open (Oliver's photos)

-- Statics: drawn parts in one mesh each, and invisible boxes to hit.
local function build_tunnel()
  local parts, solids = {}, {}
  local function slab(u0, u1, y0, y1, v, w, h, color, solid, emissive)
    -- A box from u0 to u1 along the tunnel, its top's middle at y0 .. y1
    -- (rising or falling with the floor), v across, w wide, h deep.
    local du, dy = u1 - u0, y1 - y0
    local len = math.sqrt(du * du + dy * dy)
    local pitch = math.atan(dy, du)
    local ux, uz = at((u0 + u1) / 2, v)
    local cy = (y0 + y1) / 2 - h / 2 * math.cos(pitch)
    local p = {mesh = "cube", pos = {ux, cy, uz}, yaw = T.yaw, pitch = -pitch, size = {w, h, len}, color = color, emissive = emissive}
    parts[#parts + 1] = p
    if solid then solids[#solids + 1] = p end
    return p
  end
  local slope_end = T.u_end - FLAT_IN
  -- The floor in three: outside the mouth (where you come down), the
  -- slope, the last stretch into the hall.
  local runs = {{-14, 0}, {0, slope_end}, {slope_end, T.u_end + 1}}
  for _, r in ipairs(runs) do
    local y0, y1 = M.floor_at(r[1]), M.floor_at(r[2])
    slab(r[1], r[2], y0, y1, 0, M.W + 1, 1, ASPHALT, true).floor = true
    -- walls, the roof, the lit strip down its middle, the middle line
    for _, side in ipairs{-1, 1} do
      slab(r[1], r[2], y0 + M.H, y1 + M.H, side * (M.W / 2 + 0.25), 0.5, M.H, side < 0 and CONC or CONC2, true)
      slab(r[1], r[2], y0 + 0.02, y1 + 0.02, side * (M.W / 2 - 0.6), 0.12, 0.02, LINE)
    end
    slab(r[1], r[2], y0 + M.H + 0.5, y1 + M.H + 0.5, 0, M.W + 1, 0.5, M.CEIL, true)
    slab(r[1], r[2], y0 + M.H - 0.02, y1 + M.H - 0.02, 0, 0.3, 0.06, STRIP, false, 1)
  end
  -- The way out, bright: daylight at the mouth.
  local mx, mz = at(-0.6, 0)
  parts[#parts + 1] = {mesh = "cube", pos = {mx, T.floor + M.H / 2, mz}, yaw = T.yaw, size = {M.W, M.H, 0.05},
                       color = {0.85, 0.88, 0.9}, emissive = 1}
  return parts, solids
end

local function build_hall()
  local H = M.HALL
  local parts, solids, bays = {}, {}, {}
  local ax, az, bx, bz = H.a[1], H.a[2], T.bx, T.bz
  local yaw = math.atan(ax, az)
  local y = M.HALL_Y
  local function hall_at(along, across) return H.c[1] + ax * along + bx * across, H.c[2] + az * along + bz * across end
  local function box(along, across, cy, l, w, h, color, solid, emissive)
    local x, z = hall_at(along, across)
    local p = {mesh = "cube", pos = {x, cy, z}, yaw = yaw, size = {w, h, l}, color = color, emissive = emissive}
    parts[#parts + 1] = p
    if solid then solids[#solids + 1] = p end
    return p
  end
  local L2, W2 = H.len / 2, H.wid / 2
  box(0, 0, y - 0.5, H.len + 1, H.wid + 1, 1, ASPHALT, true).floor = true   -- floor
  box(0, 0, y + M.H + 0.25, H.len + 1, H.wid + 1, 0.5, M.CEIL, true)        -- ceiling
  -- The far wall and the ends, with the doors on foot in them (M.GAPS):
  -- 2.6 m high, a lintel over.
  local function wall(gaps, lo, hi, place_at)
    local from = lo
    table.sort(gaps, function(p, q) return p[1] < q[1] end)
    for _, g in ipairs(gaps) do
      place_at((from + g[1]) / 2, g[1] - from, y + M.H / 2, M.H)
      place_at((g[1] + g[2]) / 2, g[2] - g[1], y + 2.6 + (M.H - 2.6) / 2, M.H - 2.6)
      from = g[2]
    end
    place_at((from + hi) / 2, hi - from, y + M.H / 2, M.H)
  end
  wall(M.GAPS.far, -L2 - 0.5, L2 + 0.5, function(m, l, cy, h) box(m, W2 + 0.25, cy, l, 0.5, h, CONC, true) end)
  wall(M.GAPS.west, -W2 - 0.5, W2 + 0.5, function(m, l, cy, h) box(-L2 - 0.25, m, cy, 0.5, l, h, CONC2, true) end)
  wall(M.GAPS.east, -W2 - 0.5, W2 + 0.5, function(m, l, cy, h) box(L2 + 0.25, m, cy, 0.5, l, h, CONC2, true) end)
  -- The near wall, with the tunnel's mouth in it (along it, where the
  -- tunnel's middle line meets it).
  do
    local px, pz = at(T.u_end, 0)
    local along0 = (px - H.c[1]) * ax + (pz - H.c[2]) * az
    local gap = M.W / 2 + 0.5
    local a0, a1 = -L2 - 0.5, along0 - gap
    box((a0 + a1) / 2, -W2 - 0.25, y + M.H / 2, a1 - a0, 0.5, M.H, CONC, true)
    a0, a1 = along0 + gap, L2 + 0.5
    box((a0 + a1) / 2, -W2 - 0.25, y + M.H / 2, a1 - a0, 0.5, M.H, CONC, true)
    M.mouth_along = along0
  end
  -- Bays: a row along each long wall, a double row down the middle, the
  -- aisles between; pillars between the middle rows, lit strips over the
  -- aisles. 2.5 m bays, 5 m deep. Round each end and across from the
  -- tunnel, room to drive from one aisle to the other.
  local rows = {{-W2 + 2.5, -1}, {-2.5, 1}, {2.5, -1}, {W2 - 2.5, 1}} -- across, which way the car's nose points (+b / -b)
  M.AISLES = {-W2 + 5 + 3.25, W2 - 5 - 3.25}
  local aisles = M.AISLES
  local function open(along, across)
    if math.abs(along) > L2 - 10 then return true end
    if math.abs(along - M.mouth_along) < M.W / 2 + 2 and across < W2 / 2 then return true end -- the tunnel's way in
    if math.abs(along - M.mouth_along) < 6 and math.abs(across) < W2 / 2 then return true end -- the way across
    for _, g in ipairs(M.GAPS.far) do                                                          -- doors on foot
      if across > W2 / 2 and along > g[1] - 3 and along < g[2] + 3 then return true end
    end
    return false
  end
  for along = -L2 + 4, L2 - 4, 2.5 do
    for _, r in ipairs(rows) do
      if not open(along, r[1]) then
        bays[#bays + 1] = {along = along, across = r[1], nose = r[2]}
        -- the bay's line, on the side toward -along
        box(along - 1.25, r[1], y + 0.01, 0.1, 5, 0.02, LINE)
      end
    end
  end
  for along = -L2 + 8, L2 - 8, 8 do
    if not open(along, 0) then box(along, 0, y + M.H / 2, 0.6, 0.6, M.H, PILLAR, true) end
  end
  for _, a in ipairs(aisles) do
    for along = -L2 + 6, L2 - 6, 12 do box(along, a, y + M.H - 0.03, 4, 0.3, 0.06, STRIP, false, 1) end
  end
  M.hall_at, M.hall_yaw = hall_at, yaw
  return parts, solids, bays
end

-- ---- the look, from Oliver's photos (November 2026) ------------------------------
-- Blasted out of the hill: the walls are the rock, sprayed and painted white,
-- bumpy, leaning in overhead where they meet the dark open ceiling (ducts,
-- cable trays, rows of LED strips). Along the walls a low kerb, a red rail at
-- hip height, red extinguisher boxes; at the way in a dark P1 sign with the
-- free places in green, a striped height beam, 20 signs and red bollards.
-- Drawn only (nothing new to hit), laid out by a hash of the place, the same
-- every time (no math.random: it would shift traffic's draws).
local ROCK = {{0.88, 0.88, 0.86}, {0.82, 0.82, 0.8}, {0.92, 0.92, 0.9}, {0.77, 0.77, 0.75}}
local KERB_C, RED, DARK = {0.5, 0.5, 0.49}, {0.72, 0.1, 0.1}, {0.13, 0.14, 0.16}
local DUCT, TRAY, EXIT = {0.55, 0.56, 0.57}, {0.42, 0.43, 0.45}, {0.1, 0.55, 0.25}
local KERB_W, KERB_H = 0.6, 0.12

local function hash(i, k)
  local s = (i * 73856093 + k * 19349663) % 2147483648
  s = (s * 1103515245 + 12345) % 2147483648
  return (s % 10007) / 10007
end

-- One wall's dressing, in a frame of its own: s along the wall, `out` from
-- its face into the room, y up from `fy(s)` (the floor there). part(s, out,
-- cy, len, thick, h, color, lean, mesh, emissive, twist) puts one in (lean:
-- its top toward the room; twist: turned about the vertical).
-- The rock in three tiers of lumps 0.7 to 1.7 m long, each a little further
-- out than the one under it, the top one leaning in: the vault's foot.
local TIERS = {{KERB_H, 1.6, 0.05, 0.02}, {1.5, 2.9, 0.12, 0.1}, {2.8, nil, 0.22, 0.3}}
local function dress_wall(s0, s1, seed, fy, part, opts)
  opts = opts or {}
  local m, l = (s0 + s1) / 2, s1 - s0
  part(m, KERB_W / 2, fy(m) + KERB_H / 2, l, KERB_W, KERB_H, KERB_C)
  for t, tier in ipairs(TIERS) do
    local y0, y1 = tier[1], tier[2] or M.H + 0.1
    local s, i = s0, t * 3000
    while s < s1 - 0.2 do
      local len = math.min(0.7 + 1.0 * hash(seed, i), s1 - s)
      local r1, r2, r3 = hash(seed, i + 500), hash(seed, i + 900), hash(seed, i + 1700)
      local c = ROCK[1 + math.floor(hash(seed, i + 1300) * #ROCK) % #ROCK]
      local mid = s + len / 2
      local h = y1 - y0 + 0.2 * r2
      part(mid, tier[3] + 0.18 * r1 - 0.1, fy(mid) + y0 + h / 2, len + 0.2, 0.4, h, c,
           tier[4] + (r2 - 0.5) * 0.2, nil, nil, (r3 - 0.5) * 0.5)
      s, i = s + len, i + 1
    end
  end
  -- and smaller bumps over them, so it doesn't read as panels
  local s, i = s0 + 0.3, 9000
  while s < s1 - 0.5 do
    local r1, r2, r3, r4 = hash(seed, i), hash(seed, i + 500), hash(seed, i + 900), hash(seed, i + 1700)
    local by = KERB_H + 0.4 + 2.9 * r1
    local tier = by > 2.8 and TIERS[3] or by > 1.5 and TIERS[2] or TIERS[1]
    part(s, tier[3] + 0.2, fy(s) + by, 0.5 + 0.5 * r2, 0.35, 0.35 + 0.4 * r3,
         ROCK[1 + math.floor(r4 * #ROCK) % #ROCK], tier[4] + (r3 - 0.5) * 0.6, nil, nil, (r4 - 0.5) * 1.2)
    s, i = s + 0.5 + 0.8 * r2, i + 1
  end
  if opts.rail then
    part(m, 0.62, fy(m) + 1.25, l, 0.08, 0.12, RED)
    for s = s0 + 14, s1 - 6, 36 do
      part(s, 0.55, fy(s) + 1.0, 0.4, 0.22, 0.6, RED)
      part(s, 0.5, fy(s) + 1.65, 0.25, 0.02, 0.25, RED, 0, nil, 0.3)
    end
  end
end

local function dress_tunnel(parts)
  local slope_end = T.u_end - FLAT_IN
  local grade = math.atan(M.HALL_Y - T.floor, slope_end)
  local function pitch_at(u) return (u > 0 and u < slope_end) and grade or 0 end
  local function piece(u, v, cy, len, w, h, color, roll, mesh, emissive, twist)
    local x, z = at(u, v)
    parts[#parts + 1] = {mesh = mesh or "cube", pos = {x, cy, z}, yaw = T.yaw + (twist or 0), pitch = -pitch_at(u),
                         roll = roll, size = {w, h, len}, color = color, emissive = emissive}
  end
  for side = -1, 1, 2 do
    local face = side * M.W / 2
    dress_wall(0.5, T.u_end, side + 2, M.floor_at, function(s, out, cy, len, thick, h, color, lean, mesh, em, twist)
      piece(s, face - side * out, cy, len, thick, h, color, lean and -side * lean, mesh, em, twist)
    end)
    -- a duct up by the roof, on one side
    if side > 0 then
      for u = 2, T.u_end - 4, 12 do
        piece(u + 6, face - 1.1, M.floor_at(u + 6) + M.H - 0.45, 12.1, 0.5, 0.5, DUCT, nil, "cube")
      end
    end
  end
  for u = 4, T.u_end - 4, 6 do
    piece(u, 0, M.floor_at(u) + 0.03, 3, 0.12, 0.02, LINE)
  end
end

local function dress_hall(k)
  local H = M.HALL
  local L2, W2 = H.len / 2, H.wid / 2
  local y = M.HALL_Y
  local function flat() return y end
  local function runs(lo, hi, gaps, margin)
    local out, from, g = {}, lo, {}
    for _, q in ipairs(gaps) do g[#g + 1] = q end
    table.sort(g, function(p, q) return p[1] < q[1] end)
    for _, q in ipairs(g) do
      if q[1] - margin > from then out[#out + 1] = {from, q[1] - margin} end
      from = math.max(from, q[2] + margin)
    end
    if hi > from then out[#out + 1] = {from, hi} end
    return out
  end
  local mouth = {M.mouth_along - M.W / 2 - 0.5, M.mouth_along + M.W / 2 + 0.5}
  local walls = {
    {line = W2, sgn = 1, axis = "along", gaps = M.GAPS.far, lo = -L2, hi = L2},
    {line = -W2, sgn = -1, axis = "along", gaps = {mouth}, lo = -L2, hi = L2},
    {line = -L2, sgn = -1, axis = "across", gaps = M.GAPS.west, lo = -W2, hi = W2},
    {line = L2, sgn = 1, axis = "across", gaps = M.GAPS.east, lo = -W2, hi = W2},
  }
  for wi, w in ipairs(walls) do
    for ri, r in ipairs(runs(w.lo, w.hi, w.gaps, 0.2)) do
      dress_wall(r[1], r[2], wi * 10 + ri, flat, function(s, out, cy, len, thick, h, color, lean, mesh, em, twist)
        local p
        if w.axis == "along" then
          p = k.box(s, w.line - w.sgn * out, cy, len, thick, h, color, false, em)
          if lean then p.roll = w.sgn * lean end
        else
          p = k.box(w.line - w.sgn * out, s, cy, thick, len, h, color, false, em)
          if lean then p.pitch = -w.sgn * lean end
        end
        if mesh then p.mesh = mesh end
        if twist then p.yaw = p.yaw + twist end
      end, {rail = w.axis == "along"})
    end
  end
  -- The open ceiling: ducts down each side, cable trays over the pillars.
  for _, c in ipairs{-W2 + 2.2, W2 - 2.2} do
    for along = -L2 + 3, L2 - 15, 12 do k.box(along + 6, c, y + M.H - 0.45, 12.1, 0.6, 0.6, DUCT) end
  end
  for _, c in ipairs{-1.1, 1.1} do
    k.box(0, c, y + M.H - 0.25, H.len - 4, 0.5, 0.06, TRAY)
  end
  -- The way in from the tunnel: the striped height beam over the mouth, red
  -- bollards at its corners, the P1 sign with the free places, the 20 signs.
  local bc = -W2 + 0.6
  local n = 0
  for a = mouth[1], mouth[2] - 0.5, 0.5 do
    n = n + 1
    k.box(a + 0.25, bc, y + M.H - 0.35, 0.5, 0.25, 0.3, n % 2 == 0 and {0.95, 0.95, 0.93} or {0.08, 0.08, 0.08})
  end
  for _, a in ipairs{mouth[1] - 0.2, mouth[2] + 0.2} do
    k.box(a, -W2 + 0.9, y + 0.5, 0.2, 0.2, 1.0, RED).mesh = "cylinder"
  end
  -- The sign over the way in (as photographed): dark, P1 and the free places
  -- in green in the middle, a 20 at each end; facing the cars coming in.
  local free = M.free_bays or 0
  local sc, sy = -W2 + 6, y + M.H - 0.7
  k.box(M.mouth_along, sc, sy, 5.6, 0.15, 0.6, DARK)
  k.text(M.mouth_along + 1.0, sc - 0.08, sy, "-c", "P1", 0.36, {1, 1, 1}, 0.5)
  k.text(M.mouth_along - 0.8, sc - 0.08, sy, "-c", tostring(free), 0.36, {0.2, 1, 0.3}, 1)
  for _, a in ipairs{M.mouth_along - 2.4, M.mouth_along + 2.4} do
    for _, d in ipairs{{0.48, RED, 0.1}, {0.38, {0.95, 0.95, 0.93}, 0.11}} do
      local p = k.box(a, sc - d[3], sy, d[1], d[1], 0.02, d[2])
      p.mesh, p.roll = "cylinder", math.pi / 2
    end
    k.text(a, sc - 0.12, sy, "-c", "20", 0.2, {0.05, 0.05, 0.05})
  end
  -- Over each door on foot: the green ULOS sign.
  for _, g in ipairs(M.GAPS.far) do
    local m = (g[1] + g[2]) / 2
    k.box(m, W2 - 0.03, y + 3.7, 1.4, 0.05, 0.36, EXIT, false, 0.8)
    k.text(m, W2 - 0.07, y + 3.7, "-c", "ULOS", 0.24, {1, 1, 1}, 0.8)
  end
  for _, g in ipairs(M.GAPS.west) do
    local m = (g[1] + g[2]) / 2
    k.box(-L2 + 0.03, m, y + 3.7, 0.05, 1.4, 0.36, EXIT, false, 0.8)
    k.text(-L2 + 0.07, m, y + 3.7, "+a", "ULOS", 0.24, {1, 1, 1}, 0.8)
  end
end

-- ---- on foot: doors up to the street, ways to them (pieces 3, 4) ----------------
-- Everything on foot down here is laid out in the hall's frame: along its
-- long axis, across it (+ away from the tunnel). Hansakortteli above it is
-- squared to the same lines, near enough.
--   M.AREAS: floors to stand on, {a0, a1, c0, c1, y0, y1, axis}: from a0 to a1
--     along, c0 to c1 across, y0 rising to y1 the way `axis` ("along",
--     "across") goes, or flat at y0.
--   M.DOORS: doors up to the street in a building's wall, {axis, at, out, c,
--     ys}: the wall at `axis` = at, out the way `out` (+1, -1) points, the
--     door's middle at c on the other axis, the street at ys.
--   M.ROUTES: ways on foot from the hall to a door, {pts = {{along, across},
--     ...}, w = their width, door}: the officers' way after you.
--   M.GAPS: openings in the hall's walls: far = {{a0, a1}, ...} along,
--     west, east = {{c0, c1}, ...} across.
M.PORTALS = {}
M.AREAS, M.DOORS, M.ROUTES, M.GAPS = {}, {}, {}, {far = {}, west = {}, east = {}}
--   M.PORTALS: other ways in by car from the street (systems/toriparkki),
--     {axis, at, out, c, w, ys, order, outside = {along, across}}: the mouth
--     at `axis` = at facing out the way `out` points, w wide round c.

local function hall_xz(along, across)
  local H = M.HALL
  return H.c[1] + H.a[1] * along + T.bx * across, H.c[2] + H.a[2] * along + T.bz * across
end
local function hall_ab(x, z)
  local H = M.HALL
  local dx, dz = x - H.c[1], z - H.c[2]
  return dx * H.a[1] + dz * H.a[2], dx * T.bx + dz * T.bz
end
M.hall_xz, M.hall_ab = hall_xz, hall_ab

-- The floor of M.AREAS at (x, z) (with a margin round each), or nil.
function M.area_floor(x, z, margin)
  margin = margin or 0.3
  local along, across = hall_ab(x, z)
  for _, r in ipairs(M.AREAS) do
    if along > r.a0 - margin and along < r.a1 + margin and across > r.c0 - margin and across < r.c1 + margin then
      if r.axis == "along" then return r.y0 + (r.y1 - r.y0) * U.clamp((along - r.a0) / (r.a1 - r.a0), 0, 1) end
      if r.axis == "across" then return r.y0 + (r.y1 - r.y0) * U.clamp((across - r.c0) / (r.c1 - r.c0), 0, 1) end
      return r.y0
    end
  end
  return nil
end

-- A builder in the hall's frame: parts to draw, solids to hit.
--   box(along, across, cy, l, w, h, color, solid, emissive): l along, w across
--   slab(a0, a1, y0, y1, across, w, h, ...): along, its top from y0 to y1
--   slab_x(c0, c1, y0, y1, along, l, h, ...): the same across
--   text(along, across, y, face, s, height, color, emissive): face "+a", "-a", "+c", "-c"
function M.kit()
  local H = M.HALL
  local yaw_a, yaw_c = math.atan(H.a[1], H.a[2]), math.atan(T.bx, T.bz)
  local k = {parts = {}, solids = {}}
  local function put(p, solid)
    k.parts[#k.parts + 1] = p
    if solid then k.solids[#k.solids + 1] = p end
    return p
  end
  function k.box(along, across, cy, l, w, h, color, solid, emissive)
    local x, z = hall_xz(along, across)
    return put({mesh = "cube", pos = {x, cy, z}, yaw = yaw_a, size = {w, h, l}, color = color, emissive = emissive}, solid)
  end
  function k.slab(a0, a1, y0, y1, across, w, h, color, solid, emissive)
    local da, dy = a1 - a0, y1 - y0
    local pitch = math.atan(dy, da)
    local x, z = hall_xz((a0 + a1) / 2, across)
    return put({mesh = "cube", pos = {x, (y0 + y1) / 2 - h / 2 * math.cos(pitch), z}, yaw = yaw_a, pitch = -pitch,
         size = {w, h, math.sqrt(da * da + dy * dy)}, color = color, emissive = emissive}, solid)
  end
  function k.slab_x(c0, c1, y0, y1, along, l, h, color, solid, emissive)
    local dc, dy = c1 - c0, y1 - y0
    local pitch = math.atan(dy, dc)
    local x, z = hall_xz(along, (c0 + c1) / 2)
    return put({mesh = "cube", pos = {x, (y0 + y1) / 2 - h / 2 * math.cos(pitch), z}, yaw = yaw_c, pitch = -pitch,
         size = {l, h, math.sqrt(dc * dc + dy * dy)}, color = color, emissive = emissive}, solid)
  end
  local FACE = {["+a"] = {1, 0}, ["-a"] = {-1, 0}, ["+c"] = {0, 1}, ["-c"] = {0, -1}}
  function k.text(along, across, y, face, s, height, color, emissive)
    local f = FACE[face]
    local x, z = hall_xz(along + f[1] * 0.03, across + f[2] * 0.03)
    local fx, fz = H.a[1] * f[1] + T.bx * f[2], H.a[2] * f[1] + T.bz * f[2]
    put{text = s, pos = {x, y, z}, yaw = math.atan(fx, fz), height = height, depth = 0.02, color = color or {1, 1, 1}, emissive = emissive}
  end
  return k
end

-- A door's frame: how far (x, z) is out of it, and how far to one side.
local function door_dist(d, x, z)
  local along, across = hall_ab(x, z)
  if d.axis == "along" then return (along - d.at) * d.out, across - d.c end
  return (across - d.at) * d.out, along - d.c
end
local function door_xz(d, out, side)
  local w = d.at + out * d.out
  if d.axis == "along" then return hall_xz(w, d.c + side) end
  return hall_xz(d.c + side, w)
end
M.door_xz = door_xz

-- Through a door to the street on foot: where `id` goes (layer, x, z, the
-- door), or nil.
function M.door_crossing(id)
  local x, y, z = engine.pos(id)
  local layer = engine.layer(id)
  for _, d in ipairs(M.DOORS) do
    local out, side = door_dist(d, x, z)
    if layer == 0 and out > -0.2 and out < 0.75 and math.abs(side) < 0.9 and math.abs(y - d.ys) < 2.5 then
      local nx, nz = door_xz(d, -1.0, side)
      return M.LAYER, nx, nz, d
    end
    if layer == M.LAYER and M.took[id] and out > -0.6 and out < 0.5 and math.abs(side) < 1.6 and y > d.ys - 1.5 then
      local nx, nz = door_xz(d, 1.1, 0)
      return 0, nx, nz, d
    end
  end
  return nil
end

-- Where (x, z) is on a route: the route, how far along it, or nil.
local function on_route(x, z)
  local along, across = hall_ab(x, z)
  for _, r in ipairs(M.ROUTES) do
    local s = 0
    for i = 2, #r.pts do
      local p, q = r.pts[i - 1], r.pts[i]
      local da, dc = q[1] - p[1], q[2] - p[2]
      local len = math.sqrt(da * da + dc * dc)
      local t = U.clamp(((along - p[1]) * da + (across - p[2]) * dc) / (len * len), 0, 1)
      local ea, ec = p[1] + da * t - along, p[2] + dc * t - across
      if ea * ea + ec * ec < (r.w / 2 + 0.6) ^ 2 then return r, s + t * len end
      s = s + len
    end
  end
  return nil
end
local function route_len(r)
  if r.len then return r.len end
  local s = 0
  for i = 2, #r.pts do s = s + U.dist2d(r.pts[i - 1][1], r.pts[i - 1][2], r.pts[i][1], r.pts[i][2]) end
  r.len = s
  return s
end
local function route_at(r, s)
  for i = 2, #r.pts do
    local p, q = r.pts[i - 1], r.pts[i]
    local len = U.dist2d(p[1], p[2], q[1], q[2])
    if s <= len or i == #r.pts then
      local t = U.clamp(s / len, 0, 1)
      return hall_xz(p[1] + (q[1] - p[1]) * t, p[2] + (q[2] - p[2]) * t)
    end
    s = s - len
  end
end

-- For police officers on foot (systems/police): where `id` walks instead of
-- straight at you, or nil. Out through a door and down a route after you,
-- or back up, or along one.
local function where(id, x, z)
  if (engine.layer(id) or 0) == 0 then return "top" end
  local r, s = on_route(x, z)
  if r then return "route", r, s end
  return "down"
end
function M.walk(id, px, pz)
  local you = G.vehicle or G.player
  if #M.ROUTES == 0 or not you then return nil end
  local x, _, z = engine.pos(id)
  local mine, rm, sm = where(id, x, z)
  local theirs, rt, st = where(you, px, pz)
  -- (Which way down to take: the route you're on, or the door nearest you.)
  local function nearest_to(qx, qz)
    local best, bd
    for _, r in ipairs(M.ROUTES) do
      local dx, dz = door_xz(r.door, 0, 0)
      local d = U.dist2d(qx, qz, dx, dz)
      if not bd or d < bd then best, bd = r, d end
    end
    return best, bd
  end
  if mine == "top" then
    if theirs == "top" then return nil end
    local r, d = nearest_to(x, z)
    if d > 120 then return nil end
    local ox, oz = door_xz(r.door, 1.5, 0)
    if U.dist2d(x, z, ox, oz) > 1.0 then return ox, oz end
    return door_xz(r.door, -0.3, 0)
  end
  if mine == "route" then
    local len = route_len(rm)
    local goal
    if theirs == "route" and rt == rm then
      if math.abs(st - sm) < 2 then return nil end
      goal = st
    elseif theirs == "top" then
      goal = len + 2
    else
      goal = 0
    end
    if goal > sm then
      if sm > len - 1.5 then return door_xz(rm.door, 0.3, 0) end
      return route_at(rm, math.min(sm + 3, goal))
    end
    if sm < 1.5 then return route_at(rm, 0) end
    return route_at(rm, math.max(sm - 3, goal))
  end
  -- Down in the hall (or the tunnel): to the way you went.
  if theirs == "down" then return nil end
  local r = rt or nearest_to(px, pz)
  local hx, hz = route_at(r, 0)
  if U.dist2d(x, z, hx, hz) > 1.5 then return hx, hz end
  return route_at(r, 3)
end

-- ---- up to Kauppatori (piece 3) ------------------------------------------------
-- Louhi's stair house on Kauppatori's west end (OSM way 1034479364, its
-- door on the west side, node on way 1193257272) stands just past the
-- hall's far wall. Down here: a door in the far wall, a flight of stairs
-- up alongside it to a landing at street height behind that door.
local function plan_stairs()
  -- The door (OSM): in the stair house's west wall, 19.3 m along, 20.1 across.
  local door, dc = 19.27, 20.1
  local ys = U.ground(hall_xz(door - 0.8, dc))
  local w = 2.9
  local mid = M.HALL.wid / 2 + 0.5 + w / 2 -- (the hall's far wall is the stairs' inner one)
  local n = math.max(2, math.ceil((ys - M.HALL_Y) / 0.17))
  local top = door + 2.3                  -- the landing behind the door
  local foot = top + n * 0.29             -- the flight, 0.29 m treads
  local S = {door = door, dc = dc, ys = ys, w = w, mid = mid, n = n, top = top, foot = foot, bottom = 3}
  M.STAIRS = S
  local c0, c1 = mid - w / 2, mid + w / 2
  M.AREAS[#M.AREAS + 1] = {a0 = door, a1 = top, c0 = c0, c1 = c1, y0 = ys}
  M.AREAS[#M.AREAS + 1] = {a0 = top, a1 = foot, c0 = c0, c1 = c1, y0 = ys, y1 = M.HALL_Y, axis = "along"}
  M.AREAS[#M.AREAS + 1] = {a0 = foot, a1 = foot + S.bottom, c0 = c0 - 0.5, c1 = c1, y0 = M.HALL_Y}
  local d = {axis = "along", at = door, out = -1, c = dc, ys = ys, name = "Kauppatori"}
  M.DOORS[#M.DOORS + 1] = d
  local W2 = M.HALL.wid / 2
  M.ROUTES[#M.ROUTES + 1] = {pts = {{foot + 1.5, W2 - 3}, {foot + 1.5, mid}, {top - 0.3, mid}, {door + 0.5, dc}}, w = w, door = d}
  M.GAPS.far[#M.GAPS.far + 1] = {foot, foot + S.bottom}
end

local function build_stairs()
  local S = M.STAIRS
  local H = M.HALL
  local k = M.kit()
  local box, slab = k.box, k.slab
  local ys, y, mid, w, top, foot, far = S.ys, M.HALL_Y, S.mid, S.w, S.top, S.foot, S.foot + S.bottom
  local TILE, STEP = {0.62, 0.6, 0.57}, {0.5, 0.49, 0.47}
  local CEIL = 3.0
  -- the landing, the bottom, and the flight between: steps to see, a ramp
  -- along their noses underfoot (as the outdoor stairs, roadnet)
  slab(S.door - 0.5, top, ys, ys, mid, w + 0.6, 0.6, TILE, true)
  slab(foot, far + 0.5, y, y, mid, w + 0.6, 0.6, TILE, true)
  local rise = (ys - y) / S.n
  for i = 0, S.n - 1 do
    box(top + (i + 0.5) * 0.29, mid, ys - i * rise - 0.3, 0.3, w, 0.6, i % 2 == 0 and STEP or TILE)
  end
  slab(top, foot, ys, y, mid, w, 0.4, STEP, true)
  -- walls: the outer one, the inner one above the hall's, the two ends
  local wall_top = ys + CEIL
  box((S.door + far) / 2, mid + w / 2 + 0.25, (y + wall_top) / 2, far - S.door + 1, 0.5, wall_top - y + 0.6, CONC2, true)
  box((S.door + far) / 2, mid - w / 2 - 0.25, (y + M.H + wall_top) / 2, far - S.door + 1, 0.5, wall_top - y - M.H + 0.6, CONC, true)
  box(S.door - 0.25, mid, (ys + wall_top) / 2, 0.5, w + 1, wall_top - ys + 1.2, CONC, true)
  box(far + 0.25, mid, (y + y + CEIL) / 2, 0.5, w + 1, CEIL + 0.6, CONC, true)
  -- the ceiling, following the stairs down, and its lit strip
  slab(S.door - 0.5, top, ys + CEIL + 0.3, ys + CEIL + 0.3, mid, w + 1, 0.3, CONC2, true)
  slab(top, foot, ys + CEIL + 0.3, y + CEIL + 0.3, mid, w + 1, 0.3, CONC2, true)
  slab(foot, far + 0.5, y + CEIL + 0.3, y + CEIL + 0.3, mid, w + 1, 0.3, CONC2, true)
  slab(S.door, top, ys + CEIL - 0.02, ys + CEIL - 0.02, mid, 0.25, 0.04, STRIP, false, 1)
  slab(top, foot, ys + CEIL - 0.02, y + CEIL - 0.02, mid, 0.25, 0.04, STRIP, false, 1)
  -- handrail on the outer wall
  slab(top, foot, ys + 0.9, y + 0.9, mid + w / 2 - 0.08, 0.06, 0.06, {0.25, 0.26, 0.28})
  -- the way out: daylight in the door's glass
  box(S.door + 0.02, S.dc, ys + 1.1, 0.04, 1.4, 2.2, {0.85, 0.88, 0.9}, false, 1)
  -- in the hall, over the door: the way to the square
  box((foot + far) / 2, H.wid / 2 - 0.02, y + 3.1, S.bottom, 0.04, 0.5, {0.1, 0.3, 0.75})
  k.text((foot + far) / 2, H.wid / 2 - 0.05, y + 3.1, "-c", "KAUPPATORI", 0.32, nil, 0.4)
  return k
end

-- Up top: a door in a building's wall to the street, dark glass in a light
-- frame, a sign over it (and the blue P), in layer 0.
function M.street_door(d, sign, p)
  local k = M.kit()
  local face = (d.axis == "along" and (d.out > 0 and "+a" or "-a")) or (d.out > 0 and "+c" or "-c")
  local function box(out, side, cy, depth, wide, h, color)
    if d.axis == "along" then
      k.box(d.at + d.out * out, d.c + side, cy, depth, wide, h, color)
    else
      k.box(d.c + side, d.at + d.out * out, cy, wide, depth, h, color)
    end
  end
  local function text(out, side, y, s, h, color, em)
    if d.axis == "along" then k.text(d.at + d.out * out, d.c + side, y, face, s, h, color, em)
    else k.text(d.c + side, d.at + d.out * out, y, face, s, h, color, em) end
  end
  local ys = d.ys
  box(0.04, 0, ys + 1.15, 0.1, 1.7, 2.45, {0.85, 0.85, 0.82})   -- frame
  box(0.07, 0, ys + 1.1, 0.06, 1.4, 2.2, {0.1, 0.12, 0.14})      -- glass
  box(0.07, 0, ys + 2.75, 0.06, 2.6, 0.5, {0.12, 0.13, 0.15})    -- the sign's band
  text(0.1, p and -0.35 or 0, ys + 2.75, sign, 0.35, {0.95, 0.95, 0.92}, 0.6)
  if p then
    box(0.09, 0.95, ys + 2.75, 0.06, 0.42, 0.42, {0.1, 0.3, 0.75})
    text(0.13, 0.95, ys + 2.75, "P", 0.32)
  end
  local ox, oz = door_xz(d, 0, 0)
  for _, q in ipairs(k.parts) do q.pos = {q.pos[1] - ox, q.pos[2] - ys, q.pos[3] - oz} end
  local name = "louhi_door_" .. d.name
  engine.mesh(name, k.parts)
  engine.spawn{mesh = name, pos = {ox, ys, oz}, tag = "building"}
end

-- Parts in one mesh at `o`, and their solids as invisible statics, all in layer 1.
-- The floors are "ground", the rest "wall": driving onto a floor (in at the
-- portal the car meets it all at once) isn't a crash.
local function place(name, parts, solids, o)
  local baked = {}
  for k, p in ipairs(parts) do
    local q = {}
    for key, val in pairs(p) do if key ~= "floor" then q[key] = val end end
    q.pos = {p.pos[1] - o[1], p.pos[2] - o[2], p.pos[3] - o[3]}
    baked[k] = q
  end
  engine.mesh(name, baked)
  engine.spawn{mesh = name, pos = o, layer = M.LAYER, tag = "building"}
  for _, p in ipairs(solids) do
    engine.spawn{mesh = "cube", pos = p.pos, yaw = p.yaw, pitch = p.pitch, size = p.size, visible = false, body = "static",
                 tag = p.floor and "ground" or "wall", layer = M.LAYER}
  end
end

function M.build(map)
  if not map or map.id ~= "turku" or M.built then return end
  M.built = true
  frame()
  plan_stairs()
  local hansa = require "systems.hansa"
  hansa.plan(M)
  local tori = require "systems.toriparkki"
  tori.plan(M)
  local parts, solids = build_tunnel()
  place("louhi_tunnel", parts, solids, {T.cx, T.floor, T.cz})
  local hp, hs, bays = build_hall()
  place("louhi_hall", hp, hs, {M.HALL.c[1], M.HALL_Y, M.HALL.c[2]})
  M.bays = bays
  local sk = build_stairs()
  local ox, oz = hall_xz(M.STAIRS.door, M.STAIRS.mid)
  place("louhi_stairs", sk.parts, sk.solids, {ox, M.STAIRS.ys, oz})
  M.street_door(M.DOORS[1], "LOUHI", true)
  hansa.build(M)
  tori.build(M)
  do
    local lx, lz = hall_xz((M.STAIRS.top + M.STAIRS.foot) / 2, M.STAIRS.mid)
    engine.light{pos = {lx, (M.STAIRS.ys + M.HALL_Y) / 2 + 2.6, lz}, color = {1, 0.96, 0.9}, intensity = 1, radius = 12, layer = M.LAYER}
  end
  -- Lamps: one every 30 m down the tunnel, and over the hall's aisles
  -- (only the nearest 16 are lit at a time).
  for u = 10, T.u_end, 30 do
    local x, z = at(u, 0)
    engine.light{pos = {x, M.floor_at(u) + M.H - 0.3, z}, color = {1, 0.95, 0.85}, intensity = 1.2, radius = 18, layer = M.LAYER}
  end
  for along = -M.HALL.len / 2 + 12, M.HALL.len / 2 - 12, 24 do
    for _, across in ipairs{-M.HALL.wid / 4, M.HALL.wid / 4} do
      local x, z = M.hall_at(along, across)
      engine.light{pos = {x, M.HALL_Y + M.H - 0.3, z}, color = {0.95, 1, 0.95}, intensity = 1.2, radius = 20, layer = M.LAYER}
    end
  end
  -- Parked cars in a third of the bays, the same ones every time.
  local vehicle = require "lib.vehicle"
  local s = 7
  for _, b in ipairs(bays) do
    s = (s * 1103515245 + 12345) % 2147483648
    if s % 3 == 0 then
      local x, z = M.hall_at(b.along, b.across)
      local yaw = math.atan(T.bx * b.nose, T.bz * b.nose) -- nose to the wall or the pillars
      local id = vehicle.spawn(x, z, yaw, 1 + s % 8, nil, nil, M.HALL_Y)
      engine.set_layer(id, M.LAYER)
      M.cars[#M.cars + 1] = id
      M.took[id] = true
    end
  end
  M.free_bays = #bays - #M.cars
  local dp = {}
  dress_tunnel(dp)
  place("louhi_tunnel_look", dp, {}, {T.cx, T.floor, T.cz})
  local dk = M.kit()
  dress_hall(dk)
  place("louhi_hall_look", dk.parts, {}, {M.HALL.c[1], M.HALL_Y, M.HALL.c[2]})
end

-- Who's going where: the player, on foot or with what they drive.
local function set_layer(l)
  for _, id in pairs{p = G.player, v = G.vehicle} do -- (either may be nil)
    if engine.exists(id) then
      engine.set_layer(id, l)
      M.took[id] = l ~= 0 or nil
    end
  end
  engine.view_layer(l)
end

-- Through a portal by car (or on foot): which layer `id` goes to, and the
-- portal (nil: Louhi's own), or nil.
function M.crossing(id)
  local x, y, z = engine.pos(id)
  local u, v = local_uv(x, z)
  local layer = engine.layer(id)
  if layer == 0 and u > M.DOWN_AT and u < 8 and math.abs(v) < M.W / 2 and y < T.floor + 4 then return M.LAYER end
  if layer == M.LAYER and M.took[id] and u < M.UP_AT and math.abs(v) < M.W / 2 + 1 then return 0 end
  local along, across = M.hall_ab(x, z)
  for _, p in ipairs(M.PORTALS) do
    local o, side
    if p.axis == "along" then o, side = (along - p.at) * p.out, across - p.c else o, side = (across - p.at) * p.out, along - p.c end
    if layer == 0 and o < -0.5 and o > -8 and math.abs(side) < p.w / 2 and y < p.ys + 4 then return M.LAYER, p end
    if layer == M.LAYER and M.took[id] and o > 1.5 and o < 20 and math.abs(side) < p.w / 2 + 1 then return 0, p end
  end
  if layer == M.LAYER and M.took[id] and not M.inside(x, z, 6) then return 0 end
  return nil
end

engine.on("tick", function()
  if not T or not M.built then return end
  -- Cops through the portal too, and their officers with them.
  local police = package.loaded["systems.police"]
  if police then
    for cid in pairs(police.cops) do
      local to = engine.exists(cid) and M.crossing(cid)
      if to then
        engine.set_layer(cid, to)
        M.took[cid] = to ~= 0 or nil
      end
    end
  end
  if police then
    for oid in pairs(police.officers) do
      local to, nx, nz = M.door_crossing(oid)
      if to then
        local _, oy = engine.pos(oid)
        engine.set_layer(oid, to)
        engine.set_pos(oid, nx, oy + 0.05, nz)
        M.took[oid] = to ~= 0 or nil
      end
    end
  end
  local id = G.vehicle or G.player
  if not id or not engine.exists(id) then return end
  if not G.vehicle then
    local to, nx, nz, d = M.door_crossing(id)
    if to then
      local _, py = engine.pos(id)
      engine.set_pos(id, nx, py + 0.05, nz)
      set_layer(to)
      engine.emit(to == 0 and "underground_exit" or "underground_enter", id)
      local wanted = require "lib.wanted"
      if to ~= 0 and wanted.stars() > 0 then
        local ex, ez = door_xz(d, 1.5, 0)
        wanted.center = {ex, ez, d.ys}
      end
      return
    end
  end
  local to, p = M.crossing(id)
  if to then
    set_layer(to)
    engine.emit(to == 0 and "underground_exit" or "underground_enter", id)
    -- Wanted, they saw where you went: in at the portal.
    local wanted = require "lib.wanted"
    if to ~= 0 and wanted.stars() > 0 then
      if p then
        local ex, ez = hall_xz(p.outside[1], p.outside[2])
        wanted.center = {ex, ez, p.ys}
      else
        local ex, ez = at(-20, 0)
        wanted.center = {ex, ez, T.floor}
      end
    end
  end
  -- The view goes with you (after a respawn, a menu, a cutscene).
  local l = engine.layer(id) or 0
  if engine.view_layer() ~= l then engine.view_layer(l) end
end)

-- ---- cops after you (systems/police) ----------------------------------------
-- As in GTA's tunnels: they follow you down. Up top they make for the
-- portal and drive in; down here they keep to the tunnel, then the hall,
-- toward you; you come back up, they come back out after you.

-- Where (x, z) is down here: "tunnel", "hall", or a zone another system
-- added (M.ZONES: functions of x, z giving a name or nil), and how far
-- down the tunnel. In order from Louhi's portal (M.ORDER): a cop goes zone
-- by zone toward yours, by M.LEAVE[its zone](x, z, way), or within yours by
-- M.WITHIN[it](x, z, px, pz) (its "steer" target and speed).
M.ZONES, M.ORDER, M.LEAVE, M.WITHIN = {}, {tunnel = 1, hall = 2}, {}, {}
local function part(x, z)
  for _, f in ipairs(M.ZONES) do
    local n = f(x, z)
    if n then return n end
  end
  local u, v = local_uv(x, z)
  if u < T.u_end - 1 and math.abs(v) < M.W / 2 + 1 then return "tunnel", u end
  return "hall", u
end
M.part = part

M.LEAVE.tunnel = function(x, z, way)
  local u = local_uv(x, z)
  if way > 0 then
    local tx, tz = at(math.min(u + 15, T.u_end + 8), 0)
    return tx, tz, 16
  end
  local tx, tz = at(u - 15, 0)
  return tx, tz, 16
end
M.LEAVE.hall = function(x, z, way)
  if way < 0 then
    -- Into the tunnel, by the mouth.
    local tx, tz = at(T.u_end + 4, 0)
    if U.dist2d(x, z, tx, tz) < 6 then tx, tz = at(T.u_end - 10, 0) end
    return tx, tz, 10
  end
  local f = M.HALL_ON
  if f then return f(x, z) end
  return nil
end

-- For police.drive_cop: where cop car `id` heads instead of by the roads,
-- and how fast, or nil (both up top: the roads as ever). Also "goal", x,
-- y, z: up top, the roads but to there.
function M.chase(id, sees, px, pz)
  if not T then return nil end
  local you = G.vehicle or G.player
  if not you then return nil end
  local mine, theirs = engine.layer(id) or 0, engine.layer(you) or 0
  if mine == 0 and theirs == 0 then return nil end
  local x, _, z = engine.pos(id)
  local u, v = local_uv(x, z)
  if mine == 0 then
    -- Up top, after them underground: in through the way nearest them.
    local p = M.portal_for(px, pz)
    if p then return p.approach(x, z) end
    local ex, ez = at(-20, 0)
    if U.dist2d(x, z, ex, ez) > 45 then return "goal", ex, T.floor, ez end
    if u < -16 and math.abs(v) > 1.5 then return "steer", ex, ez, 10 end
    local tx, tz = at(math.max(u, -20) + 12, 0)
    return "steer", tx, tz, 12
  end
  local mine_at = part(x, z)
  local goal_order
  if theirs == 0 then
    -- They went back up: out after them, the way nearest them.
    local p = M.portal_for(px, pz)
    goal_order = p and p.order or 0
  else
    local theirs_at = part(px, pz)
    if theirs_at == mine_at then
      local d = U.dist2d(x, z, px, pz)
      local slow = math.max(0, d - 4) * 1.5
      if sees and d < 30 then return "steer", px, pz, math.min(12, slow) end
      if mine_at == "tunnel" then
        local _, pu = part(px, pz)
        local tx, tz = at(pu > u and math.min(u + 15, pu) or math.max(u - 15, pu), 0)
        return "steer", tx, tz, math.min(16, slow)
      end
      local w = M.WITHIN[mine_at]
      if w then
        local tx, tz, sp = w(x, z, px, pz)
        return "steer", tx, tz, math.min(sp, slow)
      end
      return "steer", px, pz, math.min(10, slow)
    end
    goal_order = M.ORDER[theirs_at]
  end
  local way = goal_order > M.ORDER[mine_at] and 1 or -1
  local tx, tz, sp = M.LEAVE[mine_at](x, z, way)
  if not tx then return "steer", px, pz, 10 end
  return "steer", tx, tz, sp
end

-- The way in nearest (x, z): another portal (M.PORTALS) if (x, z) is
-- nearer it by the zones' order, or nil (Louhi's).
function M.portal_for(x, z)
  if #M.PORTALS == 0 or not T then return nil end
  local you = G.vehicle or G.player
  local o
  if you and engine.exists(you) and (engine.layer(you) or 0) ~= 0 then
    o = M.ORDER[part(x, z)] or 0
  else
    -- (Up top: whichever way in is nearer.)
    local best, bd = nil, U.dist2d(x, z, at(-20, 0))
    for _, p in ipairs(M.PORTALS) do
      local d = U.dist2d(x, z, hall_xz(p.outside[1], p.outside[2]))
      if d < bd then best, bd = p, d end
    end
    return best
  end
  local best
  for _, p in ipairs(M.PORTALS) do
    if math.abs(p.order - o) < (best and math.abs(best.order - o) or o) then best = p end
  end
  return best
end

-- The way in, 20 m out in the street: the one nearest you.
function M.portal()
  local you = G.vehicle or G.player
  if you and engine.exists(you) then
    local x, _, z = engine.pos(you)
    local p = M.portal_for(x, z)
    if p then return hall_xz(p.outside[1], p.outside[2]) end
  end
  return at(-20, 0)
end

function M.down(id)
  id = id or G.vehicle or G.player
  return id ~= nil and engine.exists(id) and (engine.layer(id) or 0) ~= 0
end

-- Out of the car, or into one, down here: still Louhi's.
engine.on("vehicle_exit", function(car)
  if G.player and M.took[car] then M.took[G.player] = true end
end)
engine.on("vehicle_enter", function(car)
  local x, _, z = engine.pos(car)
  if M.took[car] == nil and engine.layer(car) == M.LAYER and x and M.inside(x, z) then M.took[car] = true end
end)

function M.frame() return T end
M.local_uv = function(x, z) return local_uv(x, z) end
M.at = function(u, v) return at(u, v) end

return M
