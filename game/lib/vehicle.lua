-- Arcade car model on top of rigid-body physics. With wheels on the ground
-- the script owns speed and steering along the car's real 3D axes (so it
-- climbs ramps); in the air or on its roof, physics alone flies it.
local U = require "lib.util"

local M = {}
M.MAX_SPEED, M.REVERSE, M.ACCEL, M.BRAKE, M.DRAG = 38, 10, 18, 30, 0.12

-- How each kind of vehicle pulls, by tag. With drag, a car levels off at
-- about 109 km/h; the bus at about 75 and Pasi at about 84, and both get
-- there slowly and stop late. top is where the pull runs out, not the
-- speed you reach: that is accel * top / (accel + DRAG * top).
local CAR = {top = M.MAX_SPEED, accel = M.ACCEL, brake = M.BRAKE, reverse = M.REVERSE}
M.CLASSES = {
  car = CAR, cop = CAR, boat = CAR,
  bus = {top = 42, accel = 5, brake = 16, reverse = 6},
  pasi = {top = 44, accel = 6, brake = 18, reverse = 7},
}
-- Cars by their kind of body (lib/prefabs CAR_KINDS): a sports car levels
-- off at about 135 km/h and gets there quickly; a van at about 90.
M.KINDS = {
  sports = {top = 46, accel = 24, brake = 34, reverse = 10},
  van = {top = 34, accel = 12, brake = 24, reverse = 8},
}

function M.class(id)
  local tag = engine.tag(id) or ""
  if tag == "car" then
    local kind = require("lib.prefabs").car_kind(engine.mesh_of(id))
    if kind and M.KINDS[kind] then return M.KINDS[kind] end
  end
  return M.CLASSES[tag] or CAR
end

-- The speed (m/s) a vehicle of this class levels off at on the flat.
function M.top_speed(id)
  local c = M.class(id)
  return c.accel * c.top / (c.accel + M.DRAG * c.top)
end

-- Anything tagged "car" or "cop" or "pasi" or "bus" or "boat" can be driven.
M.tags = {car = true, cop = true, pasi = true, bus = true, boat = true}

-- y is the road's height there when it isn't the ground's (on a bridge,
-- in a tunnel).
function M.spawn(x, z, yaw, color_index, mesh, tag, y)
  local n = color_index or math.random(8)
  -- Another kind of car ("sports", "van", "cab": lib/prefabs) in that colour.
  local prefabs = require "lib.prefabs"
  if mesh and prefabs.CAR_KINDS[mesh] then mesh = mesh .. n end
  local kind = prefabs.CAR_KINDS[prefabs.car_kind(mesh) or ""]
  local is_pasi = mesh == "pasi" or tag == "pasi"
  local is_bus = mesh == "bus" or tag == "bus"
  local is_boat = mesh == "speedboat" or tag == "boat"
  local size = is_pasi and {2.9, 2.5, 7.2} or (is_bus and {2.6, 3.2, 12.2} or (is_boat and {2.4, 1.4, 6.2} or (kind and kind.size or {2.0, 1.4, 4.4})))
  local mass = is_pasi and 13500 or (is_bus and 11500 or (is_boat and 950 or (kind and kind.mass or 1200)))
  local step = (is_pasi or is_bus) and 0.55 or (is_boat and 0.2 or 0.35)
  local id_mesh = mesh or (is_pasi and "pasi" or (is_bus and "bus" or (is_boat and "speedboat" or ("car" .. n))))
  local default_tag = is_pasi and "pasi" or (is_bus and "bus" or (is_boat and "boat" or "car"))
  local lift = is_bus and 1.6 or (is_pasi and 1.25 or (is_boat and 0.3 or (kind and kind.lift or 0.75)))
  local id = engine.spawn{mesh = id_mesh, pos = {x, lift + (y or U.ground(x, z)), z},
                          yaw = yaw or 0, size = size, body = "dynamic", mass = mass, friction = 0,
                          step = step, tag = tag or default_tag}
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

  local c = M.class(id)
  local t = input.throttle or 0
  if t > 0 then
    v = v + (v < 0 and c.brake or c.accel * (1 - v / c.top)) * t * dt
  elseif t < 0 then
    v = v + (v > 0 and -c.brake or -c.accel * (1 + v / c.reverse)) * -t * dt
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

-- Cars nobody is driving have the handbrake on: on a slope they'd roll
-- away otherwise (they have no friction of their own; grip is M.drive's
-- doing). Slow ones are held, so a car knocked flying still flies.
function M.driven(id)
  if id == require("lib.state").vehicle then return true end
  local traffic, police = package.loaded["systems.traffic"], package.loaded["systems.police"]
  local cop = police and police.cops[id]
  return (traffic and traffic.cars[id] ~= nil) or (cop ~= nil and not cop.deployed)
end

engine.on("tick", function()
  if not engine.terrain_height(0, 0) then return end -- flat maps don't need it
  for _, id in ipairs(engine.find("car")) do
    if not M.driven(id) and engine.grounded(id) then
      local vx, vy, vz = engine.vel(id)
      if vx * vx + vz * vz < 9 then engine.set_vel(id, vx * 0.8, vy, vz * 0.8) end
    end
  end
end)

return M
