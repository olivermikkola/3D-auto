-- Police helicopter probe: at four stars it flies in over you, sees you in
-- the open but not under a roof, and flies off under four stars.
-- HELI_TEST=1 auto game --headless 6000
local G = require "lib.state"
local U = require "lib.util"
local heli = require "systems.heli"
local police = require "systems.police"
local wanted = require "lib.wanted"
local city = require "lib.city"

local function check(ok, what)
  if not ok then engine.quit(); error("HELI TEST FAILED: " .. what, 0) end
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
  sleep(0.5)
  local map = city.map().id or "?"
  check(not heli.active(), "no helicopter at the start")
  wanted.set(3)
  sleep(0.5)
  check(not heli.active(), "none at three stars")
  -- Stand still in the open where the game starts; keep the cops off (they
  -- would bust you while you wait).
  local x, y, z = engine.pos(G.player)
  engine.on("tick", function()
    police.clear()
    if G.player then engine.set_pos(G.player, x, y, z); engine.set_vel(G.player, 0, 0, 0) end
  end)
  wanted.set(4)
  sleep(0.1)
  check(heli.active(), "four stars: it's coming")
  local hx, _, hz = engine.pos(heli.id())
  check(U.dist2d(hx, hz, x, z) > 200, string.format("from far off (%.0f m)", U.dist2d(hx, hz, x, z)))
  wait(function()
    local ax, ay, az = engine.pos(heli.id())
    return U.dist2d(ax, az, x, z) < 20 and ay - U.ground(ax, az) > 30
  end, 20, "it gets here and hangs 30+ m up")
  check(heli.sees(), "it sees you in the open")
  wanted.seen = false
  sleep(0.2)
  check(wanted.seen, "and so the cops keep their sighting")
  local roof = engine.spawn{mesh = "cube", pos = {x, y + 4, z}, size = {12, 0.5, 12}, body = "static", color = {0.5, 0.5, 0.5}}
  sleep(0.1)
  check(not heli.sees(), "under a roof it doesn't")
  engine.despawn(roof)
  wanted.set(2)
  wait(function() return not heli.active() end, 1, "under four stars it leaves")
  wait(function() return heli.id() == nil end, 30, "and is gone")
  print("HELI_PROBE " .. map .. ": PASSED")
  engine.quit()
end

local co = coroutine.create(script)
engine.on("tick", function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then engine.quit(); error(err, 0) end
end)
