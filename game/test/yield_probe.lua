-- Yield probe: a car ahead going the same way pulls over to the right and
-- slows when the player's siren is on behind it (an ambulance here), and
-- goes back to its lane when it's off; with no siren, or coming the other
-- way, it doesn't. YIELD_TEST=1 auto game --headless 20000
local G = require "lib.state"
local U = require "lib.util"
local city = require "lib.city"
local errand = require "lib.errand"
local vehicle = require "lib.vehicle"
local traffic = require "systems.traffic"
local peds = require "systems.peds"

for _, name in ipairs{"systems.cashvan", "systems.racer", "systems.ambulance", "systems.fire", "systems.vigilante"} do
  local sys = require(name)
  sys.FIRST, sys.EVERY = 1e9, 1e9
end

local function check(ok, what)
  if not ok then engine.quit(); error("YIELD TEST FAILED: " .. what, 0) end
  print("  ok  " .. what)
end
local function sleep(s)
  local t = engine.time() + s
  while engine.time() < t do coroutine.yield() end
end

-- How far right of where it started, across its heading.
local function right_of(id, x0, z0, yaw0)
  local x, _, z = engine.pos(id)
  local rx, rz = U.right(yaw0)
  return (x - x0) * rx + (z - z0) * rz
end

local function script()
  sleep(0.5)
  local map = city.map().id or city.map().name or "?"
  require("lib.borders").crossings = {}
  require("lib.mission").hide_start_markers()
  for id in pairs(traffic.cars) do engine.despawn(id) end
  traffic.cars, traffic.target = {}, nil
  traffic.start = function() end
  for id in pairs(peds.peds) do engine.despawn(id) end
  peds.peds = {}

  -- A long straight road: the longest two-point stretch between junctions.
  local best, bl
  for _, j in ipairs(city.junctions()) do
    for _, n in ipairs(city.links(j)) do
      local p = city.path(j, n)
      if #p == 2 then
        local l = U.dist2d(p[1][1], p[1][2], p[2][1], p[2][2])
        if l > (bl or 0) and l < 400 then best, bl = {j, n}, l end
      end
    end
  end
  check(best and bl > 70, string.format("a straight road (%.0f m)", bl or 0))
  local ax, az = city.pos(best[1])
  local bx, bz = city.pos(best[2])
  local yaw = math.atan(bx - ax, bz - az)
  local fx, fz = U.forward(yaw)
  local rx, rz = U.right(yaw)
  local lane = city.lane(best[1], best[2])

  local function setup(siren_on, behind)
    for id in pairs(traffic.cars) do engine.despawn(id) end
    traffic.cars = {}
    local cx, cz = ax + fx * 30 + rx * lane, az + fz * 30 + rz * lane
    local car = vehicle.spawn(cx, cz, yaw, 1)
    local c = traffic.adopt(car, {keep = true, cruise = 8})
    c.from, c.to = best[1], best[2]
    c.path, c.wp, c.lane = city.path(best[1], best[2]), 2, lane
    engine.orient(car, yaw)
    local amb = G.vehicle
    if not (amb and engine.exists(amb)) then
      amb = vehicle.spawn(ax, az, yaw, 1, "ambulance")
      if G.player then engine.despawn(G.player) end
      G.player, G.vehicle = nil, amb
    end
    local d = behind and -15 or 15
    local ayaw = behind and yaw or yaw + math.pi
    local ox = behind and lane or -lane
    engine.set_pos(amb, cx + fx * d + rx * (ox - lane), 1.2 + U.ground(cx, cz), cz + fz * d + rz * (ox - lane))
    engine.orient(amb, ayaw)
    engine.set_vel(amb, 0, 0, 0)
    local h = siren_on and errand.siren() or nil
    return car, c, cx, cz, h
  end

  local function follow(amb, car, behind)
    -- Keep the ambulance 15 m behind (or ahead, facing it) while the car moves.
    local x, y, z = engine.pos(car)
    local d = behind and -15 or 15
    engine.set_pos(amb, x + fx * d, y + 0.4, z + fz * d)
    engine.set_vel(amb, 0, 0, 0)
  end

  -- No siren: it keeps its lane and its pace.
  local car, c, cx, cz = setup(false, true)
  for _ = 1, 90 do follow(G.vehicle, car, true); coroutine.yield() end
  check((c.pull or 0) == 0 and math.abs(vehicle.speed(car)) > 6, "no siren: it drives on")

  -- Siren behind: it pulls over to the right and slows.
  local h
  car, c, cx, cz, h = setup(true, true)
  check(errand.siren_on() == G.vehicle, "the siren is on")
  for _ = 1, 240 do follow(G.vehicle, car, true); coroutine.yield() end
  local moved = right_of(car, cx, cz, yaw)
  print(string.format("YIELD_PROBE %s: pulled %.1f m right, %.1f m/s", map, moved, vehicle.speed(car)))
  check(c.pull > 0.9 and math.abs(vehicle.speed(car)) <= 3.5, "a siren behind: it slows")
  check(moved > 0.8, "and moves over to the right")

  -- Siren off: back to its lane.
  errand.siren_off(h)
  check(errand.siren_on() == nil, "the siren is off")
  for _ = 1, 120 do follow(G.vehicle, car, true); coroutine.yield() end
  check(c.pull < 0.1, "siren off: back in its lane")

  -- Coming the other way: it doesn't pull over.
  car, c, cx, cz, h = setup(true, false)
  for _ = 1, 60 do coroutine.yield() end
  check((c.pull or 0) == 0, "oncoming: it carries on")
  errand.siren_off(h)
  print("YIELD_PROBE " .. map .. ": PASSED")
  engine.quit()
end

local co = coroutine.create(script)
engine.on("tick", function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then engine.quit(); error(err, 0) end
end)
