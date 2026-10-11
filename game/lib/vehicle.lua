-- Arcade car model on top of rigid-body physics. With wheels on the ground
-- the script owns speed and steering along the car's real 3D axes (so it
-- climbs ramps); in the air or on its roof, physics alone flies it.
local U = require "lib.util"

local M = {}
M.MAX_SPEED, M.REVERSE, M.ACCEL, M.BRAKE, M.DRAG = 38, 10, 18, 30, 0.12

-- Anything tagged "car" or "cop" can be driven.
M.tags = {car = true, cop = true}

function M.spawn(x, z, yaw, color_index, mesh, tag)
  local n = color_index or math.random(8)
  local id = engine.spawn{mesh = mesh or "car" .. n, pos = {x, 0.75, z}, yaw = yaw or 0, size = {2.0, 1.4, 4.4},
                          body = "dynamic", mass = 1200, friction = 0, step = 0.35, tag = tag or "car"}
  return id
end

-- Headlights: one spot riding on the car's nose (lights only show at night).
-- Driven cars get them; parked ones stay dark until someone gets in.
local lit = {}
function M.headlights(id)
  if lit[id] and engine.exists(id) then return end
  lit[id] = engine.light{follow = id, pos = {0, -0.05, 2.3}, dir = {0, -0.12, 1}, cone = 30, radius = 30, intensity = 2.4, color = {1, 0.95, 0.8}}
end

engine.on("vehicle_enter", M.headlights)

-- Forward speed (m/s) along the car's heading.
function M.speed(id)
  local vx, vy, vz = engine.vel(id)
  local fx, fy, fz = engine.forward(id)
  return vx * fx + vy * fy + vz * fz
end

-- Wheels down: touching something below and not tipped past ~60 degrees.
function M.on_wheels(id)
  local _, uy = engine.up(id)
  return engine.grounded(id) and uy > 0.5
end

function M.upside_down(id)
  local _, uy = engine.up(id)
  return uy < 0.2
end

-- input: throttle -1..1, steer -1..1 (positive = left), handbrake bool.
-- Returns false when the car can't be driven (airborne or flipped).
function M.drive(id, dt, input)
  if not M.on_wheels(id) then return false end
  local vx, vy, vz = engine.vel(id)
  local fx, fy, fz = engine.forward(id)
  local rx, ry, rz = engine.right(id)
  local ux, uy, uz = engine.up(id)
  local v = vx * fx + vy * fy + vz * fz
  local side = vx * rx + vy * ry + vz * rz
  local lift = vx * ux + vy * uy + vz * uz

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

  -- Spin about the car's own up axis; damp pitch and roll like suspension.
  local wx, wy, wz = engine.angvel(id)
  local wu = wx * ux + wy * uy + wz * uz
  local k = 0.8
  engine.set_angvel(id, (wx - ux * wu) * k + ux * rate, (wy - uy * wu) * k + uy * rate, (wz - uz * wu) * k + uz * rate)

  -- Kill sideways slip (tyre grip), less with the handbrake on for drifts.
  side = side * (input.handbrake and 0.92 or 0.6)
  engine.set_vel(id, fx * v + rx * side + ux * lift, fy * v + ry * side + uy * lift, fz * v + rz * side + uz * lift)
  return true
end

return M
