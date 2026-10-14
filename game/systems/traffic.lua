-- Ambient traffic: cars wander the road graph in the right-hand lane,
-- turning at random at junctions and braking for obstacles. The city is
-- big, so traffic follows the player: cars that end up far away are moved
-- to a street nearer them, out of sight.
local G = require "lib.state"
local U = require "lib.util"
local city = require "lib.city"
local vehicle = require "lib.vehicle"

local T = {cars = {}}
local LANE, CRUISE = 3.2, 11

-- A car drives the bends of its road from c.from to c.to, aiming at bend
-- c.wp (a grid street has no bends: just its two ends).
local function route(c)
  c.path, c.wp = city.path(c.from, c.to), 2
end

local function lane_target(c)
  local a, b = c.path[c.wp - 1], c.path[c.wp]
  local ax, az, bx, bz = a[1], a[2], b[1], b[2]
  local yaw = math.atan(bx - ax, bz - az)
  local rx, rz = U.right(yaw)
  -- Aim a little before the junction (or bend) so turns cut the corner.
  local fx, fz = U.forward(yaw)
  return bx + rx * LANE - fx * LANE, bz + rz * LANE - fz * LANE
end

local FAR, NEAR = 330, 260 -- recycle beyond FAR; respawn within NEAR

-- At a dead end (the shore, the park) turning back is the only way on.
local function pick_next(c)
  local opts = {}
  for _, n in ipairs(city.links(c.to)) do
    if n ~= c.from then opts[#opts + 1] = n end
  end
  c.from, c.to = c.to, opts[math.random(#opts)] or c.from
  route(c)
end

-- Place car c on a random street segment between `min_dist` and NEAR from
-- the player (anywhere in town if there's no player).
local function place(c, min_dist)
  local roads = city.roads()
  local px, _, pz = U.player_pos()
  for _ = 1, 40 do
    local r = roads[math.random(#roads)]
    c.from, c.to = r[1], r[2]
    local is_oneway = r.oneway or false
    local roll = math.random()
    if not is_oneway and roll < 0.5 then
      c.from, c.to = c.to, c.from
    end
    route(c)
    local t = 0.3 + math.random() * 0.4
    -- Somewhere in the middle of the road: on a bendy one, the bend
    -- that far along, by length.
    if #c.path > 2 then
      local len, segs = 0, {}
      for i = 2, #c.path do
        segs[i] = U.dist2d(c.path[i - 1][1], c.path[i - 1][2], c.path[i][1], c.path[i][2])
        len = len + segs[i]
      end
      local want = t * len
      c.wp = 2
      while c.wp < #c.path and want > segs[c.wp] do want, c.wp = want - segs[c.wp], c.wp + 1 end
      t = want / segs[c.wp]
    end
    local a, b = c.path[c.wp - 1], c.path[c.wp]
    local ax, az, bx, bz = a[1], a[2], b[1], b[2]
    local yaw = math.atan(bx - ax, bz - az)
    local rx, rz = U.right(yaw)
    local x, z = ax + (bx - ax) * t + rx * LANE, az + (bz - az) * t + rz * LANE
    local d = px and U.dist2d(x, z, px, pz)
    if not px or (d >= min_dist and d <= NEAR) then
      c.speed, c.stuck = 0, 0
      return x, z, yaw, city.height_on(c.from, c.to, x, z)
    end
  end
end

local function add_car(min_dist)
  local c = {}
  local x, z, yaw, y = place(c, min_dist)
  if not x then return end
  -- Föli buses run in Raisio and Turku
  local map_name = city.map().id
  local is_bus = (map_name == "raisio" or map_name == "turku") and (math.random(8) == 1)
  local mesh = is_bus and "bus" or nil
  local tag = is_bus and "bus" or "car"
  c.id = vehicle.spawn(x, z, yaw, nil, mesh, tag, y)
  c.is_bus = is_bus
  vehicle.headlights(c.id)
  T.cars[c.id] = c
end

-- Hand a car to the traffic AI. It should stand on a junction; it drives
-- off down one of its roads. Missions use it for cars they want to see wander town:
-- `keep` ones are never recycled out of sight, and `cruise` sets their pace.
function T.adopt(id, opts)
  local x, y, z = engine.pos(id)
  local at = city.nearest(x, z, y)
  local ways = city.links(at)
  local c = {from = at, to = ways[math.random(math.max(1, #ways))] or at, speed = 0, stuck = 0}
  route(c)
  c.keep, c.cruise = opts and opts.keep, opts and opts.cruise
  vehicle.headlights(id)
  T.cars[id] = c
  return c
end

function T.start(n)
  T.target = n
  for _ = 1, n do add_car(0) end
end

-- Wrecked, stolen or blown-up cars are replaced, out of sight.
local topup = 0
engine.on("tick", function(dt)
  topup = topup - dt
  if topup > 0 or not T.target then return end
  topup = 2
  local n = 0
  for _ in pairs(T.cars) do n = n + 1 end
  if n < T.target then add_car(90) end
end)

-- The player stole it: it's not traffic any more, and that's a crime.
engine.on("vehicle_enter", function(id)
  if T.cars[id] then
    T.cars[id] = nil
    engine.emit("carjacked", id)
  end
end)

local function update(id, c, dt)
    local x, y, z = engine.pos(id)
    local tx, tz = lane_target(c)
    if U.dist2d(x, z, tx, tz) < 4 then
      if c.wp < #c.path then c.wp = c.wp + 1 else pick_next(c) end
      tx, tz = lane_target(c)
    end
    local yaw = engine.yaw(id)
    local turn = U.angle_diff(yaw, math.atan(tx - x, tz - z))
    local fx, fz = U.forward(yaw)
    -- Brake for anything solid ahead that isn't scenery.
    local want = (c.cruise or CRUISE) * (1 - math.min(math.abs(turn), 1) * 0.6)
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

    -- Wedged somewhere for too long, or left far behind: quietly respawn it out of sight.
    c.stuck = (math.abs(vehicle.speed(id)) < 1 or not vehicle.on_wheels(id)) and (c.stuck or 0) + dt or 0
    local px, _, pz = U.player_pos()
    if not c.keep and (c.stuck > 6 or (px and U.dist2d(x, z, px, pz) > FAR)) then
      local nx, nz, nyaw2 = place(c, 90)
      if nx then
        engine.set_pos(id, nx, 0.8 + U.ground(nx, nz), nz)
        engine.orient(id, nyaw2)
        engine.set_vel(id, 0, 0, 0)
        engine.set_angvel(id, 0, 0, 0)
      end
    end
end

engine.on("tick", function(dt)
  if not G.city then return end
  for id, c in pairs(T.cars) do
    if engine.exists(id) then update(id, c, dt) else T.cars[id] = nil end
  end
end)

return T
