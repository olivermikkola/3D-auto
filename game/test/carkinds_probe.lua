-- Kinds of car: a sports car, a van and a taxi beside the ordinary car,
-- each its own size and pull, all mixed into traffic.
-- CARKINDS_TEST=1 auto game --headless 3000
local U = require "lib.util"
local city = require "lib.city"
local prefabs = require "lib.prefabs"
local traffic = require "systems.traffic"
local vehicle = require "lib.vehicle"

local function check(ok, what)
  if not ok then engine.quit(); error("CARKINDS TEST FAILED: " .. what, 0) end
  print("  ok  " .. what)
end
local function wait(pred, timeout, what)
  local t = engine.time() + timeout
  while not pred() do
    if engine.time() > t then check(false, what .. " (timed out)") end
    coroutine.yield()
  end
end
local function sleep(s)
  local t = engine.time() + s
  wait(function() return engine.time() >= t end, s + 1, "sleep")
end

local function script()
  sleep(0.5)
  local map = city.map().id or "?"
  local seen = {}
  for id in pairs(traffic.cars) do seen[prefabs.car_kind(engine.mesh_of(id)) or engine.mesh_of(id)] = true end
  check(seen.car and (seen.van or seen.cab or seen.sports), "traffic mixes kinds of car")

  -- Each kind from a standing start, full throttle for 3 s, side by side on
  -- open flat ground (the grid map: it has no hills).
  if not engine.terrain_height(0, 0) then
    for id in pairs(traffic.cars) do engine.despawn(id) end
    traffic.target = nil
    -- The longest straight street, from its start.
    local best, sx, sz, yaw = 0
    for _, r in ipairs(city.roads()) do
      local p = city.path(r[1], r[2])
      for k = 2, #p do
        local l = U.dist2d(p[k - 1][1], p[k - 1][2], p[k][1], p[k][2])
        if l > best then best, sx, sz, yaw = l, p[k - 1][1], p[k - 1][2], math.atan(p[k][1] - p[k - 1][1], p[k][2] - p[k - 1][2]) end
      end
    end
    local fx, fz = U.forward(yaw)
    sx, sz = sx + fx * 12, sz + fz * 12
    local reached = {}
    for _, kind in ipairs{"car", "sports", "van", "cab"} do
      local id = vehicle.spawn(sx, sz, yaw, 2, kind ~= "car" and kind or nil)
      check(prefabs.car_kind(engine.mesh_of(id)) == kind, kind .. " spawns as " .. engine.mesh_of(id))
      local size = prefabs.CAR_KINDS[kind].size
      sleep(0.5)
      local _, y = engine.pos(id)
      check(math.abs(y - size[2] / 2) < 0.15, string.format("%s stands on its wheels (%.2f m up)", kind, y))
      local t = engine.time() + 3
      wait(function()
        vehicle.drive(id, 1 / 60, {throttle = 1})
        return engine.time() >= t
      end, 5, kind .. " drives")
      reached[kind] = vehicle.speed(id)
      engine.despawn(id)
    end
    print(string.format("CARKINDS %s: 3 s from standing: sports %.1f, car %.1f, cab %.1f, van %.1f m/s", map,
      reached.sports, reached.car, reached.cab, reached.van))
    check(reached.sports > reached.car * 1.15 and reached.van < reached.car * 0.8, "sports cars pull hardest, vans least")
    check(math.abs(reached.cab - reached.car) < 0.5, "a taxi drives like a car")
  end
  print("CARKINDS_PROBE " .. map .. ": PASSED")
  engine.quit()
end

local co = coroutine.create(script)
engine.on("tick", function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then engine.quit(); error(err, 0) end
end)
