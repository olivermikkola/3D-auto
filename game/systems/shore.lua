-- The sea, the bay and the river stop you like a wall: drive or walk into
-- water (anywhere but a bridge) and you're put back where it was dry. Only
-- maps with surveyed water have any.
-- And the bank: the ground dips to the water's edge, and a car that runs
-- down it can't climb back out, forwards or back (7 of 16 spots round
-- Turku in test/water_probe). A car of the player's that's being driven
-- but hasn't moved for STUCK_FOR s off the road near the water is put back on the road
-- where it last was, facing along it.
local G = require "lib.state"
local U = require "lib.util"
local roadnet = require "lib.roadnet"
local player = require "lib.player"
local vehicle = require "lib.vehicle"

local STUCK_FOR, NEAR = 3, 15
local dry = {} -- id -> last dry {x, y, z}
local road = {} -- id -> last spot on a road {x, y, z, yaw}
local stuck = 0

local function near_water(x, z)
  if roadnet.wet(x, z) then return true end
  for k = 0, 7 do
    local a = k * math.pi / 4
    if roadnet.wet(x + math.cos(a) * NEAR, z + math.sin(a) * NEAR) then return true end
  end
  return false
end

engine.on("tick", function(dt)
  if not (G.city and G.city.network) then return end
  for _, id in ipairs{G.vehicle or G.player} do
    if engine.exists(id) then
      local x, y, z = engine.pos(id)
      if not roadnet.wet(x, z) then
        dry[id] = {x, y, z}
      elseif dry[id] then
        local d = dry[id]
        engine.set_pos(id, d[1], math.max(y, d[2]), d[3])
        local vx, vy, vz = engine.vel(id)
        engine.set_vel(id, -vx * 0.2, vy, -vz * 0.2)
      end
      if id == G.vehicle then
        local e = roadnet.on_carriageway(x, z, 0, y)
        if e and vehicle.on_wheels(id) then road[id] = {x, y, z, engine.yaw(id)} end
        local throttle = player.throttle or 0
        stuck = (math.abs(throttle) > 0.5 and math.abs(vehicle.speed(id)) < 1) and stuck + dt or 0
        if stuck > STUCK_FOR and not e and road[id] and near_water(x, z) then
          stuck = 0
          local r = road[id]
          engine.set_pos(id, r[1], r[2] + 0.5, r[3])
          engine.orient(id, r[4])
          engine.set_vel(id, 0, 0, 0)
          engine.set_angvel(id, 0, 0, 0)
          U.message("BACK ON THE ROAD", 2)
        end
      end
    end
  end
end)
