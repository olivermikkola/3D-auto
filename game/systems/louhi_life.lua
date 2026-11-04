-- Louhi isn't frozen (docs/UNDERGROUND.md, "Traffic"): while you're down
-- there, a few of its parked cars take turns. One backs out of its bay,
-- drives round to the tunnel and away up it; out of your sight it's gone
-- (layer 2: not drawn, touches nothing) and later comes back down as
-- someone new, drives round the aisles looking for a space and parks, nose
-- in. The P1 sign's green number is the free bays as they are.
--
-- Only the cars made at load (systems/louhi) are moved, never spawned in
-- play (that shifts every later id, and traffic with it), and every choice
-- is a hash, not math.random (that shifts traffic's draws).
local G = require "lib.state"
local U = require "lib.util"
local vehicle = require "lib.vehicle"

local M = {}
M.N = 3            -- cars that come and go
M.SPEED = 3        -- m/s round the hall
M.TUNNEL_SPEED = 6 -- and up and down the tunnel
M.AWAY = 2         -- the layer a car is in while it's gone
M.cars = {}        -- {id, state, ...}
M.moving = {}      -- id -> true while one drives itself (lib/vehicle: no skid)
M.occ = {}         -- bay index -> id parked there
M.active = false

local Lh, T, H, L2, W2, A1, A2

local function hash(i, k)
  local s = (i * 73856093 + k * 19349663) % 2147483648
  s = (s * 1103515245 + 12345) % 2147483648
  return (s % 10007) / 10007
end
local count = 0
local function roll() count = count + 1; return hash(count, 77) end

local function xz(a, c) return Lh.hall_xz(a, c) end
local function bay_xz(b) return xz(b.along, b.across) end
local function bay_yaw(b) return math.atan(T.bx * b.nose, T.bz * b.nose) end
-- The aisle beside a row of bays.
local function aisle_of(b)
  local best, bd = A1, math.huge
  for _, a in ipairs{A1, A2} do
    local d = math.abs(a - b.across)
    if d < bd then best, bd = a, d end
  end
  return best
end

-- The loop round the hall: up aisle 1 (+along), back down aisle 2.
local function loop_from(a, c)
  local E = L2 - 7
  if math.abs(c - A1) < math.abs(c - A2) then
    return {{E, A1}, {E, A2}, {-E, A2}, {-E, A1}}
  end
  return {{-E, A2}, {-E, A1}, {E, A1}, {E, A2}}
end

-- The way out from (a, c): round to aisle 1 short of the mouth, into it, up
-- the tunnel's out lane (keep right: +v going out).
local function way_out(a, c)
  local pts, E, m = {}, L2 - 7, Lh.mouth_along
  local on1 = math.abs(c - A1) < math.abs(c - A2)
  if not on1 then pts = {{-E, A2}, {-E, A1}}
  elseif a > m - 6 then pts = {{E, A1}, {E, A2}, {-E, A2}, {-E, A1}} end
  local out = {}
  for _, p in ipairs(pts) do out[#out + 1] = {xz(p[1], p[2])} end
  out[#out + 1] = {xz(m - 5, A1)}
  out[#out + 1] = {xz(m, -W2 + 1.5)}
  out[#out + 1] = {Lh.at(T.u_end - 6, M.W4)}
  out[#out + 1] = {Lh.at(T.u_end - 130, M.W4)}
  return out
end

-- Is the bay free: nobody parked in it, nothing standing in it?
local function free(i)
  if M.occ[i] then return false end
  local x, z = bay_xz(Lh.bays[i])
  for _, id in pairs{G.vehicle, G.player} do
    if engine.exists(id) and engine.layer(id) == Lh.LAYER then
      local px, _, pz = engine.pos(id)
      if (px - x) ^ 2 + (pz - z) ^ 2 < 3.5 ^ 2 then return false end
    end
  end
  return true
end

local function free_count()
  local n = 0
  for i in ipairs(Lh.bays) do if not M.occ[i] then n = n + 1 end end
  return n
end

-- The sign's number: a mesh per value, made the first time it's needed.
M.meshes = {}
local shown
local function show_free()
  local n = free_count()
  if n == shown then return end
  shown = n
  local name = "louhi_free_" .. n
  if not M.meshes[name] then
    engine.mesh(name, {{text = tostring(n), pos = {0, 0, 0}, yaw = 0, height = 0.36, depth = 0.02,
                        color = {0.2, 1, 0.3}, emissive = 1}})
    M.meshes[name] = true
  end
  if M.sign then engine.set_mesh(M.sign, name) end
end
M.free_count = free_count
function M.shown() return shown end

-- What's in front of `id` within `reach` metres (a lane 2.4 m wide)?
local function blocked(id, reach, back)
  local x, _, z = engine.pos(id)
  local fx, _, fz = engine.forward(id)
  if back then fx, fz = -fx, -fz end
  local function near(o)
    if not o or o == id or not engine.exists(o) or engine.layer(o) ~= Lh.LAYER then return false end
    local ox, _, oz = engine.pos(o)
    local dx, dz = ox - x, oz - z
    local ahead = dx * fx + dz * fz
    return ahead > 0 and ahead < reach and math.abs(dx * fz - dz * fx) < 2.4
  end
  if near(G.vehicle) or (not G.vehicle and near(G.player)) then return true end
  for _, c in ipairs(M.cars) do
    if M.moving[c.id] and near(c.id) then return true end
  end
  local police = package.loaded["systems.police"]
  if police then
    for cid in pairs(police.cops) do if near(cid) then return true end end
    for oid in pairs(police.officers) do if near(oid) then return true end end
  end
  return false
end

-- Drive `id` toward (tx, tz) at `speed`: throttle to the speed, steer at it
-- (positive steer = left; the car's right is (-fz, fx)).
local function steer_to(id, dt, tx, tz, speed)
  local x, _, z = engine.pos(id)
  local fx, _, fz = engine.forward(id)
  local dx, dz = tx - x, tz - z
  local side = -fz * dx + fx * dz      -- + : the target is to the right
  local ahead = fx * dx + fz * dz
  local turn = math.atan(side, ahead)
  local v = vehicle.speed(id)
  local want = speed
  if math.abs(turn) > 0.6 then want = math.min(want, 2) end
  if blocked(id, 7) then want = 0 end
  local t = U.clamp((want - v) * 0.6, -1, 1)
  if want == 0 and v < 0.3 then t = 0 end
  vehicle.drive(id, dt, {throttle = t, steer = U.clamp(-turn * 2.2, -1, 1)})
end

local function hide(c)
  engine.set_layer(c.id, M.AWAY)
  engine.set_vel(c.id, 0, 0, 0)
  M.moving[c.id] = nil
  c.state, c.t = "away", 20 + 40 * roll()
end

-- Where the player is, if down here.
local function player_xz()
  local id = G.vehicle or G.player
  if not id or not engine.exists(id) or engine.layer(id) ~= Lh.LAYER then return nil end
  local x, _, z = engine.pos(id)
  return x, z
end

local function far_from_player(x, z, d)
  local px, pz = player_xz()
  return not px or (px - x) ^ 2 + (pz - z) ^ 2 > d * d
end

-- Is the player in the tunnel (where an arrival would pop in)?
local function player_in_tunnel()
  local px, pz = player_xz()
  if not px then return false end
  local u, v = Lh.local_uv(px, pz)
  return u < T.u_end + 4 and math.abs(v) < Lh.W
end

-- One car's turn.
local function step(c, dt)
  local id = c.id
  if not engine.exists(id) or id == G.vehicle then return false end -- taken, or gone
  -- Off its wheels for 2 s (a moment over a seam in the floor doesn't count): tipped.
  if c.state ~= "away" and c.state ~= "parked" and not vehicle.on_wheels(id) then
    c.off = (c.off or 0) + dt
    if c.off > 2 then return false end
    return true
  end
  c.off = 0
  if c.state == "parked" then
    c.t = c.t - dt
    -- Wanted, nobody leaves (the cops have the aisles).
    if c.t <= 0 and require("lib.wanted").stars() == 0 then
      -- Off the way it'll go: back out, the tail swinging round, till it
      -- faces that way along the aisle (a real driver, not a train).
      local b = Lh.bays[c.bay]
      c.state, c.from = "backing", b.across
      c.path, c.k = way_out(b.along, c.aisle), 1
      local pa = Lh.hall_ab(c.path[1][1], c.path[1][2])
      c.dir = pa >= b.along and 1 or -1
      M.occ[c.bay] = nil
      M.moving[id] = true
      c.bay = nil
    end
  elseif c.state == "backing" then
    local x, _, z = engine.pos(id)
    local _, cc = Lh.hall_ab(x, z)
    local v = vehicle.speed(id)
    local fx, _, fz = engine.forward(id)
    local dx, dz = H.a[1] * c.dir, H.a[2] * c.dir
    local turn = math.atan(-fz * dx + fx * dz, fx * dx + fz * dz) -- + : that way is to the right
    local out_of_bay = math.abs(cc - c.from) > 2.2
    local past = (cc - c.aisle) * (c.aisle - c.from) > 2.5     -- over the aisle's middle, near the far row
    if (out_of_bay and math.abs(turn) < 0.3) or past then
      c.state = "out"
    elseif blocked(id, 6, true) then
      vehicle.drive(id, dt, {throttle = v < -0.3 and 1 or 0, steer = 0})
    else
      -- (going backwards the steering turns the car the other way)
      vehicle.drive(id, dt, {throttle = v > -1.5 and -0.6 or 0, steer = out_of_bay and U.clamp(turn * 2.2, -1, 1) or 0})
    end
  elseif c.state == "out" then
    local p = c.path[c.k]
    local x, _, z = engine.pos(id)
    if (p[1] - x) ^ 2 + (p[2] - z) ^ 2 < 2.5 ^ 2 then
      c.k = c.k + 1
      if not c.path[c.k] then
        if far_from_player(x, z, 70) then hide(c) return true end
        c.k = #c.path -- wait at the end, out of the way, till you're gone
        vehicle.drive(id, dt, {throttle = vehicle.speed(id) > 0.3 and -1 or 0, steer = 0})
        return true
      end
      p = c.path[c.k]
    end
    local u, v = Lh.local_uv(x, z)
    steer_to(id, dt, p[1], p[2], (u < T.u_end - 2 and math.abs(v) < Lh.W) and M.TUNNEL_SPEED or M.SPEED)
  elseif c.state == "away" then
    c.t = c.t - dt
    if c.t <= 0 and require("lib.wanted").stars() == 0 and not player_in_tunnel() then
      local u = T.u_end - 60
      local x, z = Lh.at(u, -M.W4)
      if far_from_player(x, z, 60) then
        engine.set_layer(id, Lh.LAYER)
        engine.set_pos(id, x, Lh.floor_at(u) + vehicle.lift(id), z)
        engine.orient(id, T.yaw, 0, 0)
        engine.set_vel(id, 0, 0, 0)
        engine.set_angvel(id, 0, 0, 0)
        M.moving[id] = true
        local m = Lh.mouth_along
        c.state, c.k, c.looked = "in", 1, 0
        c.path = {{Lh.at(T.u_end - 4, -M.W4)}, {xz(m, -W2 + 3)}, {xz(m + 6, A1)}}
      end
    end
  elseif c.state == "in" then
    -- Down and round, looking: after 10 s of it, the first free bay ahead.
    local x, _, z = engine.pos(id)
    c.looked = c.looked + dt
    if c.looked > 10 then
      local a, cc = Lh.hall_ab(x, z)
      local fx, _, fz = engine.forward(id)
      local dir = (fx * Lh.HALL.a[1] + fz * Lh.HALL.a[2]) > 0 and 1 or -1
      for i, b in ipairs(Lh.bays) do
        local ahead = (b.along - a) * dir
        if math.abs(aisle_of(b) - cc) < 1.5 and ahead > 5 and ahead < 9 and free(i) then
          M.occ[i], c.bay, c.aisle = id, i, aisle_of(b)
          local toward = b.across > c.aisle and 1 or -1 -- across, from the aisle to the bay
          c.state, c.k = "parking", 1
          c.path = {{xz(b.along - dir * 2.5, c.aisle)}, {xz(b.along, b.across - toward * 2.2)}, {xz(b.along, b.across + toward * 0.3)}}
          return true
        end
      end
    end
    local p = c.path[c.k]
    if (p[1] - x) ^ 2 + (p[2] - z) ^ 2 < 2.5 ^ 2 then
      c.k = c.k + 1
      if not c.path[c.k] then
        local a, cc = Lh.hall_ab(x, z)
        c.path, c.k = {}, 1
        for _, q in ipairs(loop_from(a, cc)) do c.path[#c.path + 1] = {xz(q[1], q[2])} end
      end
      p = c.path[c.k]
    end
    local u, v = Lh.local_uv(x, z)
    steer_to(id, dt, p[1], p[2], (u < T.u_end - 2 and math.abs(v) < Lh.W) and M.TUNNEL_SPEED or M.SPEED)
  elseif c.state == "parking" then
    local p = c.path[c.k]
    local x, _, z = engine.pos(id)
    local last = c.k == #c.path
    if (p[1] - x) ^ 2 + (p[2] - z) ^ 2 < (last and 0.8 or 1.5) ^ 2 then
      c.k = c.k + 1
      if not c.path[c.k] then
        -- In: square it up in the bay, handbrake on.
        local b = Lh.bays[c.bay]
        local bx, bz = bay_xz(b)
        engine.set_pos(id, bx, Lh.HALL_Y + vehicle.lift(id), bz)
        engine.orient(id, bay_yaw(b), 0, 0)
        engine.set_vel(id, 0, 0, 0)
        engine.set_angvel(id, 0, 0, 0)
        M.moving[id] = nil
        c.state, c.t = "parked", 60 + 90 * roll()
        return true
      end
      p = c.path[c.k]
    end
    steer_to(id, dt, p[1], p[2], 1.8)
  end
  return true
end

function M.build(louhi)
  Lh, T, H = louhi, louhi.frame(), louhi.HALL
  L2, W2 = H.len / 2, H.wid / 2
  A1, A2 = louhi.AISLES[1], louhi.AISLES[2]
  M.W4 = louhi.W / 4
  -- Who's in which bay (louhi parked them at the bays' middles).
  for _, id in ipairs(louhi.cars) do
    local x, _, z = engine.pos(id)
    for i, b in ipairs(louhi.bays) do
      local bx, bz = bay_xz(b)
      if (bx - x) ^ 2 + (bz - z) ^ 2 < 1 then M.occ[i] = id break end
    end
  end
  -- The ones that come and go: spread down the hall, the first leaving soon.
  local picked = 0
  local ids = {}
  for i, id in pairs(M.occ) do ids[#ids + 1] = {i, id} end
  table.sort(ids, function(p, q) return p[1] < q[1] end)
  for k = 1, #ids, math.max(1, math.floor(#ids / M.N)) do
    if picked >= M.N then break end
    local i, id = ids[k][1], ids[k][2]
    picked = picked + 1
    M.cars[#M.cars + 1] = {id = id, state = "parked", bay = i, aisle = aisle_of(louhi.bays[i]), t = 8 + 25 * (picked - 1)}
  end
  -- The sign's number, on the P1 sign (louhi.SIGN_AT: where and which way).
  local s = louhi.SIGN_AT
  if s then
    show_free()
    M.sign = engine.spawn{mesh = "louhi_free_" .. shown, pos = {s[1], s[2], s[3]}, yaw = s[4], layer = louhi.LAYER, tag = "building"}
  end
end

engine.on("tick", function(dt)
  if not Lh or not Lh.built then return end
  M.active = engine.view_layer() == Lh.LAYER
  if not M.active then return end
  for i = #M.cars, 1, -1 do
    local c = M.cars[i]
    if not step(c, dt) then
      -- Taken, wrecked or gone: out of the turns, its bay to whoever.
      M.moving[c.id] = nil
      if c.bay and M.occ[c.bay] == c.id then M.occ[c.bay] = nil end
      table.remove(M.cars, i)
    end
  end
  -- A parked car someone drove off in: its bay is free.
  for i, id in pairs(M.occ) do
    if not engine.exists(id) or id == G.vehicle then M.occ[i] = nil end
  end
  show_free()
end)

return M
