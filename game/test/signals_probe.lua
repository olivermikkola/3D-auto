-- Traffic lights probe: a car heading into a junction with lights stops at
-- the line on red (and isn't taken for stuck and moved off), the posts
-- there show red, and it drives on when they turn green.
-- SIGNALS_TEST=1 auto game --headless 4000
local G = require "lib.state"
local U = require "lib.util"
local city = require "lib.city"
local roadnet = require "lib.roadnet"
local signals = require "systems.signals"
local traffic = require "systems.traffic"
local vehicle = require "lib.vehicle"

local function check(ok, what)
  if not ok then engine.quit(); error("SIGNALS TEST FAILED: " .. what, 0) end
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

-- A junction with lights and a straight way into it at least 60 m long,
-- with somewhere to go on from it, nearest the map's lot.
local function approach()
  local lx, lz = city.place("lot")
  local best
  for j, _ in pairs(roadnet.signals().junctions) do
    for _, n in ipairs(city.links_in(j) or {}) do
      local p = city.path(n, j)
      local a, b = p[#p - 1], p[#p]
      local len = U.dist2d(a[1], a[2], b[1], b[2])
      local on = false
      for _, m in ipairs(city.links(j) or {}) do if m ~= n then on = m end end
      local jx, jz = city.pos(j)
      local d = U.dist2d(jx, jz, lx, lz)
      if len >= 60 and on and roadnet.signals().junctions[j].stop < 20 and (not best or d < best.d) then
        best = {j = j, n = n, on = on, a = a, b = b, d = d}
      end
    end
  end
  return best
end

local function script()
  sleep(0.5)
  local map = city.map().id or "?"
  require("lib.mission").hide_start_markers()
  local w = approach()
  check(w, "a junction with lights and a long straight way in")
  local heading = math.atan(w.b[1] - w.a[1], w.b[2] - w.a[2])
  local fx, fz = U.forward(heading)
  local rx, rz = U.right(heading)
  print(string.format("  junction %d at %.0f, %.0f, stop line %.1f m out", w.j, w.b[1], w.b[2], signals.stop_line(w.j)))
  -- Out of the way: on foot, off to the side of the junction.
  if G.vehicle then engine.despawn(G.vehicle); G.vehicle = nil end
  local px, pz = w.b[1] - rx * 40 - fx * 30, w.b[2] - rz * 40 - fz * 30
  engine.set_pos(G.player, px, U.ground(px, pz) + 1.2, pz)
  for id in pairs(traffic.cars) do engine.despawn(id); traffic.cars[id] = nil end
  traffic.target = 0

  signals.force(w.j, heading, "red")
  local lane = city.lane(w.n, w.j)
  local sx, sz = w.b[1] - fx * 45 + rx * lane, w.b[2] - fz * 45 + rz * lane
  local id = vehicle.spawn(sx, sz, heading, 2, nil, "car", city.height_on(w.n, w.j, sx, sz))
  local c = traffic.adopt(id)
  traffic.set_plan(id, {w.n, w.j}) -- (a plan left to run makes it a racer: they run reds)
  c.wp = #c.path
  local function to_junction() local x, _, z = engine.pos(id) return U.dist2d(x, z, w.b[1], w.b[2]) end

  sleep(12)
  check(engine.exists(id) and traffic.cars[id] == c, "the car is still the one put there (not moved off as stuck)")
  local stop = signals.stop_line(w.j)
  check(math.abs(vehicle.speed(id)) < 0.5, string.format("it waits on red (%.1f m/s)", vehicle.speed(id)))
  check(to_junction() > stop - 2 and to_junction() < stop + 6,
        string.format("at the line: %.1f m from the junction, the line %.1f", to_junction(), stop))
  local red = 0
  for _, p in ipairs(roadnet.signals().posts) do
    if p.junction == w.j and math.abs(math.cos(p.yaw - heading)) > 0.7 and engine.exists(p.id) then
      red = red + (engine.mesh_of(p.id) == "signal_red" and 1 or 0)
    end
  end
  check(red > 0, red .. " posts on its road show red")

  signals.force(w.j, heading, "green")
  wait(function() return c.from == w.j or to_junction() < 3 end, 12, "on green it drives into the junction")
  print("SIGNALS_PROBE " .. map .. ": PASSED")
  engine.quit()
end

local co = coroutine.create(script)
engine.on("tick", function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then engine.quit(); error(err, 0) end
end)
