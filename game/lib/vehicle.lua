-- Arcade car model. The script owns the steering and speed; the physics
-- engine just moves the box and stops it when it hits things.
local U = require "lib.util"

local M = {}
M.MAX_SPEED, M.REVERSE, M.ACCEL, M.BRAKE, M.DRAG = 38, 10, 18, 30, 0.12

function M.spawn(x, z, yaw, color_index)
  local n = color_index or math.random(8)
  return engine.spawn{mesh = "car" .. n, pos = {x, 0.75, z}, yaw = yaw or 0, size = {2.0, 1.4, 4.4},
                      body = "dynamic", mass = 1200, friction = 0, step = 0.35, tag = "car"}
end

-- Forward speed (m/s) along the car's heading.
function M.speed(id)
  local vx, _, vz = engine.vel(id)
  local fx, fz = U.forward(engine.yaw(id))
  return vx * fx + vz * fz
end

-- input: throttle -1..1, steer -1..1 (positive = left), handbrake bool.
function M.drive(id, dt, input)
  local vx, vy, vz = engine.vel(id)
  local yaw = engine.yaw(id)
  local fx, fz = U.forward(yaw)
  local rx, rz = U.right(yaw)
  local v = vx * fx + vz * fz
  local side = vx * rx + vz * rz

  local t = input.throttle or 0
  if t > 0 then
    v = v + (v < 0 and M.BRAKE or M.ACCEL * (1 - v / M.MAX_SPEED)) * t * dt
  elseif t < 0 then
    v = v + (v > 0 and -M.BRAKE or -M.ACCEL * (1 + v / M.REVERSE)) * -t * dt
  end
  v = v - v * M.DRAG * dt - (input.handbrake and v * 2.5 * dt or 0)
  if t == 0 and math.abs(v) < 0.3 then v = 0 end

  -- Yaw rate scales with speed and fades at high speed for stability.
  local steer = input.steer or 0
  local rate = steer * U.clamp(math.abs(v) / 6, 0, 1) * (1.9 - math.min(math.abs(v), 30) / 30) * (v >= 0 and 1 or -1)
  if input.handbrake then rate = rate * 1.6 end
  yaw = yaw + rate * dt
  engine.set_yaw(id, yaw)

  -- Kill sideways slip (tyre grip), less with the handbrake on for drifts.
  side = side * (input.handbrake and 0.92 or 0.6)
  fx, fz = U.forward(yaw)
  rx, rz = U.right(yaw)
  engine.set_vel(id, fx * v + rx * side, vy, fz * v + rz * side)
end

return M
