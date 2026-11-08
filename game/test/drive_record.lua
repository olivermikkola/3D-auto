-- Drive recorder: a robot drives the map from a bonnet camera while random
-- steering and throttle nudges are mixed into its inputs, and every drawn
-- frame's state goes to stdout as a REC line. With --record the pictures go
-- alongside, one per line, for training a world model outside the game.
-- The nudges matter: a perfect driver's steering is just the road's shape,
-- so nothing could learn what steering itself does. Run:
--   DRIVE_RECORD=1 SHOT_NO_HUD=1 MAP=turku xvfb-run -a auto game --size 128x128 \
--     --frames 1200 --ticks-per-frame 6 --record out.rgb > out.log
-- DRIVE_RECORD_SEED=n: the nudges (default 1).  DRIVE_RECORD_SPEED=m: top speed
-- in m/s (default 17).  DRIVE_RECORD_FOV=deg: camera (default 75).
-- REC,frame,tick,x,y,z,yaw,forward speed,throttle,steer,hardest hit,cut
--   throttle, steer: the mean applied since the previous REC line.
--   hardest hit: the hardest contact since the previous REC line, m/s.
--   cut: 1 when the car was replaced or moved, so this frame doesn't follow
--   from the last one.
local G = require "lib.state"
local U = require "lib.util"
local city = require "lib.city"
local vehicle = require "lib.vehicle"
local input = require "lib.input"
local robot = require "test.robot"
require("lib.menu").IDLE_PAUSE = math.huge -- nobody's at the keys, and that's the point

local SPEED = tonumber(os.getenv("DRIVE_RECORD_SPEED") or "") or 17
local FOV = tonumber(os.getenv("DRIVE_RECORD_FOV") or "") or 75

-- The nudges have their own generator, so changing them can't disturb the
-- game's own random numbers (and through them the traffic).
local state = (math.tointeger(tonumber(os.getenv("DRIVE_RECORD_SEED") or "1")) * 2654435761 + 1) & 0xffffffff
local function rand()
  state = (state * 1664525 + 1013904223) & 0xffffffff
  return state / 4294967296
end

local pts, last_j, driver = {}, nil, nil
local function extend()
  local x, z = city.pos(last_j)
  for _ = 1, 20 do
    local goal = city.random_near(x, z, 500, 1500)
    local js = goal and robot.junctions(last_j, goal)
    if js and #js > 1 then
      robot.lane_points(js, pts)
      last_j = goal
      return true
    end
  end
end

-- A new car on the road at a junction, facing along a fresh route, or false
-- if there's no route from that junction.
local cut = 1
local function place(x, z)
  pts = {}
  driver = robot.driver(pts, SPEED, 7)
  last_j = city.nearest(x, z, U.ground(x, z))
  if not extend() then return false end
  local p, q = pts[1], pts[2]
  local car = vehicle.spawn(p[1], p[2], math.atan(q[1] - p[1], q[2] - p[2]), 1, nil, "car",
    city.height_on(city.nearest(p[1], p[2]), last_j, p[1], p[2]))
  if G.player then engine.despawn(G.player) end
  G.player, G.vehicle = nil, car
  engine.emit("vehicle_enter", car)
  cut = 1
  return true
end

-- Somewhere random, so that different seeds see different parts of town.
local function place_anywhere()
  local js = city.junctions()
  for _ = 1, 50 do
    if place(city.pos(js[1 + math.floor(rand() * #js)])) then return end
  end
  error("DRIVE_RECORD: no junction with a route from it")
end

-- Each nudge holds for a while, then is replaced: usually a small one the
-- robot corrects, sometimes a hard one that can put the car in a wall.
local nudge_for, nudge_steer, nudge_gas = 0, 0, 0
local function nudge(dt)
  nudge_for = nudge_for - dt
  if nudge_for > 0 then return end
  nudge_for = 0.2 + rand() * 0.8
  local size = rand() < 0.15 and 1.0 or 0.35
  nudge_steer = (rand() * 2 - 1) * size
  nudge_gas = rand() < 0.1 and -1 or 0
end

local sum_gas, sum_steer, inputs = 0, 0, 0
input.drive = function()
  if not G.vehicle or not driver then return 0, 0, false end
  if #pts - driver.at < 40 then extend() end
  local gas, steer = driver.inputs(G.vehicle)
  gas, steer = U.clamp(gas + nudge_gas, -1, 1), U.clamp(steer + nudge_steer, -1, 1)
  sum_gas, sum_steer, inputs = sum_gas + gas, sum_steer + steer, inputs + 1
  return gas, steer, false
end

local hit = 0
engine.on("contact", function(a, b, speed)
  if G.vehicle and (a == G.vehicle or b == G.vehicle) then hit = math.max(hit, speed or 0) end
end)

local started, stuck = false, 0
engine.on("tick", function(dt)
  if not started and engine.time() > 0.5 then
    started = true
    place_anywhere()
  end
  if not started then return end
  require("lib.wanted").set(0) -- this is about driving, not the police
  local car = G.vehicle
  if not car or not engine.exists(car) then -- written off
    if not place(city.pos(last_j)) then place_anywhere() end
    return
  end
  nudge(dt)
  driver.backing = math.max(0, driver.backing - dt)
  local vx, _, vz = engine.vel(car)
  stuck = math.sqrt(vx * vx + vz * vz) < 1 and stuck + dt or 0
  if stuck > 4 then -- nose in something it won't back out of: start again further on
    stuck = 0
    driver.at = math.min(#pts, driver.at + 12)
    local p, q = pts[driver.at], pts[math.min(#pts, driver.at + 1)]
    engine.set_pos(car, p[1], U.ground(p[1], p[2]) + 1.5, p[2])
    engine.set_yaw(car, math.atan(q[1] - p[1], q[2] - p[2]))
    engine.set_vel(car, 0, 0, 0)
    cut = 1
  elseif stuck > 2.5 then
    driver.backing = 1
  end
end)

-- (Loaded after lib.camera, so this frame handler has the last word.)
local frame = 0
engine.on("frame", function()
  frame = frame + 1
  local car = G.vehicle
  if not car or not engine.exists(car) then return end
  local x, y, z = engine.pos(car)
  local yaw = engine.yaw(car)
  local fx, fz = U.forward(yaw)
  engine.camera(x + fx * 2.2, y + 1.15, z + fz * 2.2, x + fx * 22, y + 0.2, z + fz * 22, FOV)
  local n = math.max(inputs, 1)
  print(string.format("REC,%d,%d,%.3f,%.3f,%.3f,%.4f,%.3f,%.3f,%.3f,%.2f,%d",
    frame, engine.ticks(), x, y, z, yaw, vehicle.speed(car), sum_gas / n, sum_steer / n, hit, cut))
  sum_gas, sum_steer, inputs, hit, cut = 0, 0, 0, 0, 0
end)
