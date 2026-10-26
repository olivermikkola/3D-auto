-- Ambient traffic: cars wander the road graph in the right-hand lane,
-- turning at random at junctions and braking for obstacles. The city is
-- big, so traffic follows the player: cars that end up far away are moved
-- to a street nearer them, out of sight.
local G = require "lib.state"
local U = require "lib.util"
local city = require "lib.city"
local vehicle = require "lib.vehicle"
local signals = require "systems.signals"

local T = {cars = {}}
local LANE, CRUISE = 3.2, 11 -- LANE: how far before a bend a car aims (and its lane on a grid)

-- A car drives the bends of its road from c.from to c.to, aiming at bend
-- c.wp (a grid street has no bends: just its two ends).
local function route(c)
  c.path, c.wp, c.lane = city.path(c.from, c.to), 2, city.lane(c.from, c.to)
end

-- A siren behind (the player's ambulance, fire engine or police car,
-- lib/errand): within YIELD m, going the same way, a car moves PULL m over
-- to the right and slows to YIELD_SPEED, as the law says.
local YIELD, PULL, YIELD_SPEED, PULL_AHEAD = 45, 1.6, 3, 15

local function lane_target(c)
  local a, b = c.path[c.wp - 1], c.path[c.wp]
  local ax, az, bx, bz = a[1], a[2], b[1], b[2]
  local yaw = math.atan(bx - ax, bz - az)
  local rx, rz = U.right(yaw)
  -- Aim a little before the junction (or bend) so turns cut the corner.
  local fx, fz = U.forward(yaw)
  local lane = (c.lane or LANE) + (c.pull or 0) * PULL
  return bx + rx * lane - fx * LANE, bz + rz * lane - fz * LANE
end

local FAR, NEAR = 330, 260 -- recycle beyond FAR; respawn within NEAR
-- At a dead end (the shore, the park) turning back is the only way on.
-- A one-way street that just ends (cut off at the map's edge) has no way
-- on at all: the car is lost, and gets moved to another street.
local function pick_next(c)
  -- A car with a plan (a street racer) takes the next junction on it.
  if c.plan and #c.plan > 0 then
    c.from, c.to = c.to, table.remove(c.plan, 1)
    route(c)
    return
  end
  local opts, back = {}, false
  for _, n in ipairs(city.links(c.to) or {}) do
    if n ~= c.from then opts[#opts + 1] = n else back = true end
  end
  if #opts == 0 and not back then c.lost = true; return end
  -- A car with its own mind (a suspect on the run: systems/vigilante) picks.
  local pick = #opts > 0 and c.choose and c.choose(c, opts)
  c.from, c.to = c.to, pick or opts[math.random(#opts)] or c.from
  route(c)
end

local near_roads -- the roads in reach of where the player was: {map, x, z, roads}

-- Place car c on a random street segment between `min_dist` and NEAR from
-- the player (anywhere in town if there's no player).
local function place(c, min_dist)
  c.lost = nil
  local roads = city.roads()
  local px, _, pz = U.player_pos()
  -- Drawn from the roads with an end in reach: drawn from the whole of
  -- Turku, most of the 40 tries fell kilometres off and a game began with
  -- three or four cars about.
  -- (Listed again once the player is 50 m from where it was last listed:
  -- going through every road took a few ms, and cars respawn in bunches.)
  if px then
    if not (near_roads and near_roads.map == city.map() and U.dist2d(near_roads.x, near_roads.z, px, pz) < 50) then
      local near, reach = {}, NEAR + 200
      for _, r in ipairs(roads) do
        local ax, az = city.pos(r[1])
        local bx, bz = city.pos(r[2])
        if U.dist2d(ax, az, px, pz) < reach or U.dist2d(bx, bz, px, pz) < reach then near[#near + 1] = r end
      end
      near_roads = {map = city.map(), x = px, z = pz, roads = near}
    end
    if #near_roads.roads > 0 then roads = near_roads.roads end
  end
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
    local x, z = ax + (bx - ax) * t + rx * c.lane, az + (bz - az) * t + rz * c.lane
    local d = px and U.dist2d(x, z, px, pz)
    if not px or (d >= min_dist and d <= NEAR) then
      c.speed, c.stuck = 0, 0
      return x, z, yaw, city.height_on(c.from, c.to, x, z)
    end
  end
end

-- What kind of car the n-th one is: mostly ordinary cars, then vans,
-- taxis and the odd sports car. Counted, not rolled, so the random numbers
-- everything else draws stay the same.
local added = 0
local function kind_of(n)
  local h = (n * 2654435761) % 100
  if h < 14 then return "van" elseif h < 24 then return "cab" elseif h < 31 then return "sports" end
end

local function add_car(min_dist)
  local c = {}
  local x, z, yaw, y = place(c, min_dist)
  if not x then return end
  -- Föli buses run in Raisio and Turku
  local map_name = city.map().id
  local is_bus = (map_name == "raisio" or map_name == "turku") and (math.random(8) == 1)
  added = added + 1
  local kind = not is_bus and kind_of(added) or nil
  local mesh = is_bus and "bus" or kind
  local tag = is_bus and "bus" or "car"
  local color
  if kind == "cab" then
    math.random(8) -- as for any car's colour, so the sequence doesn't shift
    color = added % 3 == 0 and 5 or 6 -- black, or now and then white
  end
  c.id = vehicle.spawn(x, z, yaw, color, mesh, tag, y)
  c.is_bus = is_bus
  vehicle.headlights(c.id)
  T.cars[c.id] = c
end

-- Hand a car to the traffic AI. It should stand on a junction; it drives
-- off down one of its roads. Missions use it for cars they want to see wander town:
-- `keep` ones are never recycled out of sight, and `cruise` sets their pace.
-- A car's `choose(c, opts)`, if set, picks the next junction from opts.
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

-- Drive junctions js[1], js[2], ... in order (js[1] the one it's at), then
-- wander as usual.
function T.set_plan(id, js)
  local c = T.cars[id]
  if not c or #js < 2 then return end
  c.from, c.to, c.speed = js[1], js[2], c.speed or 0
  route(c)
  c.plan = {table.unpack(js, 3)}
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

local siren -- the player's vehicle with its siren on, this tick

local function update(id, c, dt)
    local x, y, z = engine.pos(id)
    local tx, tz = lane_target(c)
    if U.dist2d(x, z, tx, tz) < 4 then
      if c.wp < #c.path then c.wp = c.wp + 1 else pick_next(c) end
      if c.lost then c.speed = 0 end
      tx, tz = lane_target(c)
    end
    -- Pulling over: the bend can be far off, so aim PULL_AHEAD m on from
    -- here, on the moved-over lane, or the car would hardly move over.
    if (c.pull or 0) > 0 then
      local a = c.path[c.wp - 1]
      local ax, az = a[1], a[2]
      local yaw = math.atan(tx - ax, tz - az)
      local fx, fz = U.forward(yaw)
      local along = (x - ax) * fx + (z - az) * fz + PULL_AHEAD
      if along < U.dist2d(ax, az, tx, tz) then
        local rx, rz = U.right(yaw)
        local lane = (c.lane or LANE) + c.pull * PULL
        tx, tz = ax + fx * along + rx * lane, az + fz * along + rz * lane
      end
    end
    local yaw = engine.yaw(id)
    local turn = U.angle_diff(yaw, math.atan(tx - x, tz - z))
    local fx, fz = U.forward(yaw)
    -- Brake for anything solid ahead that isn't scenery.
    local want = (c.cruise or CRUISE) * (1 - math.min(math.abs(turn), 1) * 0.6)
    -- A siren behind: pull over and let it by (not a suspect on the run).
    local yielding = false
    if siren and not c.choose then
      local sx, _, sz = engine.pos(siren)
      local dx, dz = sx - x, sz - z
      local d = math.sqrt(dx * dx + dz * dz)
      yielding = d < YIELD and (dx * fx + dz * fz) < -2 and math.cos(U.angle_diff(yaw, engine.yaw(siren))) > 0.5
    end
    c.pull = U.clamp((c.pull or 0) + (yielding and dt or -dt), 0, 1)
    if yielding then want = math.min(want, YIELD_SPEED) end
    -- Lights at the junction ahead: wait at the line on red, and on amber
    -- if there's room to stop (else carry on through). Not a street racer
    -- (a plan) or a suspect on the run (choose): they run the reds.
    c.waiting = false
    if c.wp == #c.path and #c.path >= 2 and not ((c.plan and #c.plan > 0) or c.choose) then
      local a, b = c.path[#c.path - 1], c.path[#c.path]
      local light = signals.state(c.to, math.atan(b[1] - a[1], b[2] - a[2]))
      if light and light ~= "green" then
        local stop = signals.stop_line(c.to)
        local left = U.dist2d(x, z, b[1], b[2]) - stop -- to the line
        local room = c.speed * c.speed / 10 + 1 -- what braking at 5 m/s2 takes
        if left > -1 and (light == "red" or left > room) then
          want = math.min(want, math.max(0, left * 0.8))
          c.waiting = left < 6
        end
      end
    end
    local hit, d = engine.raycast(x + fx * 2.3, y, z + fz * 2.3, fx, 0, fz, 12, id)
    if hit then
      local tag = engine.tag(hit)
      -- Queue behind cars going our way; ignore cross traffic unless it's in our face.
      local vehicle_ahead = tag == "car" or tag == "cop" or tag == "bus" or tag == "pasi"
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
    -- (Not while waiting at a red light, nor in the queue behind one.)
    local queued = c.waiting or (hit and d < 8 and T.cars[hit] and T.cars[hit].waiting) or false
    c.waiting = queued -- (so the queue passes it back, car to car)
    c.stuck = (math.abs(vehicle.speed(id)) < 1 or not vehicle.on_wheels(id)) and not queued and (c.stuck or 0) + dt or 0
    local px, _, pz = U.player_pos()
    if not c.keep and (c.lost or c.stuck > 6 or (px and U.dist2d(x, z, px, pz) > FAR)) then
      local nx, nz, nyaw2, ny = place(c, 90)
      if nx then
        -- On the road it was put on: a bridge's deck, not the river under it.
        engine.set_pos(id, nx, 0.8 + (ny or U.ground(nx, nz)), nz)
        engine.orient(id, nyaw2)
        engine.set_vel(id, 0, 0, 0)
        engine.set_angvel(id, 0, 0, 0)
      end
    end
end

engine.on("tick", function(dt)
  if not G.city then return end
  siren = require("lib.errand").siren_on()
  for id, c in pairs(T.cars) do
    if engine.exists(id) then update(id, c, dt) else T.cars[id] = nil end
  end
end)

T._pick_next = pick_next -- for test.dead_end_probe

return T
