-- On-foot controls and getting in and out of cars.
local G = require "lib.state"
local U = require "lib.util"
local vehicle = require "lib.vehicle"

local M = {}
local WALK, RUN, JUMP = 5, 10, 8

function M.spawn(x, y, z, yaw)
  G.player = engine.spawn{mesh = "person", pos = {x, y, z}, yaw = yaw or 0, size = {0.7, 1.8, 0.7},
                          body = "dynamic", mass = 80, friction = 0, step = 0.45, lock_rotation = true, tag = "player"}
  return G.player
end

local function walk(dt)
  local id = G.player
  local f = (engine.key("w") and 1 or 0) - (engine.key("s") and 1 or 0)
  local s = (engine.key("d") and 1 or 0) - (engine.key("a") and 1 or 0)
  local _, vy = engine.vel(id)
  local speed = engine.key("shift") and RUN or WALK
  local fx, fz = U.forward(G.cam_yaw)
  local rx, rz = U.right(G.cam_yaw)
  local mx, mz = fx * f + rx * s, fz * f + rz * s
  local len = math.sqrt(mx * mx + mz * mz)
  if len > 0 then
    mx, mz = mx / len * speed, mz / len * speed
    -- Turn the body toward the direction of travel.
    local yaw = engine.yaw(id)
    engine.set_yaw(id, yaw + U.angle_diff(yaw, math.atan(mx, mz)) * math.min(1, dt * 12))
  end
  if engine.key("space") and engine.grounded(id) then vy = JUMP end
  engine.set_vel(id, mx, vy, mz)
end

function M.enter_nearest()
  local x, y, z = engine.pos(G.player)
  local car, best = nil, math.huge
  for tag in pairs(vehicle.tags) do
    local id, d = engine.nearest(x, y, z, 4.5, tag)
    if id and d < best then car, best = id, d end
  end
  if not car then return end
  engine.despawn(G.player)
  G.player = nil
  G.vehicle = car
  engine.emit("vehicle_enter", car)
end

function M.exit()
  local car = G.vehicle
  local x, y, z = engine.pos(car)
  local yaw = engine.yaw(car)
  local rx, rz = U.right(yaw)
  engine.set_angvel(car, 0, 0, 0)
  -- Try the left door, then the right one, then the roof.
  for _, side in ipairs{-1, 1} do
    local px, pz = x + rx * side * 2.0, z + rz * side * 2.0
    if not engine.raycast(x, y, z, rx * side, 0, rz * side, 2.4, car) then
      G.vehicle = nil
      M.spawn(px, y + 0.3, pz, yaw)
      engine.emit("vehicle_exit", car)
      return
    end
  end
  G.vehicle = nil
  M.spawn(x, y + 2.2, z, yaw)
  engine.emit("vehicle_exit", car)
end

engine.on("key", function(k, down)
  if k ~= "e" or not down then return end
  if G.vehicle then M.exit() elseif G.player then M.enter_nearest() end
end)

engine.on("tick", function(dt)
  if G.vehicle then
    vehicle.drive(G.vehicle, dt, {
      throttle = (engine.key("w") and 1 or 0) - (engine.key("s") and 1 or 0),
      steer = (engine.key("a") and 1 or 0) - (engine.key("d") and 1 or 0),
      handbrake = engine.key("space"),
    })
  elseif G.player then
    walk(dt)
  end
end)

return M
