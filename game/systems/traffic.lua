-- Ambient traffic: cars wander the street grid in the right-hand lane,
-- turning at random at intersections and braking for obstacles.
local G = require "lib.state"
local U = require "lib.util"
local city = require "lib.city"
local vehicle = require "lib.vehicle"

local T = {cars = {}}
local LANE, CRUISE = 3.2, 11

local function lane_target(c)
  local ax, az = city.node(c.from[1], c.from[2])
  local bx, bz = city.node(c.to[1], c.to[2])
  local yaw = math.atan(bx - ax, bz - az)
  local rx, rz = U.right(yaw)
  -- Aim a little before the intersection centre so turns cut the corner.
  local fx, fz = U.forward(yaw)
  return bx + rx * LANE - fx * LANE, bz + rz * LANE - fz * LANE
end

local function pick_next(c, N)
  local k, l = c.to[1], c.to[2]
  local opts = {}
  for _, d in ipairs{{1, 0}, {-1, 0}, {0, 1}, {0, -1}} do
    local nk, nl = k + d[1], l + d[2]
    local back = nk == c.from[1] and nl == c.from[2]
    if nk >= 0 and nk <= N and nl >= 0 and nl <= N and not back then opts[#opts + 1] = {nk, nl} end
  end
  c.from, c.to = c.to, opts[math.random(#opts)] or c.from
end

-- Place car c on a random street segment, at least `min_dist` from the player.
local function place(c, N, min_dist)
  for _ = 1, 20 do
    local k, l = math.random(0, N - 1), math.random(0, N)
    c.from, c.to = {k, l}, {k + 1, l}
    if math.random() < 0.5 then c.from, c.to = {l, k}, {l, k + 1} end
    if math.random() < 0.5 then c.from, c.to = c.to, c.from end
    local ax, az = city.node(c.from[1], c.from[2])
    local bx, bz = city.node(c.to[1], c.to[2])
    local yaw = math.atan(bx - ax, bz - az)
    local rx, rz = U.right(yaw)
    local t = 0.3 + math.random() * 0.4
    local x, z = ax + (bx - ax) * t + rx * LANE, az + (bz - az) * t + rz * LANE
    local px, _, pz = U.player_pos()
    if not px or U.dist2d(x, z, px, pz) >= min_dist then
      c.speed, c.stuck = 0, 0
      return x, z, yaw
    end
  end
end

function T.start(n)
  for _ = 1, n do
    local c = {}
    local x, z, yaw = place(c, G.city.N, 0)
    c.id = vehicle.spawn(x, z, yaw)
    vehicle.headlights(c.id)
    T.cars[c.id] = c
  end
end

-- The player stole it: it's not traffic any more, and that's a crime.
engine.on("vehicle_enter", function(id)
  if T.cars[id] then
    T.cars[id] = nil
    engine.emit("carjacked", id)
  end
end)

local function update(id, c, dt, N)
    local x, y, z = engine.pos(id)
    local tx, tz = lane_target(c)
    if U.dist2d(x, z, tx, tz) < 4 then
      pick_next(c, N)
      tx, tz = lane_target(c)
    end
    local yaw = engine.yaw(id)
    local turn = U.angle_diff(yaw, math.atan(tx - x, tz - z))
    local fx, fz = U.forward(yaw)
    -- Brake for anything solid ahead that isn't scenery.
    local want = CRUISE * (1 - math.min(math.abs(turn), 1) * 0.6)
    local hit, d = engine.raycast(x + fx * 2.3, y, z + fz * 2.3, fx, 0, fz, 12, id)
    if hit then
      local tag = engine.tag(hit)
      -- Queue behind cars going our way; ignore cross traffic unless it's in our face.
      local vehicle_ahead = tag == "car" or tag == "cop"
      local same_way = vehicle_ahead and math.cos(U.angle_diff(yaw, engine.yaw(hit))) > 0.5
      if tag == "player" or tag == "ped" or same_way or (vehicle_ahead and d < 3) then
        want = d < 5 and 0 or want * (d - 5) / 7
      end
    end
    c.speed = c.speed or 0
    c.speed = c.speed + U.clamp(want - c.speed, -25 * dt, 6 * dt)
    local nyaw = yaw + U.clamp(turn, -1.6 * dt, 1.6 * dt) * U.clamp(c.speed / 4, 0, 1)
    -- Knocked over or airborne: let physics have it until the stuck timer resets it.
    if vehicle.on_wheels(id) then
      engine.set_yaw(id, nyaw)
      local _, vy = engine.vel(id)
      fx, fz = U.forward(nyaw)
      engine.set_vel(id, fx * c.speed, vy, fz * c.speed)
      local wx, _, wz = engine.angvel(id)
      engine.set_angvel(id, wx * 0.8, 0, wz * 0.8)
    end

    -- Wedged somewhere for too long: quietly respawn it out of sight.
    c.stuck = (math.abs(vehicle.speed(id)) < 1 or not vehicle.on_wheels(id)) and (c.stuck or 0) + dt or 0
    if c.stuck > 6 then
      local nx, nz, nyaw2 = place(c, N, 90)
      if nx then
        engine.set_pos(id, nx, 0.8, nz)
        engine.orient(id, nyaw2)
        engine.set_vel(id, 0, 0, 0)
        engine.set_angvel(id, 0, 0, 0)
      end
    end
end

engine.on("tick", function(dt)
  local N = G.city and G.city.N
  if not N then return end
  for id, c in pairs(T.cars) do
    if engine.exists(id) then update(id, c, dt, N) else T.cars[id] = nil end
  end
end)

return T
