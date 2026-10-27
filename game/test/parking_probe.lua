-- Kerbside parking probe: cars stand in the parking lanes of the streets
-- that have them, clear of the traffic lanes (city.lane keeps inside
-- them) and of crossings; you can get into one and drive it off; one hit
-- hard is shoved; none on low quality.
-- PARKING_TEST=1 auto game --headless 4000
local G = require "lib.state"
local U = require "lib.util"
local city = require "lib.city"
local roadnet = require "lib.roadnet"
local settings = require "lib.settings"
local player = require "lib.player"
local vehicle = require "lib.vehicle"
local P = require "systems.parking"

local function check(ok, what)
  if not ok then engine.quit(); error("PARKING TEST FAILED: " .. what, 0) end
  print("  ok  " .. what)
end
local function wait(pred, timeout, what)
  local t = engine.time() + timeout
  while not pred() do
    if engine.time() > t then check(false, what .. " (timed out)") end
    coroutine.yield()
  end
end
local function count() local n = 0 for _ in pairs(P.list) do n = n + 1 end return n end

local function script()
  local map = city.map().id or "?"
  wait(function() return P.pending == false end, 5, "the cars are parked")
  local n = count()
  print(string.format("PARKING_PROBE %s: %d parked", map, n))
  check(n > 150, "cars by the kerb")
  check(#engine.find("parked") == n, "each one there")

  -- Clear of the lanes: every car's middle at least a car's width and a
  -- little from the middle of the nearest lane on its side of its street.
  local net = roadnet.net()
  local in_lane, by_zebra = {}, {}
  for _, p in pairs(P.list) do
    local e = net.edges[p.edge]
    local best, bd = nil, math.huge
    for i = 2, #e.pts do
      local a, b = e.pts[i - 1], e.pts[i]
      local ux, uz = b[1] - a[1], b[2] - a[2]
      local t = math.max(0, math.min(1, ((p.x - a[1]) * ux + (p.z - a[2]) * uz) / math.max(ux * ux + uz * uz, 1e-6)))
      local dd = U.dist2d(p.x, p.z, a[1] + ux * t, a[2] + uz * t)
      if dd < bd then best, bd = i, dd end
    end
    local a, b = e.pts[best - 1], e.pts[best]
    local right = (p.x - a[1]) * (b[2] - a[2]) - (p.z - a[2]) * (b[1] - a[1]) > 0 -- (right of a to b: along U.right)
    local fx, fz = b[1] - a[1], b[2] - a[2]
    local l = math.sqrt(fx * fx + fz * fz)
    local off = math.abs((p.x - a[1]) * fz - (p.z - a[2]) * fx) / l -- from the middle
    local lane
    if e.oneway then
      local pl, pr = e.parking[1] and city.PARK_W or 0, e.parking[2] and city.PARK_W or 0
      local wide = e.width - pl - pr
      local n = math.max(1, math.floor(wide / 3.5))
      lane = right and city.lane(e.a, e.b) or (e.width / 2 - pl - wide / n / 2)
    else
      lane = right and city.lane(e.a, e.b) or city.lane(e.b, e.a)
    end
    if off - lane < 1.9 + 0.3 then
      in_lane[#in_lane + 1] = p
      print(string.format("  in lane? %.0f, %.0f on %s: %.1f m off its middle, lane %.1f, width %.1f, parking %s/%s, oneway %s, right %s, seg %d/%d", p.x, p.z, e.name or "?", off, lane, e.width, tostring(e.parking[1]), tostring(e.parking[2]), tostring(e.oneway), tostring(right), best, #e.pts))
    end
    local z = city.map().zebras or {}
    for k = 1, #z, 2 do
      if (z[k] - p.x) ^ 2 + (z[k + 1] - p.z) ^ 2 < 25 then by_zebra[#by_zebra + 1] = p break end
    end
  end
  local function where(l) return l[1] and string.format(" (at %.0f, %.0f)", l[1].x, l[1].z) or "" end
  check(#in_lane == 0, "none in a traffic lane" .. where(in_lane))
  check(#by_zebra == 0, "none on a crossing" .. where(by_zebra))

  -- Get into the nearest one and drive it off.
  local id, p = next(P.list)
  if G.vehicle then engine.despawn(G.vehicle); G.vehicle = nil end
  local rx, rz = U.right(p.yaw)
  local px, pz = p.x + rx * 2.3, p.z + rz * 2.3
  if not G.player then player.spawn(px, U.ground(px, pz) + 1.2, pz, p.yaw) else engine.set_pos(G.player, px, U.ground(px, pz) + 1.2, pz) end
  coroutine.yield()
  player.enter_nearest()
  check(G.vehicle and engine.tag(G.vehicle) == "car" and not engine.exists(id) and P.list[id] == nil, "getting in makes it a car you drive")
  check(engine.mesh_of(G.vehicle) == p.mesh, "the same car")
  local car = G.vehicle

  -- Shove one: a car into it at 12 m/s.
  local id2, q = next(P.list)
  local fx, fz = math.sin(q.yaw), math.cos(q.yaw)
  local sx, sz = q.x - fx * 9, q.z - fz * 9
  local ram = vehicle.spawn(sx, sz, q.yaw, 1)
  engine.set_vel(ram, fx * 12, 0, fz * 12)
  wait(function() return not engine.exists(id2) end, 3, "a car hit hard shoves a parked one")
  check(P.list[id2] == nil, "and it's a loose car now")
  engine.despawn(ram)

  settings.set("quality", 1)
  check(count() == 0 and #engine.find("parked") == 0, "none on low quality")
  settings.set("quality", 3)
  wait(function() return P.pending == false and count() > n end, 3, "more on high")
  print(string.format("PARKING_PROBE %s: %d on high", map, count()))
  settings.reset()
  print("PARKING_PROBE " .. map .. ": PASSED")
  engine.quit()
end

local co = coroutine.create(script)
engine.on("tick", function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then engine.quit(); error(err, 0) end
end)
