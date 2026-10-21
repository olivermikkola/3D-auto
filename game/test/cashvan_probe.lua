-- Cash van probe: a van leaves a bank near you, drives off with traffic,
-- runs when hit, spills its bags when wrecked (two stars), the bags pay
-- when picked up, and a van left far behind is gone.
-- CASHVAN_TEST=1 auto game --headless 3000
local G = require "lib.state"
local U = require "lib.util"
local H = require "lib.health"
local cashvan = require "systems.cashvan"
local traffic = require "systems.traffic"
local wanted = require "lib.wanted"

local function check(ok, what)
  if not ok then engine.quit(); error("CASHVAN TEST FAILED: " .. what, 0) end
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

local function stand(x, z)
  engine.set_pos(G.player, x, 1.2 + U.ground(x, z), z)
  engine.set_vel(G.player, 0, 0, 0)
end

local function script()
  sleep(0.5)
  local map = require("lib.city").map().id or "?"
  check(cashvan.van() == nil, "no van at the start")
  cashvan.soon()
  wait(function() return cashvan.van() end, 2, "a van sets off")
  local van = cashvan.van()
  local px, _, pz = U.player_pos()
  local x0, _, z0 = engine.pos(van)
  check(U.dist2d(x0, z0, px, pz) < 650, string.format("near you (%.0f m)", U.dist2d(x0, z0, px, pz)))
  local shown = false
  for _, m in ipairs(G.markers) do if m.id == van then shown = true end end
  check(shown, "it's on the map")
  check(traffic.cars[van] and traffic.cars[van].keep, "it drives with traffic and isn't recycled")
  sleep(4)
  local x1, _, z1 = engine.pos(van)
  check(U.dist2d(x0, z0, x1, z1) > 3, string.format("it drives off (%.1f m)", U.dist2d(x0, z0, x1, z1)))

  H.damage(van, 10, G.player)
  check(traffic.cars[van].cruise > 15 and wanted.stars() >= 1, "hit, it runs, and that's a crime")
  local cash0 = G.cash
  H.damage(van, 1000, G.player)
  check(cashvan.van() == nil, "wrecked, its round is over")
  check(#cashvan.bags() == 4, "four bags spill out")
  check(wanted.stars() >= 2, "two stars for the robbery")
  sleep(2.5)
  for _, b in ipairs({table.unpack(cashvan.bags())}) do
    local x, _, z = engine.pos(b.id)
    stand(x, z)
    sleep(0.2)
  end
  check(#cashvan.bags() == 0 and G.cash == cash0 + 1000, "the bags pay $1000 (cash " .. (G.cash - cash0) .. ")")

  -- The next one, left far behind, is gone.
  wanted.clear()
  cashvan.soon()
  wait(function() return cashvan.van() end, 2, "another van sets off")
  van = cashvan.van()
  local vx, _, vz = engine.pos(van)
  stand(vx + 700, vz)
  wait(function() return not engine.exists(van) and cashvan.van() == nil end, 2, "a van left 700 m behind is gone")
  print("CASHVAN_PROBE " .. map .. ": PASSED")
  engine.quit()
end

local co = coroutine.create(script)
engine.on("tick", function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then engine.quit(); error(err, 0) end
end)
