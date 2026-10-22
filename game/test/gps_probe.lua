-- GPS probe: routes between random spots are real drives (one-way streets
-- the right way, the length what the line measures, never longer than the
-- obvious way round, the goal at the end), a search across the whole map
-- is quick, mission start markers get no route, and the player's own car,
-- driven by a robot along the GPS line as it's redrawn, gets to a goal
-- 1-2 km off (on a small map, what it has). GPS_TEST=1 auto game --headless 20000
local G = require "lib.state"
local U = require "lib.util"
local city = require "lib.city"
local gps = require "lib.gps"
local template = require "lib.template"
local vehicle = require "lib.vehicle"
local input = require "lib.input"
local robot = require "test.robot"
local traffic = require "systems.traffic"
local peds = require "systems.peds"

local PAIRS = 40

-- No cash vans or street racers turning up as other blips meanwhile.
for _, name in ipairs{"systems.cashvan", "systems.racer"} do
  local sys = require(name)
  sys.FIRST, sys.EVERY = 1e9, 1e9
end

local function check(ok, what)
  if not ok then engine.quit(); error("GPS TEST FAILED: " .. what, 0) end
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

local function linked(a, b)
  for _, n in ipairs(city.links(a)) do if n == b then return true end end
  return false
end

local function measure(pts)
  local l = 0
  for i = 2, #pts do l = l + U.dist2d(pts[i - 1][1], pts[i - 1][2], pts[i][1], pts[i][2]) end
  return l
end

-- Random spots on the map's roads, from its own generator.
local seed = 12345
local function rand()
  seed = (seed * 1103515245 + 12345) & 0x7fffffff
  return seed / 0x80000000
end
local function spot()
  local roads = city.roads()
  local r = roads[1 + math.floor(rand() * #roads)]
  local p = city.path(r[1], r[2])
  local k = 2 + math.floor(rand() * (#p - 1))
  local t = rand()
  return p[k - 1][1] + (p[k][1] - p[k - 1][1]) * t, p[k - 1][2] + (p[k][2] - p[k - 1][2]) * t
end

local function routes()
  local found, times, t0 = 0, {}, os.clock()
  for _ = 1, PAIRS do
    local fx, fz = spot()
    local gx, gz = spot()
    local s0 = os.clock()
    local r = gps.route_between(fx, fz, nil, gx, gz, nil)
    if os.getenv("GPS_TRACE") then print(string.format("GPS_TRACE %.0f,%.0f -> %.0f,%.0f %.1f ms", fx, fz, gx, gz, (os.clock() - s0) * 1000)) end
    times[#times + 1] = os.clock() - s0
    if r then
      found = found + 1
      for k = 2, #r.js do
        if not linked(r.js[k - 1], r.js[k]) then check(false, string.format("route %d -> %d against a one-way street", r.js[k - 1], r.js[k])) end
      end
      local l = measure(r.pts)
      if math.abs(l - r.length) > 1 then check(false, string.format("route says %.0f m, its line is %.0f m", r.length, l)) end
      if l + 1 < U.dist2d(fx, fz, gx, gz) - 30 then check(false, "a route shorter than the crow flies") end
      local e = r.pts[#r.pts]
      if U.dist2d(e[1], e[2], gx, gz) > 30 then check(false, string.format("the route ends %.0f m from the goal", U.dist2d(e[1], e[2], gx, gz))) end
      -- Never longer than leaving by the nearest junction and taking the
      -- fewest-meters way from there (template's own search) to the goal's.
      if #r.js >= 2 then
        local j0, j1 = r.js[1], r.js[#r.js]
        local mid = template.drive_from(j0)[j1]
        if not mid then check(false, string.format("junction %d can't reach %d by the template's search", j0, j1)) end
        local inner = 0
        for k = 2, #r.js do inner = inner + measure(city.path(r.js[k - 1], r.js[k])) end
        if inner > mid + 1 then check(false, string.format("junction %d -> %d: %.0f m, shortest is %.0f m", j0, j1, inner, mid)) end
      end
    end
  end
  check(found >= PAIRS * 0.8, string.format("%d of %d random pairs have a route", found, PAIRS))
  table.sort(times)
  local typical = times[#times // 2 + 1]
  print(string.format("GPS_PROBE: routes take %.1f ms typically, %.1f ms at worst (%d junctions; the worst may hold a garbage collector step)",
    typical * 1000, times[#times] * 1000, #city.junctions()))
  check(typical < 0.03, string.format("a route across the map is quick (%.1f ms)", typical * 1000))
end

-- Into a car of the player's own, still, on a road.
local function give_car(x, z, yaw)
  local car = vehicle.spawn(x, z, yaw, 1, nil, "car", U.ground(x, z))
  if G.player then engine.despawn(G.player) end
  G.player, G.vehicle = nil, car
  engine.emit("vehicle_enter", car)
  return car
end

-- The GPS line moved over to the right-hand side of the road, for the robot.
local function keep_right(pts)
  local out = {}
  for i = 2, #pts do
    local p, q = pts[i - 1], pts[i]
    if U.dist2d(p[1], p[2], q[1], q[2]) > 0.5 then
      local rx, rz = U.right(math.atan(q[1] - p[1], q[2] - p[2]))
      out[#out + 1] = {p[1] + rx * 2.5, p[2] + rz * 2.5}
      out[#out + 1] = {q[1] + rx * 2.5, q[2] + rz * 2.5}
    end
  end
  return out
end

local driver
input.drive = function()
  if not (G.vehicle and driver) then return 0, 0, false end
  local throttle, steer = driver.inputs(G.vehicle)
  return throttle, steer, false
end

local function drive(map)
  require("lib.borders").crossings = {}
  for id in pairs(traffic.cars) do engine.despawn(id) end
  traffic.cars, traffic.target = {}, nil
  for id in pairs(peds.peds) do engine.despawn(id) end
  peds.peds = {}
  -- A start and a goal 1-2 km apart by road.
  local fx, fz, gx, gz, r
  for k = 1, 400 do
    fx, fz = spot()
    gx, gz = spot()
    r = gps.route_between(fx, fz, nil, gx, gz, nil)
    local min = k <= 200 and 1000 or 300 -- (a small map has none that far)
    if r and r.length > min and r.length < 2000 and #r.pts >= 2 then break end
    r = nil
  end
  check(r ~= nil, "a goal 0.3-2 km away")
  local p, q = r.pts[1], r.pts[2]
  local car = give_car(p[1], p[2], math.atan(q[1] - p[1], q[2] - p[2]))
  local goal = engine.spawn{mesh = "marker", pos = {gx, 2.5 + U.ground(gx, gz), gz}, scale = 5, color = {1, 0.85, 0.1, 0.35}}
  G.markers[#G.markers + 1] = {id = goal, color = {1, 0.85, 0.1}}
  sleep(0.2)
  local first = gps.update()
  check(first and gps.target().id == goal, "the goal's blip is the GPS's")
  check(math.abs(first.length - r.length) < 25, string.format("its route is the one found (%.0f vs %.0f m)", first.length, r.length))
  local dots = gps.dots()
  check(dots and #dots / 2 > first.length / 8, string.format("drawn as %d dots", dots and #dots / 2 or 0))
  print(string.format("GPS_PROBE %s: driving %.0f m from %.0f, %.0f to %.0f, %.0f", map, first.length, fx, fz, gx, gz))
  driver = robot.driver(keep_right(first.pts), 14, 6)
  local t0, still, redraws, last = engine.time(), 0, 0, nil
  local limit = first.length / 5 + 60
  while true do
    coroutine.yield()
    local x, _, z = engine.pos(car)
    if U.dist2d(x, z, gx, gz) < 20 then break end
    if engine.time() - t0 > limit then
      check(false, string.format("got there in %.0f s (%.0f m left by the GPS)", limit, gps.left() or -1))
    end
    -- Follow the line as it's redrawn (it starts where the car is).
    local route = gps.update()
    if route ~= last and route then
      last, redraws = route, redraws + 1
      if redraws % 5 == 0 then
        local backing = driver.backing
        driver = robot.driver(keep_right(route.pts), 14, 6)
        driver.backing = backing
      end
    end
    still = math.abs(vehicle.speed(car)) < 1 and still + 1 / 60 or 0
    if still > 2 then driver.backing, still = 1.5, 0 end
    if driver.backing > 0 then driver.backing = driver.backing - 1 / 60 end
  end
  local took = engine.time() - t0
  check(true, string.format("the car got there by the GPS in %.0f s (%d redraws)", took, redraws))
  check(gps.left() and gps.left() < 40, string.format("and the GPS says it's there (%.0f m left)", gps.left() or -1))
  engine.despawn(goal)
  driver = nil
  sleep(0.1)
  gps.update()
  local t = gps.target()
  check(gps.left() == nil, "goal gone: no route" .. (t and (" (still heading for " .. tostring(engine.tag(t.id)) .. ")") or ""))
end

local function script()
  sleep(0.5)
  local map = city.map().id or city.map().name or "?"
  routes()
  -- Free roam: only the missions' start markers on the map, and no route.
  require("lib.mission").show_start_markers()
  gps.update()
  check(gps.target() == nil and gps.left() == nil, "mission start markers get no route")
  require("lib.mission").hide_start_markers() -- (or the robot drives into one and starts it)
  drive(map)
  print("GPS_PROBE " .. map .. ": PASSED")
  engine.quit()
end

local co = coroutine.create(script)
engine.on("tick", function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then engine.quit(); error(err, 0) end
end)
