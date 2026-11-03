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
  local S = M.STAIRS
  return S ~= nil and along > S.door - margin and along < S.foot + S.bottom + margin
         and math.abs(across - S.mid) < S.w / 2 + 0.5 + margin
end

-- The floor's height at (x, z) down here, or nil outside.
function M.ground(x, z)
  if not M.inside(x, z, 1) then return nil end
  local sy = M.stairs_floor(x, z)
  if sy then return sy end
  local u, v = local_uv(x, z)
  if math.abs(v) < M.W / 2 + 1 and u < T.u_end then return M.floor_at(u) end
  return M.HALL_Y
end

local CONC, CONC2, ASPHALT, LINE, PILLAR = {0.55, 0.55, 0.53}, {0.45, 0.45, 0.44}, {0.2, 0.2, 0.21}, {0.85, 0.85, 0.8}, {0.62, 0.6, 0.56}
local STRIP = {1, 0.97, 0.9}

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
  end
  local slope_end = T.u_end - FLAT_IN
  -- The floor in three: outside the mouth (where you come down), the
  -- slope, the last stretch into the hall.
  local runs = {{-14, 0}, {0, slope_end}, {slope_end, T.u_end + 1}}
  for _, r in ipairs(runs) do
    local y0, y1 = M.floor_at(r[1]), M.floor_at(r[2])
    slab(r[1], r[2], y0, y1, 0, M.W + 1, 1, ASPHALT, true)
    -- walls, the roof, the lit strip down its middle, the middle line
    for _, side in ipairs{-1, 1} do
      slab(r[1], r[2], y0 + M.H, y1 + M.H, side * (M.W / 2 + 0.25), 0.5, M.H, side < 0 and CONC or CONC2, true)
      slab(r[1], r[2], y0 + 0.02, y1 + 0.02, side * (M.W / 2 - 0.6), 0.12, 0.02, LINE)
    end
    slab(r[1], r[2], y0 + M.H + 0.5, y1 + M.H + 0.5, 0, M.W + 1, 0.5, CONC2, true)
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
  box(0, 0, y - 0.5, H.len + 1, H.wid + 1, 1, ASPHALT, true)                -- floor
  box(0, 0, y + M.H + 0.25, H.len + 1, H.wid + 1, 0.5, CONC2, true)          -- ceiling
  -- The far wall, with the door to the stairs up to Kauppatori in it.
  do
    local S = M.STAIRS
    local d0, d1 = S.foot, S.foot + S.bottom
    box((-L2 - 0.5 + d0) / 2, W2 + 0.25, y + M.H / 2, d0 + L2 + 0.5, 0.5, M.H, CONC, true)
    box((d1 + L2 + 0.5) / 2, W2 + 0.25, y + M.H / 2, L2 + 0.5 - d1, 0.5, M.H, CONC, true)
    box((d0 + d1) / 2, W2 + 0.25, y + 2.6 + (M.H - 2.6) / 2, d1 - d0, 0.5, M.H - 2.6, CONC, true)
  end
  for _, s in ipairs{-1, 1} do box(s * (L2 + 0.25), 0, y + M.H / 2, 0.5, H.wid + 1, M.H, CONC2, true) end -- the ends
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
    local S = M.STAIRS                                                                          -- the stairs' door
    return across > W2 / 2 and along > S.foot - 3 and along < S.foot + S.bottom + 3
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

-- ---- on foot, up to Kauppatori (docs/UNDERGROUND.md, piece 3) ----------------
-- Louhi's stair house on Kauppatori's west end (OSM way 1034479364, its
-- door on the west side, node on way 1193257272) stands just past the
-- hall's far wall. Down here: from the hall's far wall a door, then up a
-- flight of stairs alongside the wall to a landing at street height behind
-- that door. Through it (on foot) you're up on the square, and back.
-- All of it in the hall's frame: along its long axis, across it (+ away
-- from the tunnel).
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

local function stairs_frame()
  -- The door (OSM): in the stair house's west wall, 19.3 m along, 20.1 across.
  local door, dc = 19.27, 20.1
  local ys = U.ground(hall_xz(door - 0.8, dc))
  local w = 2.9
  local mid = M.HALL.wid / 2 + 0.5 + w / 2 -- (the hall's far wall is the stairs' inner one)
  local rise = ys - M.HALL_Y
  local n = math.max(2, math.ceil(rise / 0.17))
  local top = door + 2.3                  -- the landing behind the door
  local foot = top + n * 0.29             -- the flight, 0.29 m treads
  M.STAIRS = {door = door, dc = dc, ys = ys, w = w, mid = mid, n = n, top = top, foot = foot, bottom = 3}
  return M.STAIRS
end

-- The stairs' floor at (x, z), or nil off them.
function M.stairs_floor(x, z)
  local S = M.STAIRS
  if not S then return nil end
  local along, across = hall_ab(x, z)
  if math.abs(across - S.mid) > S.w / 2 + 0.3 or along < S.door - 0.1 or along > S.foot + S.bottom then return nil end
  if along <= S.top then return S.ys end
  if along >= S.foot then return M.HALL_Y end
  return S.ys + (M.HALL_Y - S.ys) * (along - S.top) / (S.foot - S.top)
end

local function build_stairs()
  local S = M.STAIRS
  local H = M.HALL
  local yaw = math.atan(H.a[1], H.a[2])
  local parts, solids = {}, {}
  local function box(along, across, cy, l, w, h, color, solid, emissive, pitch)
    local x, z = hall_xz(along, across)
    local p = {mesh = "cube", pos = {x, cy, z}, yaw = yaw, pitch = pitch, size = {w, h, l}, color = color, emissive = emissive}
    parts[#parts + 1] = p
    if solid then solids[#solids + 1] = p end
  end
  -- A slab from (a0, y0) to (a1, y1) along, its top on that line.
  local function slab(a0, a1, y0, y1, across, w, h, color, solid, emissive)
    local da, dy = a1 - a0, y1 - y0
    local len = math.sqrt(da * da + dy * dy)
    local pitch = math.atan(dy, da)
    local cy = (y0 + y1) / 2 - h / 2 * math.cos(pitch)
    box((a0 + a1) / 2, across, cy, len, w, h, color, solid, emissive, -pitch)
  end
  local ys, y, mid, w, top, foot, far = S.ys, M.HALL_Y, S.mid, S.w, S.top, S.foot, S.foot + S.bottom
  local TILE, STEP = {0.62, 0.6, 0.57}, {0.5, 0.49, 0.47}
  local CEIL = 3.0
  -- the landing, the bottom, and the flight between: steps to see, a ramp
  -- along their noses underfoot (as the outdoor stairs, roadnet)
  slab(S.door - 0.5, top, ys, ys, mid, w + 0.6, 0.6, TILE, true)
  slab(foot, far + 0.5, y, y, mid, w + 0.6, 0.6, TILE, true)
  local rise = (ys - y) / S.n
  for k = 0, S.n - 1 do
    local t = ys - k * rise
    box(top + (k + 0.5) * 0.29, mid, t - 0.3, 0.3, w, 0.6, k % 2 == 0 and STEP or TILE)
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
  local sx, sz = hall_xz((foot + far) / 2, H.wid / 2 - 0.05)
  local sign_yaw = math.atan(-T.bx, -T.bz)
  box((foot + far) / 2, H.wid / 2 - 0.02, y + 3.1, S.bottom, 0.04, 0.5, {0.1, 0.3, 0.75})
  parts[#parts + 1] = {text = "KAUPPATORI", pos = {sx - T.bx * 0.03, y + 3.1, sz - T.bz * 0.03}, yaw = sign_yaw, height = 0.32,
                       depth = 0.02, color = {1, 1, 1}, emissive = 0.4}
  return parts, solids
end

-- Up top: the stair house's door, dark glass in a light frame, LOUHI and
-- the blue P over it.
local function build_stair_door()
  local S = M.STAIRS
  local H = M.HALL
  local ax, az = H.a[1], H.a[2]
  local yaw = math.atan(ax, az)
  local face = math.atan(-ax, -az)
  local parts = {}
  local function box(along, across, cy, l, w, h, color, emissive)
    local x, z = hall_xz(along, across)
    parts[#parts + 1] = {mesh = "cube", pos = {x, cy, z}, yaw = yaw, size = {w, h, l}, color = color, emissive = emissive}
  end
  local d, dc, ys = S.door - 0.04, S.dc, S.ys
  box(d, dc, ys + 1.15, 0.1, 1.7, 2.45, {0.85, 0.85, 0.82})  -- frame
  box(d - 0.03, dc, ys + 1.1, 0.06, 1.4, 2.2, {0.1, 0.12, 0.14}) -- glass
  box(d - 0.03, dc, ys + 2.75, 0.06, 2.6, 0.5, {0.12, 0.13, 0.15})
  local tx, tz = hall_xz(d - 0.08, dc - 0.35)
  parts[#parts + 1] = {text = "LOUHI", pos = {tx, ys + 2.75, tz}, yaw = face, height = 0.35, depth = 0.03, color = {0.95, 0.95, 0.92},
                       emissive = 0.6}
  box(d - 0.05, dc + 0.95, ys + 2.75, 0.06, 0.42, 0.42, {0.1, 0.3, 0.75})
  local px, pz = hall_xz(d - 0.09, dc + 0.95)
  parts[#parts + 1] = {text = "P", pos = {px, ys + 2.75, pz}, yaw = face, height = 0.32, depth = 0.02, color = {1, 1, 1}}
  local o = {hall_xz(S.door, dc)}
  for _, p in ipairs(parts) do p.pos = {p.pos[1] - o[1], p.pos[2] - ys, p.pos[3] - o[2]} end
  engine.mesh("louhi_stair_door", parts)
  engine.spawn{mesh = "louhi_stair_door", pos = {o[1], ys, o[2]}, tag = "building"}
end

-- Through the stair house's door on foot: where `id` goes (layer, x, z),
-- or nil.
function M.door_crossing(id)
  local S = M.STAIRS
  if not S then return nil end
  local x, y, z = engine.pos(id)
  local along, across = hall_ab(x, z)
  local layer = engine.layer(id)
  if layer == 0 and along > S.door - 0.75 and along < S.door + 0.2 and math.abs(across - S.dc) < 0.9 and math.abs(y - S.ys) < 2.5 then
    local nx, nz = hall_xz(S.door + 1.0, across)
    return M.LAYER, nx, nz
  end
  if layer == M.LAYER and M.took[id] and along < S.door + 0.6 and math.abs(across - S.mid) < S.w / 2 + 0.3 and y > S.ys - 1.5 then
    local nx, nz = hall_xz(S.door - 1.1, S.dc)
    return 0, nx, nz
  end
  return nil
end

-- For police officers on foot (systems/police): where `id` walks instead of
-- straight at you, or nil. Through the door and down the stairs after you,
-- or back up.
local function zone(x, z, layer)
  if layer == 0 then return "top" end
  local S = M.STAIRS
  local along, across = hall_ab(x, z)
  if along > S.door - 0.5 and math.abs(across - S.mid) < S.w / 2 + 0.3 then return "stairs", along end
  return "down", along
end
function M.walk(id, px, pz)
  local S = M.STAIRS
  local you = G.vehicle or G.player
  if not S or not you then return nil end
  local x, _, z = engine.pos(id)
  local mine, along = zone(x, z, engine.layer(id) or 0)
  local theirs = zone(px, pz, engine.layer(you) or 0)
  if mine == theirs then return nil end
  local bottom = S.foot + S.bottom / 2
  if mine == "top" then
    local ox, oz = hall_xz(S.door - 1.5, S.dc)
    if U.dist2d(x, z, ox, oz) > 120 then return nil end
    if U.dist2d(x, z, ox, oz) > 1.0 then return ox, oz end
    return hall_xz(S.door + 0.3, S.dc)
  end
  if mine == "stairs" then
    if theirs == "top" then return hall_xz(S.door, S.dc) end
    if along < S.foot then return hall_xz(bottom, S.mid) end
    return hall_xz(bottom, M.HALL.wid / 2 - 3)
  end
  -- down (the hall), after you up the stairs
  local hx, hz = hall_xz(bottom, M.HALL.wid / 2 - 1.5)
  if U.dist2d(x, z, hx, hz) > 1.2 then return hx, hz end
  return hall_xz(bottom, S.mid)
end

-- Parts in one mesh at `o`, and their solids as invisible statics, all in layer 1.
local function place(name, parts, solids, o)
  local baked = {}
  for k, p in ipairs(parts) do
    local q = {}
    for key, val in pairs(p) do q[key] = val end
    q.pos = {p.pos[1] - o[1], p.pos[2] - o[2], p.pos[3] - o[3]}
    baked[k] = q
  end
  engine.mesh(name, baked)
  engine.spawn{mesh = name, pos = o, layer = M.LAYER, tag = "building"}
  for _, p in ipairs(solids) do
    engine.spawn{mesh = "cube", pos = p.pos, yaw = p.yaw, pitch = p.pitch, size = p.size, visible = false, body = "static",
                 tag = "wall", layer = M.LAYER}
  end
end

function M.build(map)
  if not map or map.id ~= "turku" or M.built then return end
  M.built = true
  frame()
  stairs_frame()
  local parts, solids = build_tunnel()
  place("louhi_tunnel", parts, solids, {T.cx, T.floor, T.cz})
  local hp, hs, bays = build_hall()
  place("louhi_hall", hp, hs, {M.HALL.c[1], M.HALL_Y, M.HALL.c[2]})
  M.bays = bays
  local sp, ss = build_stairs()
  local ox, oz = hall_xz(M.STAIRS.door, M.STAIRS.mid)
  place("louhi_stairs", sp, ss, {ox, M.STAIRS.ys, oz})
  build_stair_door()
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

function M.crossing(id)
  local x, y, z = engine.pos(id)
  local u, v = local_uv(x, z)
  local layer = engine.layer(id)
  if layer == 0 and u > M.DOWN_AT and u < 8 and math.abs(v) < M.W / 2 and y < T.floor + 4 then return M.LAYER end
  if layer == M.LAYER and M.took[id] and (u < M.UP_AT and math.abs(v) < M.W / 2 + 1 or not M.inside(x, z, 6)) then return 0 end
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
    local to, nx, nz = M.door_crossing(id)
    if to then
      local _, py = engine.pos(id)
      engine.set_pos(id, nx, py + 0.05, nz)
      set_layer(to)
      engine.emit(to == 0 and "underground_exit" or "underground_enter", id)
      local wanted = require "lib.wanted"
      if to ~= 0 and wanted.stars() > 0 then
        local ex, ez = hall_xz(M.STAIRS.door - 1.5, M.STAIRS.dc)
        wanted.center = {ex, ez, M.STAIRS.ys}
      end
      return
    end
  end
  local to = M.crossing(id)
  if to then
    set_layer(to)
    engine.emit(to == 0 and "underground_exit" or "underground_enter", id)
    -- Wanted, they saw where you went: in at the portal.
    local wanted = require "lib.wanted"
    if to ~= 0 and wanted.stars() > 0 then
      local ex, ez = M.portal()
      wanted.center = {ex, ez, T.floor}
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

-- Where (x, z) is down here: "tunnel" or "hall".
local function part(x, z)
  local u, v = local_uv(x, z)
  if u < T.u_end - 1 and math.abs(v) < M.W / 2 + 1 then return "tunnel", u end
  return "hall", u
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
    -- Up top, after them underground: in through the portal.
    local ex, ez = M.portal()
    if U.dist2d(x, z, ex, ez) > 45 then return "goal", ex, T.floor, ez end
    if u < -16 and math.abs(v) > 1.5 then return "steer", ex, ez, 10 end
    local tx, tz = at(math.max(u, -20) + 12, 0)
    return "steer", tx, tz, 12
  end
  if theirs == 0 then
    -- They went back up: out after them.
    if part(x, z) == "hall" then
      local tx, tz = at(T.u_end + 4, 0)
      if U.dist2d(x, z, tx, tz) < 6 then tx, tz = at(T.u_end - 10, 0) end
      return "steer", tx, tz, 10
    end
    local tx, tz = at(u - 15, 0)
    return "steer", tx, tz, 16
  end
  -- Both down here.
  local d = U.dist2d(x, z, px, pz)
  local slow = math.max(0, d - 4) * 1.5
  if sees and d < 30 then return "steer", px, pz, math.min(12, slow) end
  local mine_at = part(x, z)
  local theirs_at, pu = part(px, pz)
  if mine_at == "tunnel" then
    local to = theirs_at == "hall" and T.u_end + 8 or pu
    local tx, tz = at(to > u and math.min(u + 15, to) or math.max(u - 15, to), 0)
    return "steer", tx, tz, theirs_at == "tunnel" and math.min(16, slow) or 16
  end
  if theirs_at == "tunnel" then
    -- From the hall into the tunnel, by the mouth.
    local tx, tz = at(T.u_end + 4, 0)
    if U.dist2d(x, z, tx, tz) < 6 then tx, tz = at(T.u_end - 10, 0) end
    return "steer", tx, tz, 10
  end
  return "steer", px, pz, math.min(10, slow)
end

-- The way in, 20 m out in the street.
function M.portal() return at(-20, 0) end

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
