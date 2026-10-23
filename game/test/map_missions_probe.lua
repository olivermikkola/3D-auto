-- Map missions probe: the map's own missions (Pansio Base Heist, Pöli
-- Transit, The Archipelago Run) play through: their vehicle spawns, you get
-- in it, it's taken to each marker, the mission passes and pays, and you're
-- still in the vehicle afterwards. MAP_MISSIONS_TEST=1 auto game --headless 20000
local G = require "lib.state"
local U = require "lib.util"
local city = require "lib.city"
local mission = require "lib.mission"
local player = require "lib.player"
local vehicle = require "lib.vehicle"
local wanted = require "lib.wanted"

local IDS = {"08_pansio_heist", "09_foli_transit", "10_archipelago_run"}

local function check(ok, what)
  if not ok then engine.quit(); error("MAP MISSIONS TEST FAILED: " .. what, 0) end
  print("  ok  " .. what)
end
local function wait(pred, timeout, what)
  local t = engine.time() + timeout
  while not pred() do
    if engine.time() > t then check(false, what .. " (timed out)") end
    coroutine.yield()
  end
end

local passed, failed
engine.on("mission_passed", function(def) passed = def end)
engine.on("mission_failed", function(def, reason) failed = reason or "?" end)

local function script()
  coroutine.yield()
  local map = city.map().id or "?"
  for id in pairs(require("systems.traffic").cars) do engine.despawn(id) end
  local played = 0
  for _, id in ipairs(IDS) do
    local def
    for _, d in ipairs(mission.defs) do if d.id == id then def = d end end
    if def then
      passed, failed = nil, nil
      local cash = G.cash
      mission.start(def)
      check(G.mission and G.mission.def == def, def.title .. ": starts")
      -- Its vehicle: the one it owns.
      local car
      wait(function()
        for _, e in ipairs(G.mission and G.mission.owned or {}) do
          if engine.exists(e) and vehicle.tags[engine.tag(e)] then car = e end
        end
        return car ~= nil or failed
      end, 3, def.title .. ": its vehicle spawns")
      check(not failed, def.title .. ": no script error (" .. tostring(failed) .. ")")
      local x, y, z = engine.pos(car)
      local rx, rz = U.right(engine.yaw(car))
      engine.set_pos(G.player, x + rx * 2.5, y + 0.5, z + rz * 2.5)
      coroutine.yield()
      player.enter_nearest()
      check(G.vehicle == car, def.title .. ": in its vehicle")
      local stops, last = 0, nil
      wait(function()
        local mk = G.markers[#G.markers]
        if mk and engine.exists(mk.id) and mk.id ~= last then
          last, stops = mk.id, stops + 1
          local mx, _, mz = engine.pos(mk.id)
          local _, vy = engine.pos(car)
          local boat = engine.tag(car) == "boat"
          engine.set_pos(car, mx, boat and vy or U.ground(mx, mz) + 1.5, mz)
        end
        engine.set_vel(car, 0, 0, 0)
        return passed or failed
      end, 60, def.title .. ": plays through")
      check(passed == def, string.format("%s: passed after %d markers (%s)", def.title, stops, tostring(failed)))
      check(G.cash == cash + def.reward, def.title .. ": pays $" .. def.reward)
      check(G.vehicle == car and engine.exists(car), def.title .. ": you're still in the vehicle")
      player.exit()
      wanted.clear()
      played = played + 1
    end
  end
  print(string.format("MAP_MISSIONS_PROBE %s: %d played", map, played))
  print("MAP_MISSIONS_PROBE " .. map .. ": PASSED")
  engine.quit()
end

local co = coroutine.create(script)
engine.on("tick", function()
  if coroutine.status(co) == "dead" then return end
  local ok, err = coroutine.resume(co)
  if not ok then engine.quit(); error(err, 0) end
end)
