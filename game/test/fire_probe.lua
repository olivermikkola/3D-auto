-- Fire probe: a fire engine stands by the fire station (a real one on maps
-- with places); in it, in free roam, a fire breaks out at a real place (a
-- car on a street corner on a map without places) with a clock; the GPS
-- leads there; stopped within reach the hose puts it out (the robot only
-- gets it on once stopped), out of reach it's off;
-- out, it pays by the time left. Left alone it grows; the clock running out
-- or leaving the engine calls it off; a lost engine is back at the station.
-- FIRE_TEST=1 auto game --headless 120000
local G = require "lib.state"
local U = require "lib.util"
local city = require "lib.city"
local gps = require "lib.gps"
local H = require "lib.health"
local input = require "lib.input"
local wanted = require "lib.wanted"
local robot = require "test.robot"
local fire = require "systems.fire"
local traffic = require "systems.traffic"
local peds = require "systems.peds"

for _, name in ipairs{"systems.cashvan", "systems.racer"} do
  local sys = require(name)
  sys.FIRST, sys.EVERY = 1e9, 1e9
end

local function check(ok, what)
  if not ok then engine.quit(); error("FIRE TEST FAILED: " .. what, 0) end
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

engine.on("fire_lost", function(why)
  local x, _, z = engine.pos(G.vehicle or G.player)
  print(string.format("FIRE_PROBE: call lost: %s (at %.0f, %.0f; %s m to go by the GPS)", why, x, z, tostring(gps.left())))
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
  require("lib.daynight").set_hour(13)

  local truck = fire.vehicle()
  check(truck and engine.exists(truck), "a fire engine stands by the station")
  local tx, _, tz = engine.pos(truck)
  local sx, sz, _, name = fire.station()
  check(U.dist2d(tx, tz, sx, sz) < 5, "at " .. name)

  get_in(truck)
  check(fire.in_engine(), "in the fire engine")
  wait(function() return fire.state() == "call" end, fire.FIRST + 3, "on call, a fire breaks out")
  local f = fire.fire_now()
  print(string.format("FIRE_PROBE %s: fire at %s: %s (clock %.0f s)", map, f.where, f.line, f.clock))
  check(f.light and f.siren, "flames lit, siren on")
  gps.update()
  check(gps.target() and gps.target().id == f.marker, "the GPS leads there")
  check(G.errand and G.errand_deadline, "the HUD says where, with a clock")

  -- Left alone it grows.
  local size0 = f.size
  sleep(1)
  check(f.size > size0, "left alone, it grows")

  driver = robot.gps_driver(15, 6)
  local t0 = engine.time()
  local cash0 = G.cash
  wait(function() return fire.spraying() end, f.clock + 5, "the robot gets there by the GPS and the hose comes on")
  print(string.format("FIRE_PROBE %s: there in %.0f s", map, engine.time() - t0))
  check(f.siren == nil, "the siren's off at the fire")
  local left0 = f.left
  sleep(1)
  check(f.left < left0, "the hose knocks it down")
  wait(function() return fire.state() == nil end, fire.PUT_OUT * fire.BIGGEST + 3, "put out")
  local last = fire.last
  check(last and G.cash - cash0 == last.pay + last.bonus,
    string.format("paid $%d with %.0f s to spare", last and last.pay or -1, last and last.left or -1))
  check(G.errand == nil and G.errand_deadline == nil, "done: the HUD's clear")
  driver = nil

  -- Out of reach, the hose is off.
  fire.soon()
  wait(function() return fire.state() == "call" end, 3, "the next fire")
  f = fire.fire_now()
  engine.set_pos(G.vehicle, f.x + 6, 0.75 + U.ground(f.x + 6, f.z), f.z)
  engine.set_vel(G.vehicle, 0, 0, 0)
  sleep(0.2)
  check(fire.spraying(), "stopped by it: the hose is on")
  engine.set_pos(G.vehicle, f.x + fire.REACH + 5, 0.75 + U.ground(f.x + fire.REACH + 5, f.z), f.z)
  sleep(0.2)
  check(not fire.spraying(), "out of reach: the hose is off")

  -- The clock running out burns it down (while nobody sprays).
  engine.set_pos(G.vehicle, f.x + 80, 0.75 + U.ground(f.x + 80, f.z), f.z)
  f.deadline = engine.time() - 1
  sleep(0.1)
  check(fire.state() == nil and said("BURNED DOWN"), "too late: it burned down")
  check(fire.streak() == 0, "and the streak starts over")

  -- Leaving the engine calls it off.
  fire.soon()
  wait(function() return fire.state() == "call" end, 3, "another fire")
  get_out()
  sleep(0.1)
  check(fire.state() == nil and said("YOU LEFT THE FIRE ENGINE"), "leaving the engine calls it off")

  -- A lost engine is back at the station, but not while you're by it.
  engine.despawn(truck)
  fire.RESPAWN = 1
  engine.set_pos(G.player, sx + 30, 1.2 + U.ground(sx + 30, sz), sz)
  sleep(2)
  check(not fire.vehicle(), "not back while you're by the station")
  local fx, fz = sx + 300, sz
  for _, j in ipairs(city.junctions()) do
    local x, z = city.pos(j)
    if U.dist2d(x, z, sx, sz) > 150 then fx, fz = x, z; break end
  end
  engine.set_pos(G.player, fx, 1.2 + U.ground(fx, fz), fz)
  wait(function() local t = fire.vehicle() return t and engine.exists(t) end, 4, "a lost engine is back")
  local nx, _, nz = engine.pos(fire.vehicle())
  check(U.dist2d(nx, nz, sx, sz) < 5, "at the station")
  print("FIRE_PROBE " .. map .. ": PASSED")
  engine.quit()
end

local co = coroutine.create(script)
engine.on("tick", function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then engine.quit(); error(err, 0) end
end)
