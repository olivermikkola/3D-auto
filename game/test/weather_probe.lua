-- Weather probe: a game starts clear and turns by the seed every three
-- hours; rain greys the sky, pulls the fog in, takes the shadows, falls on
-- the screen (not under cover), hisses, and wet roads brake longer.
-- WEATHER_TEST=1 auto game --headless 3000
local G = require "lib.state"
local U = require "lib.util"
local D = require "lib.daynight"
local W = require "lib.weather"
local vehicle = require "lib.vehicle"
local city = require "lib.city"

local function check(ok, what)
  if not ok then engine.quit(); error("WEATHER TEST FAILED: " .. what, 0) end
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

-- Metres a car takes to stop from 20 m/s, brakes full on, on a straight road.
local function stopping(x, z, yaw)
  local id = vehicle.spawn(x, z, yaw, 2)
  sleep(0.3)
  local fx, fz = U.forward(yaw)
  engine.set_vel(id, fx * 20, 0, fz * 20)
  local x0, _, z0 = engine.pos(id)
  local ticks = 0
  wait(function()
    vehicle.drive(id, 1 / 60, {throttle = -1})
    ticks = ticks + 1
    return vehicle.speed(id) < 0.5
  end, 10, "the car stops")
  local x1, _, z1 = engine.pos(id)
  engine.despawn(id)
  return U.dist2d(x0, z0, x1, z1)
end

local function script()
  sleep(0.5)
  local map = city.map().id or "?"
  check(W.kind == "clear" and W.cloud == 0 and W.rain == 0, "a game starts clear")
  local count = {}
  for n = 1, 1000 do local k = W.pick(n); count[k] = (count[k] or 0) + 1 end
  check(count.clear > 350 and count.clear < 500 and count.rain > 140 and count.storm > 40 and count.cloudy > 230,
        string.format("the odds hold: clear %d, cloudy %d, rain %d, storm %d of 1000", count.clear, count.cloudy, count.rain, count.storm))
  check(W.pick(7) == W.pick(7), "the same spell, the same weather")

  -- Three hours on, the next spell's weather (by the seed) comes in.
  local spells = W.spells
  D.set_hour((math.floor(D.hour / W.SLOT) + 1) * W.SLOT + 0.1)
  sleep(0.1)
  check(W.spells == spells + 1 and W.kind == W.pick(W.spells), "every three hours the weather turns: " .. W.kind)

  W.set("clear")
  sleep(0.2)
  local fog_a, fog_b = W.fog()
  local p = W.tint(D.palette(12))
  local sat = math.max(p.sky[1], p.sky[2], p.sky[3]) - math.min(p.sky[1], p.sky[2], p.sky[3])
  -- A straight, flat bit of road to brake on.
  local best
  for _, r in ipairs(city.roads()) do
    local pts = city.path(r[1], r[2])
    for i = 2, #pts do
      local ax, az, bx, bz = pts[i - 1][1], pts[i - 1][2], pts[i][1], pts[i][2]
      local l = U.dist2d(ax, az, bx, bz)
      local level = city.level(r[1])
      local at_grade = not level or math.abs(level - U.ground(city.pos(r[1]))) < 0.5
      local mx, mz = (ax + bx) / 2, (az + bz) / 2
      if l > 70 and at_grade and math.abs(U.ground(ax, az) - U.ground(bx, bz)) < 0.5
         and math.abs(U.ground(mx, mz) - U.ground(ax, az)) < 0.3 then
        best = {ax, az, math.atan(bx - ax, bz - az)}
        break
      end
    end
    if best then break end
  end
  check(best, "a straight flat road to brake on")
  local dry = stopping(best[1], best[2], best[3])

  W.set("storm")
  sleep(1)
  local wa, wb = W.fog()
  check(wb < fog_b * 0.6, string.format("rain pulls the fog in (%.0f -> %.0f m)", fog_b, wb))
  local q = W.tint(D.palette(12))
  local wsat = math.max(q.sky[1], q.sky[2], q.sky[3]) - math.min(q.sky[1], q.sky[2], q.sky[3])
  check(wsat < sat * 0.4 and q.sun[1] < p.sun[1] * 0.5, "clouds grey the sky and dim the sun")
  check(W.open > 0.9, "out in the open the rain falls past the camera")
  check(W.grip() < 0.75, "wet roads grip less")
  local wet = stopping(best[1], best[2], best[3])
  check(wet > dry * 1.2, string.format("and the car stops later: %.1f m dry, %.1f m wet", dry, wet))
  W.set("clear")
  sleep(0.2)
  check(W.grip() == 1, "dry again")
  print("WEATHER_PROBE " .. map .. ": PASSED")
  engine.quit()
end

local co = coroutine.create(script)
engine.on("tick", function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then engine.quit(); error(err, 0) end
end)
