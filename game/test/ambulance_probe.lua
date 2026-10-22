-- Ambulance probe: an ambulance stands by the hospital; in it, in free
-- roam, a call comes (someone lying on the pavement at a real place, or a
-- street corner on a map without places) with a clock; the GPS leads there;
-- stopped by them, they're loaded, the siren goes and the GPS leads to the
-- nearest hospital; a knock costs seconds; stopped there, it pays by the
-- time left. The clock running out, or leaving the ambulance, calls it off;
-- a lost ambulance is back at the hospital. AMBULANCE_TEST=1 auto game --headless 120000
local G = require "lib.state"
local U = require "lib.util"
local city = require "lib.city"
local gps = require "lib.gps"
local H = require "lib.health"
local input = require "lib.input"
local wanted = require "lib.wanted"
local robot = require "test.robot"
local ambulance = require "systems.ambulance"
local traffic = require "systems.traffic"
local peds = require "systems.peds"

for _, name in ipairs{"systems.cashvan", "systems.racer"} do
  local sys = require(name)
  sys.FIRST, sys.EVERY = 1e9, 1e9
end

local function check(ok, what)
  if not ok then engine.quit(); error("AMBULANCE TEST FAILED: " .. what, 0) end
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

engine.on("patient_lost", function(why)
  local c = ambulance.call_now()
  local x, _, z = engine.pos(G.vehicle or G.player)
  print(string.format("AMBULANCE_PROBE: call lost: %s (car at %.0f, %.0f; %s m to go by the GPS)", why, x, z, tostring(gps.left())))
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

  local amb = ambulance.vehicle()
  check(amb and engine.exists(amb), "an ambulance stands by the hospital")
  local ax, _, az = engine.pos(amb)
  local hx, hz = city.place("hospital")
  check(U.dist2d(ax, az, hx, hz) < 90, string.format("by it (%.0f m)", U.dist2d(ax, az, hx, hz)))

  get_in(amb)
  check(ambulance.in_ambulance(), "in the ambulance")
  wait(function() return ambulance.state() == "pickup" end, ambulance.FIRST + 3, "on call, a call comes")
  local c = ambulance.call_now()
  print(string.format("AMBULANCE_PROBE %s: call at %s: %s (clock %.0f s, to %s)", map, c.where, c.line, c.clock, c.hospital[3]))
  check(engine.exists(c.patient), "the patient lies there")
  gps.update()
  check(gps.target() and gps.target().id == c.marker, "the GPS leads to them")
  check(G.errand and G.errand_deadline, "the HUD says where, with a clock")

  driver = robot.gps_driver(15, 6)
  local t0 = engine.time()
  wait(function() return ambulance.state() == "ride" end, c.clock + 5, "the robot gets to the patient by the GPS")
  print(string.format("AMBULANCE_PROBE %s: picked up in %.0f s", map, engine.time() - t0))
  check(c.patient == nil and c.siren ~= nil, "loaded, and the siren's on")
  gps.update()
  check(gps.target() and gps.target().id == c.marker, "the GPS leads to the hospital")
  local d0 = c.deadline
  H.damage(G.vehicle, 1)
  check(math.abs(c.deadline - (d0 - ambulance.KNOCK)) < 1e-6, "a knock costs seconds")
  local cash0 = G.cash
  wait(function() return ambulance.state() == nil end, c.deadline - engine.time() + 5, "the robot gets them to hospital in time")
  local last = ambulance.last
  check(last and G.cash - cash0 == last.pay + last.bonus,
    string.format("paid $%d with %.0f s to spare", last and last.pay or -1, last and last.left or -1))
  check(G.errand == nil and G.errand_deadline == nil, "done: the HUD's clear")
  driver = nil

  -- The clock running out calls it off.
  ambulance.soon()
  wait(function() return ambulance.state() == "pickup" end, 3, "the next call comes")
  local p2 = ambulance.call_now().patient
  ambulance.call_now().deadline = engine.time() - 1
  sleep(0.1)
  check(ambulance.state() == nil and not engine.exists(p2) and said("TOO LATE"), "too late: the call's off")
  check(ambulance.streak() == 0, "and the streak starts over")

  -- Leaving the ambulance calls it off.
  ambulance.soon()
  wait(function() return ambulance.state() == "pickup" end, 3, "another call comes")
  get_out()
  sleep(0.1)
  check(ambulance.state() == nil and said("YOU LEFT THE AMBULANCE"), "leaving the ambulance calls it off")

  -- A lost ambulance is back at the hospital, but not while you're by it.
  engine.despawn(amb)
  ambulance.RESPAWN = 1
  engine.set_pos(G.player, hx + 30, 1.2 + U.ground(hx + 30, hz), hz)
  sleep(2)
  check(not ambulance.vehicle(), "not back while you're by the hospital")
  local fx, fz = hx + 300, hz
  for _, j in ipairs(city.junctions()) do
    local x, z = city.pos(j)
    if U.dist2d(x, z, hx, hz) > 150 then fx, fz = x, z; break end
  end
  engine.set_pos(G.player, fx, 1.2 + U.ground(fx, fz), fz)
  wait(function() local a = ambulance.vehicle() return a and engine.exists(a) end, 4, "a lost ambulance is back")
  local nx, _, nz = engine.pos(ambulance.vehicle())
  check(U.dist2d(nx, nz, hx, hz) < 90, "at the hospital")
  print("AMBULANCE_PROBE " .. map .. ": PASSED")
  engine.quit()
end

local co = coroutine.create(script)
engine.on("tick", function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then engine.quit(); error(err, 0) end
end)
