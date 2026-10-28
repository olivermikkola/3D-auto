-- Street racer probe: a racer waits near you, pull up beside it and the
-- countdown starts, it drives its way to the finish junction by junction;
-- get there first and you're paid, let it win and you're not.
-- RACER_TEST=1 auto game --headless 6000
local G = require "lib.state"
local U = require "lib.util"
local city = require "lib.city"
local prefabs = require "lib.prefabs"
local racer = require "systems.racer"
local traffic = require "systems.traffic"
local vehicle = require "lib.vehicle"

local function check(ok, what)
  if not ok then engine.quit(); error("RACER TEST FAILED: " .. what, 0) end
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

local function put(id, x, z)
  engine.set_pos(id, x, 0.8 + U.ground(x, z), z)
  engine.set_vel(id, 0, 0, 0)
  engine.set_angvel(id, 0, 0, 0)
end

-- Pull up 4 m beside the racer and stop.
local function pull_up(mine)
  local rc = racer.car()
  local x, _, z = engine.pos(rc)
  local rx, rz = U.right(engine.yaw(rc))
  put(mine, x - rx * 4, z - rz * 4)
  engine.set_yaw(mine, engine.yaw(rc))
end

local function script()
  sleep(0.5)
  local map = city.map().id or "?"
  if not city.network() then
    sleep(2)
    check(racer.state() == nil, "no racers on a map without points of interest")
    print("RACER_PROBE " .. map .. ": PASSED")
    engine.quit()
    return
  end
  racer.forced = true
  -- Into a car of your own.
  local px, _, pz = engine.pos(G.player)
  local mine = vehicle.spawn(px + 3, pz, 0, 2)
  sleep(0.3)
  engine.set_pos(G.player, px + 3, 1.2 + U.ground(px + 3, pz - 3.5), pz - 3.5)
  engine.emit("key", "e", true)
  wait(function() return G.vehicle == mine end, 1, "in a car")

  racer.soon()
  wait(function() return racer.state() == "waiting" end, 2, "a racer waits")
  local rc = racer.car()
  local x, _, z = engine.pos(rc)
  local mx, _, mz = engine.pos(mine)
  check(prefabs.car_kind(engine.mesh_of(rc)) == "sports", "in a sports car")
  check(U.dist2d(x, z, mx, mz) > 70 and U.dist2d(x, z, mx, mz) < 210, string.format("%.0f m from you", U.dist2d(x, z, mx, mz)))
  sleep(1)
  check(racer.state() == "waiting", "it waits for you")

  pull_up(mine)
  wait(function() return racer.state() == "countdown" end, 1, "pulling up beside it starts the countdown")
  wait(function() return racer.state() == "racing" end, 4, "three, two, one, go")
  local way = racer.way
  local seen, last = {}, 1
  local fx, fz = city.pos(racer.finish().junction)
  check(way[#way] == racer.finish().junction, "the way ends at the finish")
  local d0 = U.dist2d(x, z, fx, fz)
  local t = engine.time() + 12
  wait(function()
    local c = traffic.cars[rc]
    if c then
      for k = last, #way do
        if way[k] == c.from then
          if seen[#seen] ~= k then seen[#seen + 1] = k end
          last = k
          break
        end
      end
    end
    put(mine, mx, mz) -- you wait at the start
    return engine.time() > t
  end, 14, "racing")
  local nx, _, nz = engine.pos(rc)
  check(#seen >= 2, string.format("it drives its way, junction by junction (%d passed, in order)", #seen))
  check(U.dist2d(nx, nz, fx, fz) < d0 - 60, string.format("toward the finish (%.0f -> %.0f m)", d0, U.dist2d(nx, nz, fx, fz)))
  local cash = G.cash
  put(mine, fx, fz)
  wait(function() return racer.state() == nil end, 1, "at the finish first")
  check(G.cash == cash + racer.PRIZE, "you win the prize")

  -- Another, and this time it wins.
  racer.soon()
  wait(function() return racer.state() == "waiting" end, 2, "another racer waits")
  -- Held beside it: this one may wait on a slope a parked car rolls down.
  wait(function()
    if racer.state() == "waiting" then pull_up(mine) end
    return racer.state() == "racing"
  end, 5, "and races")
  fx, fz = city.pos(racer.finish().junction)
  put(racer.car(), fx, fz)
  cash = G.cash
  wait(function() return racer.state() == nil end, 1, "it gets there first")
  check(G.cash == cash, "no prize")
  print("RACER_PROBE " .. map .. ": PASSED")
  engine.quit()
end

local co = coroutine.create(script)
engine.on("tick", function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then engine.quit(); error(err, 0) end
end)
