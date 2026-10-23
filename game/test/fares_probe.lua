-- Taxi fares probe: in a cab in free roam you go on duty and a fare calls
-- from a real place nearby; the GPS leads to them; stopped by them they get
-- in, and the GPS leads on to where they're going (0.4-4 km by road); a
-- knock on the way cuts the tip; stopped there, you're paid by the
-- distance. A star, or leaving the cab, calls a fare off. At night the bars
-- call. Not in an ordinary car, and not on a map without places.
-- FARES_TEST=1 auto game --headless 60000
local G = require "lib.state"
local U = require "lib.util"
local city = require "lib.city"
local gps = require "lib.gps"
local H = require "lib.health"
local vehicle = require "lib.vehicle"
local input = require "lib.input"
local wanted = require "lib.wanted"
local robot = require "test.robot"
local fares = require "systems.fares"
local traffic = require "systems.traffic"
local peds = require "systems.peds"

for _, name in ipairs{"systems.cashvan", "systems.racer"} do
  local sys = require(name)
  sys.FIRST, sys.EVERY = 1e9, 1e9
end

local function check(ok, what)
  if not ok then engine.quit(); error("FARES TEST FAILED: " .. what, 0) end
  print("  ok  " .. what)
end

local function wait(pred, timeout, what)
  local t = engine.time() + timeout
  while not pred() do
    if engine.time() > t then check(false, what .. " (timed out)") end
    coroutine.yield()
  end
end
engine.on("fare_lost", function(why) print("FARES_PROBE: fare lost: " .. why .. " (stars " .. wanted.stars() .. ")") end)
engine.on("wanted_changed", function(level, old) print(string.format("FARES_PROBE: wanted %s -> %s", tostring(old), tostring(level))) end)
if os.getenv("FARES_TRACE") then
  local next_t = 0
  engine.on("tick", function()
    if not G.vehicle or engine.time() < next_t then return end
    next_t = engine.time() + 2
    local x, _, z = engine.pos(G.vehicle)
    local f = fares.fare()
    print(string.format("TRACE t=%.0f %s car %.0f,%.0f v %.1f gps %s stop %s", engine.time(), tostring(fares.state()), x, z,
      vehicle.speed(G.vehicle), tostring(gps.left() and math.floor(gps.left())), f and string.format("%.0f,%.0f", f.stop[1], f.stop[2]) or "-"))
  end)
end

local function sleep(s)
  local t = engine.time() + s
  wait(function() return engine.time() >= t end, s + 1, "sleep")
end

local driver
input.drive = function()
  if not (G.vehicle and driver) then return 0, 0, true end
  return driver.inputs(G.vehicle)
end

local function into(mesh, x, z, yaw)
  local car = vehicle.spawn(x, z, yaw or 0, 6, mesh, "car", U.ground(x, z))
  if G.vehicle then engine.despawn(G.vehicle) end
  if G.player then engine.despawn(G.player) end
  G.player, G.vehicle = nil, car
  engine.emit("vehicle_enter", car)
  return car
end

local function out_of_car()
  local x, _, z = engine.pos(G.vehicle)
  G.player = engine.spawn{mesh = "person", pos = {x + 3, 1.2 + U.ground(x + 3, z), z}, size = {0.7, 1.8, 0.7},
                          body = "dynamic", tag = "player"}
  G.vehicle = nil
end

local function nearest_road_start()
  local x, z = city.place("lot")
  local r = gps.route_between(x, z, nil, x + 1, z + 1, nil)
  local p = r and r.pts[1] or {x, z}
  return p[1], p[2]
end

local function script()
  sleep(0.5)
  local map = city.map().id or city.map().name or "?"
  require("lib.borders").crossings = {}
  require("lib.mission").hide_start_markers()
  for id in pairs(traffic.cars) do engine.despawn(id) end
  traffic.cars, traffic.target = {}, nil
  for id in pairs(peds.peds) do engine.despawn(id) end
  peds.peds = {}
  require("lib.daynight").set_hour(13)
  local x, z = nearest_road_start()

  -- An ordinary car: no fares.
  into("car", x, z)
  sleep(fares.FIRST + 1)
  check(fares.state() == nil, "no fares in an ordinary car")

  into("cab", x, z)
  check(fares.in_cab(), "a cab is a cab")
  if not city.network() then
    sleep(fares.FIRST + 1)
    check(fares.state() == nil, "no places on this map, no fares")
    print("FARES_PROBE " .. map .. ": PASSED")
    engine.quit()
    return
  end
  wait(function() return fares.state() == "pickup" end, fares.FIRST + 3, "on duty, a fare calls")
  local f = fares.fare()
  check(f.pickup.name and f.drop.name, string.format("from %s to %s", f.pickup.name, f.drop.name))
  check(U.dist2d(f.pickup.x, f.pickup.z, x, z) <= 1000, string.format("the pickup is near (%.0f m)", U.dist2d(f.pickup.x, f.pickup.z, x, z)))
  check(engine.exists(f.rider), "the passenger waits there")
  gps.update()
  check(gps.target() and gps.target().id == f.marker, "the GPS leads to the pickup")
  check(G.errand and G.errand:find(f.pickup.name, 1, true), "the HUD says where")

  -- A star calls it off.
  wanted.set(1)
  sleep(0.1)
  check(fares.state() == nil and not engine.exists(f.rider) and not engine.exists(f.marker), "a star calls the fare off")
  wanted.clear()
  wait(function() return fares.state() == "pickup" end, fares.FIRST + 3, "back on duty with no stars, the next fare calls")
  f = fares.fare()

  -- To the pickup and on to the drop, by the GPS. (The robot's driving
  -- isn't clean enough to never clip a pedestrian or a parked car, and a
  -- star calls the fare off: no petty crimes while it drives.)
  local heat_up = wanted.heat_up
  wanted.heat_up = function() end
  local cash0 = G.cash
  driver = robot.gps_driver(14, 6)
  local t0 = engine.time()
  wait(function() return fares.state() == "ride" end, 240, "the robot gets to the pickup by the GPS")
  print(string.format("FARES_PROBE %s: picked up at %s in %.0f s", map, f.pickup.name, engine.time() - t0))
  check(not f.rider and engine.exists(f.marker), "the passenger got in; the drop is marked")
  gps.update()
  check(gps.target() and gps.target().id == f.marker, "the GPS leads to the drop")
  H.damage(G.vehicle, 1)
  check(f.tip < 1, "a knock cuts the tip")
  t0 = engine.time()
  wait(function() return fares.state() == nil end, 600, "the robot gets them there by the GPS")
  local last = fares.last
  check(last and G.cash - cash0 == last.base + last.tip, string.format("paid $%d + $%d tip for %.0f m in %.0f s",
    last.base, last.tip, last.drive, last.took))
  check(last.base >= fares.BASE + fares.PER_KM * 0.4 - 1, "the fare is by the distance")
  check(G.errand == nil and gps.target() == nil, "done: no errand, no route")
  wanted.heat_up = heat_up

  -- Leaving the cab calls a fare off.
  driver = nil
  fares.soon()
  wait(function() return fares.state() == "pickup" end, 3, "another fare calls")
  out_of_car()
  sleep(0.1)
  check(fares.state() == nil, "leaving the cab calls it off")

  -- At night the bars call.
  require("lib.daynight").set_hour(23)
  local night = 0
  for seed = 1, 12 do
    local p = fares.cast(x, z, seed)
    local a = p and p.tags.amenity
    if a == "pub" or a == "bar" or a == "nightclub" then night = night + 1 end
  end
  check(night >= 3, string.format("at night the bars call (%d of 12)", night))
  print("FARES_PROBE " .. map .. ": PASSED")
  engine.quit()
end

local co = coroutine.create(script)
engine.on("tick", function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then engine.quit(); error(err, 0) end
end)
