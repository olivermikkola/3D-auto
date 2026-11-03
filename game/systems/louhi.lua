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
  return math.abs(along) < H.len / 2 + margin and math.abs(across) < H.wid / 2 + margin
end

-- The floor's height at (x, z) down here, or nil outside.
function M.ground(x, z)
  if not M.inside(x, z, 1) then return nil end
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
  box(0, 0, y - 0.5, H.len + 1, H.wid + 1, 1, ASPHALT, true).floor = true   -- floor
  box(0, 0, y + M.H + 0.25, H.len + 1, H.wid + 1, 0.5, CONC2, true)          -- ceiling
  box(0, W2 + 0.25, y + M.H / 2, H.len + 1, 0.5, M.H, CONC, true)            -- the far wall
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
    return math.abs(along - M.mouth_along) < 6 and math.abs(across) < W2 / 2                   -- the way across
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
  local parts, solids = build_tunnel()
  place("louhi_tunnel", parts, solids, {T.cx, T.floor, T.cz})
  local hp, hs, bays = build_hall()
  place("louhi_hall", hp, hs, {M.HALL.c[1], M.HALL_Y, M.HALL.c[2]})
  M.bays = bays
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
  local id = G.vehicle or G.player
  if not id or not engine.exists(id) then return end
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
