-- Convoy probe: at four stars three squad cars come at once, in a column
-- down one road, 100-220 m off and heading your way, on top of the level's
-- usual units; they drive at you. At five stars a Pasi leads the convoy.
-- CONVOY_TEST=1 auto game --headless 6000
local G = require "lib.state"
local U = require "lib.util"
local city = require "lib.city"
local police = require "systems.police"
local vehicle = require "lib.vehicle"
local wanted = require "lib.wanted"

local function check(ok, what)
  if not ok then engine.quit(); error("CONVOY TEST FAILED: " .. what, 0) end
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

local function convoy()
  local out = {}
  for id, c in pairs(police.cops) do if c.convoy then out[#out + 1] = id end end
  return out
end

local function script()
  sleep(0.5)
  local map = city.map().id or "?"
  require("lib.mission").hide_start_markers()
  -- In a car, standing still on a road.
  local r = city.roads()[1]
  local p = city.path(r[1], r[2])
  local ax, az, bx, bz = p[1][1], p[1][2], p[2][1], p[2][2]
  local x, z = (ax + bx) / 2, (az + bz) / 2
  local car = vehicle.spawn(x, z, math.atan(bx - ax, bz - az), 3, nil, nil, city.height_on(r[1], r[2], x, z))
  if G.player then engine.despawn(G.player) end
  G.player, G.vehicle = nil, car
  for id in pairs(require("systems.traffic").cars) do engine.despawn(id) end

  wanted.set(4)
  wait(function() return #convoy() > 0 end, 5, "a convoy comes at four stars")
  local c = convoy()
  check(#c == 3, #c .. " units in it")
  local px, _, pz = engine.pos(car)
  local yaw0 = engine.yaw(c[1])
  local near, far = math.huge, 0
  for _, id in ipairs(c) do
    local cx, _, cz = engine.pos(id)
    local d = U.dist2d(cx, cz, px, pz)
    near, far = math.min(near, d), math.max(far, d)
    check(math.cos(engine.yaw(id) - yaw0) > 0.95, "facing the same way")
    check(not police.cops[id].is_pasi, "a squad car (no Pasi at four)")
    for _, other in ipairs(c) do
      local ox, _, oz = engine.pos(other)
      check(U.dist2d(cx, cz, ox, oz) < 26, "in a column")
    end
  end
  check(near >= 95 and far <= 245, string.format("%.0f-%.0f m off", near, far))
  local fx, fz = U.forward(yaw0)
  local lx, _, lz = engine.pos(c[1])
  check(((px - lx) * fx + (pz - lz) * fz) / U.dist2d(lx, lz, px, pz) > 0.3, "heading your way")
  check(police.count() <= 5 + 3, police.count() .. " units on the street (5 + the convoy at most)")
  sleep(4)
  local closer = 0
  for _, id in ipairs(c) do
    if engine.exists(id) then
      local cx, _, cz = engine.pos(id)
      if U.dist2d(cx, cz, px, pz) < near + 10 then closer = closer + 1 end
    end
  end
  print(string.format("CONVOY_PROBE %s: convoy %.0f-%.0f m off, %d of 3 closer after 4 s", map, near, far, closer))
  check(closer >= 2, "they drive at you")

  -- Five stars: a Pasi leads it.
  police.clear()
  wanted.set(5)
  local ids
  wait(function() ids = police.convoy(); return ids ~= nil end, 3, "a convoy at five stars")
  check(police.cops[ids[1]].is_pasi and engine.tag(ids[1]) == "cop", "a Pasi leads it, as a police unit")
  check(not police.cops[ids[2]].is_pasi and not police.cops[ids[3]].is_pasi, "squad cars behind")
  print("CONVOY_PROBE " .. map .. ": PASSED")
  engine.quit()
end

local co = coroutine.create(script)
engine.on("tick", function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then engine.quit(); error(err, 0) end
end)
