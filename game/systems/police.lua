-- Police: cop cars that hunt the player while the wanted level is up.
-- They path along the street grid toward the player, switch to direct
-- pursuit once they can see you, and bust you if you stop next to one.
-- Escape by leaving the search circle unseen. Pure Lua, no engine help.
local G = require "lib.state"
local U = require "lib.util"
local city = require "lib.city"
local vehicle = require "lib.vehicle"
local wanted = require "lib.wanted"

local P = {cops = {}}
local COPS_PER_LEVEL = {1, 2, 3, 5, 7}
local SIGHT = 90

function P.build()
  local parts = require("lib.prefabs").car_parts({0.95, 0.95, 0.97})
  parts[#parts + 1] = {mesh = "cube", pos = {0, -0.2, 0.2}, size = {2.03, 0.3, 2.6}, color = {0.08, 0.08, 0.1}}
  parts[#parts + 1] = {mesh = "cube", pos = {0, 0.71, -0.3}, size = {1.2, 0.06, 0.35}, color = {0.2, 0.2, 0.2}}
  engine.mesh("cop", parts)
  engine.mesh("beacon", {{mesh = "cube", size = {0.5, 0.16, 0.3}, color = {1, 1, 1}, emissive = 1}})
end

function P.count()
  local n = 0
  for _ in pairs(P.cops) do n = n + 1 end
  return n
end

function P.is_cop(id) return P.cops[id] ~= nil end

-- ---- spawning ------------------------------------------------------------

local function nearest_node(x, z)
  local L = G.city
  local k = U.clamp(math.floor((x - L.origin) / L.P + 0.5), 0, L.N)
  local l = U.clamp(math.floor((z - L.origin) / L.P + 0.5), 0, L.N)
  return k, l
end

-- An intersection 70-130 m from where the cops think the player is.
local function spawn_point()
  local px, pz = wanted.center[1], wanted.center[2]
  for _ = 1, 40 do
    local k, l = math.random(0, G.city.N), math.random(0, G.city.N)
    local x, z = city.node(k, l)
    local d = U.dist2d(x, z, px, pz)
    if d > 70 and d < 130 and not engine.nearest(x, 1, z, 6) then return x, z, math.atan(px - x, pz - z) end
  end
end

local function spawn_cop()
  local x, z, yaw = spawn_point()
  if not x then return end
  local id = vehicle.spawn(x, z, yaw, nil, "cop", "cop")
  vehicle.headlights(id)
  local c = {id = id, stuck = 0, reverse = 0}
  c.red = engine.spawn{mesh = "beacon", color = {1, 0.1, 0.1}}
  c.blue = engine.spawn{mesh = "beacon", color = {0.1, 0.2, 1}}
  c.siren = engine.play("siren", {loop = true, follow = id})
  P.cops[id] = c
end

local function remove(id)
  local c = P.cops[id]
  if not c then return end
  engine.despawn(c.red)
  engine.despawn(c.blue)
  if c.siren then engine.stop(c.siren) end
  P.cops[id] = nil
end

function P.clear()
  for id in pairs(P.cops) do
    remove(id)
    engine.despawn(id)
  end
end

-- ---- perception ----------------------------------------------------------

local function sees_player(id)
  local target = G.vehicle or G.player
  if not target then return false end
  local x, y, z = engine.pos(id)
  local px, py, pz = engine.pos(target)
  local dx, dy, dz = px - x, py + 0.4 - (y + 1), pz - z
  local d = math.sqrt(dx * dx + dy * dy + dz * dz)
  if d > SIGHT then return false end
  local hit = engine.raycast(x, y + 1, z, dx, dy, dz, d, id)
  return hit == nil or hit == target
end

-- ---- driving -------------------------------------------------------------

local function drive_cop(c, dt)
  local id = c.id
  local x, _, z = engine.pos(id)
  local px, _, pz = U.player_pos()
  local yaw = engine.yaw(id)
  local speed = vehicle.speed(id)
  local dist = U.dist2d(x, z, px, pz)
  local tx, tz, want

  if c.sees and dist < 50 then
    -- Direct pursuit, leading the target a little.
    local vx, _, vz = engine.vel(G.vehicle or G.player)
    tx, tz = px + vx * 0.4, pz + vz * 0.4
    want = dist < 12 and math.max(0, dist - 4) or 30
  else
    -- Follow the grid one intersection at a time toward the player if seen,
    -- otherwise toward the last sighting; once there, search nearby streets.
    local k, l = nearest_node(x, z)
    local gk, gl = nearest_node(wanted.seen and px or wanted.center[1], wanted.seen and pz or wanted.center[2])
    if not c.goal or U.dist2d(x, z, c.goal[1], c.goal[2]) < 9 then
      local dk, dl = gk - k, gl - l
      if dk == 0 and dl == 0 then
        if math.random() < 0.5 then dk = math.random(0, 1) * 2 - 1 else dl = math.random(0, 1) * 2 - 1 end
        if k + dk < 0 or k + dk > G.city.N then dk = -dk end
        if l + dl < 0 or l + dl > G.city.N then dl = -dl end
      end
      if math.abs(dk) >= math.abs(dl) and dk ~= 0 then k = k + (dk > 0 and 1 or -1)
      elseif dl ~= 0 then l = l + (dl > 0 and 1 or -1) end
      c.goal = {city.node(k, l)}
    end
    tx, tz = c.goal[1], c.goal[2]
    -- Slow for the corner coming up at the next intersection.
    want = U.dist2d(x, z, tx, tz) < 22 and 13 or 30
  end

  local diff = U.angle_diff(yaw, math.atan(tx - x, tz - z))
  local throttle = speed < want and 1 or (speed > want + 3 and -1 or 0)
  if math.abs(diff) > 1.1 and speed > 12 then throttle = -1 end
  local input = {throttle = throttle, steer = U.clamp(diff * 2.5, -1, 1), handbrake = math.abs(diff) > 0.9 and speed > 14}

  -- Wedged against something: back up with opposite lock for a second.
  c.stuck = (throttle > 0 and math.abs(speed) < 1.5) and c.stuck + dt or 0
  if c.stuck > 1.2 then c.reverse, c.stuck = 1.0, 0 end
  if c.reverse > 0 then
    c.reverse = c.reverse - dt
    input = {throttle = -1, steer = -input.steer}
  end
  vehicle.drive(id, dt, input)
end

-- ---- the loop ------------------------------------------------------------

local spawn_timer, busted_for = 0, 0

local function busted()
  local fine = math.min(G.cash, 100 + math.floor(G.cash * 0.1))
  G.cash = G.cash - fine
  engine.emit("busted", fine)
  wanted.clear()
  P.clear()
  -- Released on foot outside the station (the start of the game).
  if G.vehicle then
    engine.set_vel(G.vehicle, 0, 0, 0)
    G.vehicle = nil
  elseif G.player then
    engine.despawn(G.player)
  end
  require("lib.player").spawn(G.spawn[1], G.spawn[2], G.spawn[3], 0)
  U.message("BUSTED", 4)
  U.message(string.format("-$%d", fine), 4)
  busted_for = 0
end

engine.on("tick", function(dt)
  -- Cops that are gone, wrecked, or far away get recycled.
  local px, _, pz = U.player_pos()
  if not px then return end
  for id, c in pairs(P.cops) do
    local x, _, z = engine.pos(id)
    local wrecked = not engine.exists(id) or vehicle.upside_down(id)
    c.wrecked_for = wrecked and (c.wrecked_for or 0) + dt or 0
    if not x or c.wrecked_for > 3 or U.dist2d(x, z, px, pz) > 170 then
      remove(id)
      if x then engine.despawn(id) end
    end
  end

  if wanted.stars() == 0 then
    -- Off duty: idle, and leave once out of sight.
    for id, c in pairs(P.cops) do
      local x, _, z = engine.pos(id)
      vehicle.drive(id, dt, {throttle = 0})
      if U.dist2d(x, z, px, pz) > 60 then
        remove(id)
        engine.despawn(id)
      end
    end
    return
  end

  -- Keep the right number of units on the street.
  spawn_timer = spawn_timer - dt
  if spawn_timer <= 0 and P.count() < COPS_PER_LEVEL[wanted.stars()] then
    spawn_timer = 1.5
    spawn_cop()
  end

  local seen, close = false, false
  for id, c in pairs(P.cops) do
    c.siren = c.siren or engine.play("siren", {loop = true, follow = id})
    c.sees = sees_player(id)
    seen = seen or c.sees
    drive_cop(c, dt)
    local x, _, z = engine.pos(id)
    if U.dist2d(x, z, px, pz) < 7 and math.abs(vehicle.speed(id)) < 6 then close = true end
  end

  -- Evasion: unseen and outside the search circle for a few seconds.
  if seen then
    wanted.seen, wanted.unseen_for, wanted.center = true, 0, {px, pz}
  else
    wanted.seen = false
    wanted.unseen_for = wanted.unseen_for + dt
    local outside = U.dist2d(px, pz, wanted.center[1], wanted.center[2]) > wanted.radius()
    if (outside and wanted.unseen_for > 3) or wanted.unseen_for > 30 then
      wanted.clear()
      U.message("LOST THE COPS", 3)
      return
    end
  end

  -- Busted: stopped (or on foot) right next to a cop.
  local slow = G.player ~= nil or math.abs(vehicle.speed(G.vehicle)) < 2
  busted_for = (close and slow) and busted_for + dt or 0
  if busted_for > 1.5 then busted() end
end)

-- Stealing a cop car is its own crime.
engine.on("vehicle_enter", function(id)
  if P.cops[id] then
    remove(id)
    engine.set_visible(id, true)
    wanted.add(1)
  end
end)

engine.on("wanted_changed", function(new)
  if new == 0 then
    for _, c in pairs(P.cops) do engine.stop(c.siren); c.siren = nil end
  end
end)

-- Light bars ride on the roof and alternate red/blue.
engine.on("frame", function()
  local on = math.floor(engine.time() * 6) % 2 == 0
  local active = wanted.stars() > 0
  for id, c in pairs(P.cops) do
    local x, y, z = engine.pos(id)
    local ux, uy, uz = engine.up(id)
    local rx, ry, rz = engine.right(id)
    local fx, fy, fz = engine.forward(id)
    local qx, qy, qz, qw = engine.rot(id)
    for side, light in pairs{[1] = c.red, [-1] = c.blue} do
      local s = side * 0.3
      engine.set_pos(light, x + ux * 0.8 + rx * s - fx * 0.3, y + uy * 0.8 + ry * s - fy * 0.3, z + uz * 0.8 + rz * s - fz * 0.3)
      engine.set_rot(light, qx, qy, qz, qw)
      local lit = active and (on == (side == 1))
      local k = lit and 1 or 0.25
      if side == 1 then engine.set_color(light, k, 0.1 * k, 0.1 * k) else engine.set_color(light, 0.1 * k, 0.2 * k, k) end
    end
  end
end)

-- Blips and the search circle on the minimap.
engine.on("minimap", function(map)
  local blink = math.floor(engine.time() * 4) % 2 == 0
  for id in pairs(P.cops) do
    local x, _, z = engine.pos(id)
    local mx, my = map(x, z)
    engine.rect(mx - 2.5, my - 2.5, 5, 5, blink and 1 or 0.2, 0.1, blink and 0.2 or 1, 1)
  end
  if wanted.stars() > 0 then
    local r = wanted.radius()
    for k = 0, 47 do
      local a = k / 48 * math.pi * 2
      local mx, my = map(wanted.center[1] + math.cos(a) * r, wanted.center[2] + math.sin(a) * r)
      engine.rect(mx - 1, my - 1, 2, 2, 1, 0.3, 0.3, wanted.seen and 0.9 or 0.5)
    end
  end
end)

return P
