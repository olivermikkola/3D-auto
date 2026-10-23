-- Pöli bus probe: on Turku (real bus stops) a Pöli bus stands at the bus
-- station; in it, in free roam, a route of four real stops comes, people
-- waiting at each; the GPS leads to the next; stood there with the doors
-- open they get on and it pays (less when late); the last stop pays a
-- bonus. Leaving the bus ends the route. Maps without bus stops have no
-- bus. BUS_TEST=1 auto game --headless 120000
local G = require "lib.state"
local U = require "lib.util"
local city = require "lib.city"
local gps = require "lib.gps"
local H = require "lib.health"
local input = require "lib.input"
local wanted = require "lib.wanted"
local robot = require "test.robot"
local busroute = require "systems.busroute"
local vehicle = require "lib.vehicle"
local traffic = require "systems.traffic"
local peds = require "systems.peds"

for _, name in ipairs{"systems.cashvan", "systems.racer"} do
  local sys = require(name)
  sys.FIRST, sys.EVERY = 1e9, 1e9
end

local function check(ok, what)
  if not ok then engine.quit(); error("BUS TEST FAILED: " .. what, 0) end
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

engine.on("bus_route_lost", function(why)
  print("BUS_PROBE: route lost: " .. why)
end)

local driver
input.drive = function()
  if not (G.vehicle and driver) then return 0, 0, true end
  return driver.inputs(G.vehicle)
end

local function get_in(id)
  if G.player then engine.despawn(G.player) end
  G.player, G.vehicle = nil, id
  engine.emit("vehicle_enter", id)
end

local function get_out()
  local x, _, z = engine.pos(G.vehicle)
  G.player = engine.spawn{mesh = "person", pos = {x + 3, 1.2 + U.ground(x + 3, z), z}, size = {0.7, 1.8, 0.7},
                          body = "dynamic", tag = "player"}
  G.vehicle = nil
end

local function said(text)
  for _, m in ipairs(G.messages) do if m.text:find(text, 1, true) then return true end end
  return false
end

-- Stand the bus at stop s, stopped.
local function at_stop(s)
  engine.set_pos(G.vehicle, s[1], 1.6 + U.ground(s[1], s[2]), s[2])
  engine.set_vel(G.vehicle, 0, 0, 0)
end

local function script()
  sleep(0.5)
  local map = city.map().id or city.map().name or "?"
  if not busroute.depot() then
    check(busroute.vehicle() == nil, "no bus stops on " .. map .. ": no Pöli bus")
    print("BUS_PROBE " .. map .. ": PASSED")
    return engine.quit()
  end
  require("lib.borders").crossings = {}
  require("lib.mission").hide_start_markers()
  for id in pairs(traffic.cars) do engine.despawn(id) end
  traffic.cars, traffic.target = {}, nil
  for id in pairs(peds.peds) do engine.despawn(id) end
  peds.peds = {}
  wanted.heat_up = function() end -- (the robot clips things now and then)
  require("lib.daynight").set_hour(13)

  local bus = busroute.vehicle()
  check(bus and engine.exists(bus), "a Pöli bus stands at the bus station")
  local bx, _, bz = engine.pos(bus)
  local dx, dz, _, name = busroute.depot()
  check(U.dist2d(bx, bz, dx, dz) < 5, "at " .. name)

  get_in(bus)
  check(busroute.in_bus(), "in the bus")
  wait(function() return busroute.state() == "route" end, busroute.FIRST + 3, "a route comes")
  local r = busroute.route_now()
  local names = {}
  for k, s in ipairs(r.stops) do names[k] = s[3] end
  print(string.format("BUS_PROBE %s: route %s", map, table.concat(names, " -> ")))
  check(#r.stops == busroute.STOPS, "four stops")
  local seen = {}
  for _, n in ipairs(names) do check(not seen[n], "never a stop twice: " .. n); seen[n] = true end
  check(#r.waiting >= 1, "people wait at the first stop")
  gps.update()
  check(gps.target() and gps.target().id == r.marker, "the GPS leads to it")

  -- The robot drives the bus there by the GPS and stands with the doors open.
  driver = robot.gps_driver(12, 5)
  local t0, cash0 = engine.time(), G.cash
  wait(function() return r.at == 2 end, 150, "the robot gets the bus to the first stop and they get on")
  print(string.format("BUS_PROBE %s: first stop in %.0f s (timetable %.0f s)", map, engine.time() - t0, r.due - t0))
  driver = nil
  check(G.cash > cash0, string.format("they paid ($%d)", G.cash - cash0))

  -- Late at stop 2: less.
  r.due = engine.time() - 1
  local n = #r.waiting
  cash0 = G.cash
  at_stop(r.stops[2])
  wait(function() return r.at == 3 end, busroute.DOORS + 2, "doors open at stop 2")
  check(G.cash - cash0 == math.floor(n * busroute.FARE * busroute.LATE), "late: less pay")

  -- On to the end: the bonus (halved, one stop was late).
  for k = 3, #r.stops do
    at_stop(r.stops[k])
    wait(function() return busroute.state() == nil or r.at == k + 1 end, busroute.DOORS + 2, "doors open at stop " .. k)
  end
  check(busroute.state() == nil and busroute.last and busroute.last.late == 1 and busroute.last.bonus == busroute.BONUS // 2,
        "route done, the bonus halved for a late stop")
  check(G.errand == nil, "the HUD's clear")

  -- Leaving the bus ends the route.
  busroute.soon()
  wait(function() return busroute.state() == "route" end, 3, "the next route")
  get_out()
  sleep(0.1)
  check(busroute.state() == nil and said("YOU LEFT THE BUS"), "leaving the bus ends it")
  print("BUS_PROBE " .. map .. ": PASSED")
  engine.quit()
end

local co = coroutine.create(script)
engine.on("tick", function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then engine.quit(); error(err, 0) end
end)
