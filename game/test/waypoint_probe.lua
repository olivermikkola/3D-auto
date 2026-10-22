-- Waypoint probe: on the map (M), Enter puts a waypoint under the crosshair
-- and again takes it off, a click puts one under the mouse, Backspace
-- clears it; the GPS heads for it before any blip; the player's car,
-- robot-driven along the GPS line, gets there, the waypoint clears itself
-- and the GPS goes back to the blip. WAYPOINT_TEST=1 auto game --headless 60000
local G = require "lib.state"
local U = require "lib.util"
local city = require "lib.city"
local gps = require "lib.gps"
local menu = require "lib.menu"
local map_viewer = require "lib.map_viewer"
local vehicle = require "lib.vehicle"
local input = require "lib.input"
local robot = require "test.robot"
local traffic = require "systems.traffic"
local peds = require "systems.peds"
local wanted = require "lib.wanted"

for _, name in ipairs{"systems.cashvan", "systems.racer"} do
  local sys = require(name)
  sys.FIRST, sys.EVERY = 1e9, 1e9
end

local function check(ok, what)
  if not ok then engine.quit(); error("WAYPOINT TEST FAILED: " .. what, 0) end
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

local driver
input.drive = function()
  if not (G.vehicle and driver) then return 0, 0, true end
  return driver.inputs(G.vehicle)
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
  wanted.heat_up = function() end -- (the robot clips things now and then)

  -- In a car on a road, with a blip 300+ m off (a mission's goal, say).
  local roads = city.roads()
  local r = roads[math.max(1, #roads // 3)]
  local p = city.path(r[1], r[2])
  local car = vehicle.spawn(p[1][1], p[1][2], math.atan(p[2][1] - p[1][1], p[2][2] - p[1][2]), 1, "car", "car", U.ground(p[1][1], p[1][2]))
  if G.player then engine.despawn(G.player) end
  G.player, G.vehicle = nil, car
  engine.emit("vehicle_enter", car)
  local px, pz = p[1][1], p[1][2]
  local bx, bz, wx, wz
  for _, j in ipairs(city.junctions()) do
    local x, z = city.pos(j)
    local d = U.dist2d(x, z, px, pz)
    if not bx and d > 300 then bx, bz = x, z end
    -- The waypoint: a junction 500-1200 m off (what a small map has).
    if not wx and d > 500 and d < 1200 then
      local route = gps.route_between(px, pz, nil, x, z, nil)
      if route and route.length < 2000 then wx, wz = x, z end
    end
  end
  if not wx then
    for _, j in ipairs(city.junctions()) do
      local x, z = city.pos(j)
      if not wx and U.dist2d(x, z, px, pz) > 200 then wx, wz = x, z end
    end
  end
  local blip = engine.spawn{mesh = "marker", pos = {bx, 2.5 + U.ground(bx, bz), bz}, scale = 5, color = {1, 0.85, 0.1, 0.35}}
  G.markers[#G.markers + 1] = {id = blip, color = {1, 0.85, 0.1}}
  sleep(0.1)
  check(gps.target() and gps.target().id == blip, "no waypoint: the GPS heads for the blip")

  -- On the map: Enter at the crosshair puts one there; again, takes it off.
  engine.emit("key", "m", true)
  check(menu.open and menu.page == "map", "M opens the map")
  map_viewer.draw(engine.screen())
  map_viewer.pan_x, map_viewer.pan_z = wx, wz
  engine.emit("menu_key", "enter", true)
  local w = gps.waypoint
  check(w and U.dist2d(w.x, w.z, wx, wz) < 1, "Enter puts a waypoint at the crosshair")
  engine.emit("menu_key", "enter", true)
  check(gps.waypoint == nil, "Enter on it takes it off")
  -- A click puts one under the mouse (and panning the map isn't a click).
  local cx, cy = engine.cursor()
  map_viewer.mouse_down(cx, cy)
  map_viewer.frame() -- the button's up: a click
  local ex, ez = map_viewer.to_world(cx, cy)
  check(gps.waypoint and U.dist2d(gps.waypoint.x, gps.waypoint.z, ex, ez) < 1, "a click puts one under the mouse")
  engine.emit("menu_key", "backspace", true)
  check(gps.waypoint == nil, "Backspace clears it")
  map_viewer.pan_x, map_viewer.pan_z = wx, wz
  engine.emit("menu_key", "enter", true)
  map_viewer.draw(engine.screen()) -- the route's drawn on the map too
  check(gps.left() and gps.left() > 0, string.format("the map shows the route (%.0f m)", gps.left() or -1))
  engine.emit("key", "m", true)
  check(not menu.open, "M closes the map")

  -- The waypoint goes before the blip; drive there by the GPS.
  sleep(0.5)
  check(gps.target() == gps.waypoint, "the GPS heads for the waypoint, not the blip")
  local length = gps.left()
  print(string.format("WAYPOINT_PROBE %s: driving %.0f m to the waypoint at %.0f, %.0f", map, length, wx, wz))
  driver = robot.gps_driver(14, 6)
  local t0 = engine.time()
  wait(function() return gps.waypoint == nil end, length / 5 + 60, "the robot gets to the waypoint by the GPS")
  driver = nil
  check(true, string.format("there in %.0f s: the waypoint clears itself", engine.time() - t0))
  local said = false
  for _, m in ipairs(G.messages) do if m.text == "WAYPOINT REACHED" then said = true end end
  check(said, "WAYPOINT REACHED")
  sleep(0.5)
  check(gps.target() and gps.target().id == blip, "and the GPS heads for the blip again")
  print("WAYPOINT_PROBE " .. map .. ": PASSED")
  engine.quit()
end

local co = coroutine.create(script)
engine.on("tick", function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then engine.quit(); error(err, 0) end
end)
