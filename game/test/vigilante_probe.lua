-- Vigilante probe: in a police car, in free roam with no stars, a suspect
-- sets off from a junction near you and runs, red on the map, with a
-- clock; the GPS leads to it and the robot catches up; ramming it is no
-- crime; wrecking it pays, and so does boxing it in; each one caught raises
-- the level (faster, and more pay); the clock running out lets it get away;
-- leaving the car or a star ends the shift and the level starts over.
-- VIGILANTE_TEST=1 auto game --headless 120000
local G = require "lib.state"
local U = require "lib.util"
local city = require "lib.city"
local gps = require "lib.gps"
local H = require "lib.health"
local input = require "lib.input"
local vehicle = require "lib.vehicle"
local wanted = require "lib.wanted"
local robot = require "test.robot"
local vigilante = require "systems.vigilante"
local traffic = require "systems.traffic"
local peds = require "systems.peds"

for _, name in ipairs{"systems.cashvan", "systems.racer"} do
  local sys = require(name)
  sys.FIRST, sys.EVERY = 1e9, 1e9
end

local function check(ok, what)
  if not ok then
    engine.quit()
    error("VIGILANTE TEST FAILED: " .. what, 0) end
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

-- Everything said on screen goes to the log too, for when a check fails.
local message = U.message
U.message = function(text, ...)
  print(string.format("VIGILANTE_PROBE: %.1f s: %s", engine.time(), text))
  return message(text, ...)
end

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

-- Put the player's car on the road at junction j, facing along its first road.
local function park_at(j)
  local x, z = city.pos(j)
  local n = city.links(j)[1]
  local nx, nz = city.pos(n)
  local yaw = math.atan(nx - x, nz - z)
  engine.set_pos(G.vehicle, x, 0.75 + U.ground(x, z), z)
  engine.orient(G.vehicle, yaw)
  engine.set_vel(G.vehicle, 0, 0, 0)
end

local function script()
  sleep(0.5)
  local map = city.map().id or city.map().name or "?"
  require("lib.borders").crossings = {}
  require("lib.mission").hide_start_markers()
  for id in pairs(traffic.cars) do engine.despawn(id) end
  traffic.cars, traffic.target = {}, nil
  traffic.start = function() end -- (no new traffic: the suspect drives alone)
  for id in pairs(peds.peds) do engine.despawn(id) end
  peds.peds = {}
  require("lib.daynight").set_hour(13)

  -- A police car, on the road at a junction with roads all round.
  local j0
  for _, j in ipairs(city.junctions()) do
    if #city.links(j) >= 3 then j0 = j; break end
  end
  j0 = j0 or city.junctions()[1]
  local x0, z0 = city.pos(j0)
  local cop = vehicle.spawn(x0, z0, 0, nil, "cop", "cop")
  get_in(cop)
  park_at(j0)
  check(vigilante.in_cop_car() and wanted.stars() == 0, "in a police car, no stars")
  wait(function() return vigilante.state() == "chase" end, vigilante.FIRST + 3, "on patrol, a suspect is called in")
  local s = vigilante.suspect()
  local sx, _, sz = engine.pos(s.id)
  print(string.format("VIGILANTE_PROBE %s: suspect %.0f m off: %s", map, U.dist2d(sx, sz, x0, z0), s.crime))
  check(traffic.cars[s.id] and traffic.cars[s.id].keep, "it drives off as traffic that isn't recycled")
  check(G.errand and G.errand_deadline, "the HUD says so, with a clock")
  gps.update()
  check(gps.target() and gps.target().id == s.id, "the GPS leads to it")

  -- The robot follows the GPS to it (the suspect at a crawl, so this times
  -- the GPS on a moving goal, not the robot's top speed).
  check(traffic.cars[s.id].choose == vigilante.flee, "it picks its own way at junctions")

  -- On the run: of the roads out of a junction it takes the one away from
  -- you (always, with SMART and SMART_MAX at 1), through traffic's own pick.
  local smart, smart_max = vigilante.SMART, vigilante.SMART_MAX
  vigilante.SMART, vigilante.SMART_MAX = 1, 1
  local jf
  local px, _, pz = U.player_pos()
  for _, j in ipairs(city.junctions()) do
    local x, z = city.pos(j)
    if #city.links(j) >= 3 and U.dist2d(x, z, px, pz) > 80 then jf = j; break end
  end
  check(jf, "a junction to test that on")
  do
    local fake = {from = city.links(jf)[1], to = jf, choose = vigilante.flee, speed = 0, stuck = 0}
    local opts, far, fd = {}, nil, -1
    for _, n in ipairs(city.links(jf)) do
      if n ~= fake.from then
        opts[#opts + 1] = n
        local x, z = city.pos(n)
        if U.dist2d(x, z, px, pz) > fd then far, fd = n, U.dist2d(x, z, px, pz) end
      end
    end
    traffic._pick_next(fake)
    check(fake.to == far, "at a junction it takes the road away from you")
  end
  vigilante.SMART, vigilante.SMART_MAX = smart, smart_max

  -- Off the chase's clock: the suspect called in can be across the
  -- river, a long way round by the bridges, and got away before then.
  s.cruise = 5
  s.deadline = engine.time() + 200
  local heat_up = wanted.heat_up
  wanted.heat_up = function() end -- (the robot clips things now and then)
  driver = robot.gps_driver(15, 6)
  local t0 = engine.time()
  wait(function()
    local x, _, z = engine.pos(s.id)
    local px, _, pz = U.player_pos()
    return U.dist2d(x, z, px, pz) < 30
  end, 180, "the robot catches up with it by the GPS")
  print(string.format("VIGILANTE_PROBE %s: caught up in %.0f s", map, engine.time() - t0))
  driver = nil
  wanted.heat_up = heat_up

  -- Ramming it is no crime (ramming another car is).
  engine.set_vel(G.vehicle, 12, 0, 0)
  local heat = wanted.heat
  engine.emit("contact", G.vehicle, s.id, 15)
  check(wanted.heat == heat and wanted.stars() == 0, "ramming the suspect is no crime")

  -- Wrecking it pays, and the next is level 2.
  local cash0 = G.cash
  H.damage(s.id, 1e6, G.vehicle)
  check(vigilante.state() == nil and vigilante.last and vigilante.last.how == "SUSPECT WRECKED", "wrecked: caught")
  check(G.cash - cash0 == vigilante.PAY, string.format("paid $%d", G.cash - cash0))
  check(vigilante.level() == 2 and G.errand == nil, "level 2, and the HUD's clear")

  -- Boxed in: it stops with you on its bumper and gives up.
  park_at(j0)
  vigilante.soon()
  wait(function() return vigilante.state() == "chase" end, 3, "the next suspect is called in")
  s = vigilante.suspect()
  check(traffic.cars[s.id].cruise > vigilante.CRUISE, "and it runs faster")
  sleep(1)
  traffic.cars[s.id] = nil -- (stopped dead)
  engine.set_vel(s.id, 0, 0, 0)
  local x, y, z = engine.pos(s.id)
  local fx, fz = U.forward(engine.yaw(s.id))
  engine.set_pos(G.vehicle, x + fx * 6, y, z + fz * 6)
  engine.set_vel(G.vehicle, 0, 0, 0)
  cash0 = G.cash
  wait(function() return vigilante.state() == nil end, vigilante.PIN_SECS + 2, "boxed in, the driver gives up")
  check(vigilante.last.how == "SUSPECT ARRESTED" and G.cash - cash0 == 2 * vigilante.PAY,
        string.format("arrested: paid $%d at level 2", G.cash - cash0))
  check(vigilante.level() == 3, "level 3")
  if engine.exists(s.id) then engine.despawn(s.id) end

  -- The clock running out: it gets away; the level stays.
  park_at(j0)
  vigilante.soon()
  wait(function() return vigilante.state() == "chase" end, 3, "another suspect")
  s = vigilante.suspect()
  s.deadline = engine.time() - 1
  sleep(0.1)
  check(vigilante.state() == nil and said("GOT AWAY") and vigilante.level() == 3, "too slow: it got away")
  check(not traffic.cars[s.id] or not traffic.cars[s.id].keep, "and it's plain traffic again")

  -- Leaving the car ends the shift: back to level 1.
  vigilante.soon()
  wait(function() return vigilante.state() == "chase" end, 3, "another suspect")
  get_out()
  sleep(0.1)
  check(vigilante.state() == nil and said("YOU LEFT THE POLICE CAR") and vigilante.level() == 1, "leaving the car ends the shift")

  -- A star ends it too.
  get_in(cop)
  wait(function() return vigilante.state() == "chase" end, vigilante.FIRST + 3, "back in: on patrol again")
  wanted.set(1)
  sleep(0.1)
  check(vigilante.state() == nil and said("THE REAL POLICE WANT YOU"), "a star ends the shift")
  wanted.clear()
  print("VIGILANTE_PROBE " .. map .. ": PASSED")
  engine.quit()
end

local co = coroutine.create(script)
engine.on("tick", function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then engine.quit(); error(err, 0) end
end)
