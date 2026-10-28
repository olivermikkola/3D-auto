-- Taking a bike: beside a rider, enter pulls them off and you ride it away,
-- at a bike's speed and upright; get off, get on again; a bike lying where
-- its rider was knocked off can be picked up too.
-- BIKE_TEST=1 auto game --headless 3000   (MAP=turku)
local G = require "lib.state"
local U = require "lib.util"
local C = require "systems.cyclists"
local player = require "lib.player"
local vehicle = require "lib.vehicle"
local input = require "lib.input"

local function check(ok, what)
  if not ok then engine.quit(); error("BIKE TEST FAILED: " .. what, 0) end
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
  -- Where the cycle paths are thickest, by day.
  local best, bx0, bz0 = 0
  for k, list in pairs(C.cells) do
    local i, j = k:match("^(-?%d+),(-?%d+)$")
    local x, z = (tonumber(i) + 0.5) * 100, (tonumber(j) + 0.5) * 100
    if #list > best and math.abs(x) < 1500 and math.abs(z) < 1500 and not require("lib.roadnet").wet(x, z) then best, bx0, bz0 = #list, x, z end
  end
  require("lib.daynight").set_hour(12)
  local who = G.vehicle or G.player
  engine.set_pos(who, bx0, U.ground(bx0, bz0) + 1.5, bz0)
  wait(function() return next(C.riders) ~= nil end, 30, "riders out")
  local id, c = next(C.riders)
  c.speed = 0
  sleep(0.5)
  local x, y, z = engine.pos(id)
  local rx, rz = U.right(engine.yaw(id))
  if G.vehicle then engine.despawn(G.vehicle); G.vehicle = nil end
  if not G.player then player.spawn(x + rx * 1.5, y, z + rz * 1.5, 0) else engine.set_pos(G.player, x + rx * 1.5, y, z + rz * 1.5) end
  coroutine.yield()
  local down = #engine.find("ped_down")
  player.enter_nearest()
  check(G.vehicle and engine.tag(G.vehicle) == "bike", "enter beside a rider: you're on their bike")
  check(C.riders[id] == nil and not engine.exists(id), "the rider is off it")
  check(#engine.find("ped_down") > down, "and on the ground")

  -- Ride it: pedal for 4 s.
  local bike = G.vehicle
  local bx, _, bz = engine.pos(bike)
  local t = engine.time() + 4
  local real = input.drive
  input.drive = function() return 1, 0, false end
  wait(function() return engine.time() > t end, 6, "riding")
  input.drive = real
  local speed = vehicle.speed(bike)
  local ex, _, ez = engine.pos(bike)
  local _, uy = engine.up(bike)
  print(string.format("BIKE_PROBE: %.1f m/s after 4 s, %.0f m, up %.2f", speed, U.dist2d(bx, bz, ex, ez), uy))
  check(U.dist2d(bx, bz, ex, ez) > 8, "it goes")
  check(speed < 12.5, string.format("at a bike's speed (%.1f m/s)", speed))
  check(uy > 0.95, "upright")

  -- Off and on.
  player.exit()
  check(G.player and not G.vehicle, "off it")
  sleep(0.3)
  player.enter_nearest()
  check(G.vehicle == bike, "and on again")
  player.exit()

  -- One lying in the road: knock a rider off, pick their bike up.
  local id2 = next(C.riders)
  if id2 then
    local x2, y2, z2 = engine.pos(id2)
    engine.emit("killed", id2, G.player, 1, 0, 0)
    sleep(2.5)
    local fb = engine.find("fallen_bike")[1]
    check(fb ~= nil, "a knocked off rider's bike lies there")
    local fx, fy, fz = engine.pos(fb)
    engine.set_pos(G.player, fx + 1, fy + 0.5, fz)
    coroutine.yield()
    player.enter_nearest()
    check(G.vehicle and engine.tag(G.vehicle) == "bike" and not engine.exists(fb), "picked up and ridden")
  end
  print("BIKE_PROBE: PASSED")
  engine.quit()
end

local co = coroutine.create(script)
engine.on("tick", function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then engine.quit(); error(err, 0) end
end)
