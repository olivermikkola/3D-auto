-- Focused integration test using the real world, input bus, health and audio.
-- GARAGE_TEST=1 auto game --headless 600
local G = require "lib.state"
local H = require "lib.health"
local C = require "systems.carnage"
local vehicle = require "lib.vehicle"
local garage, car, repaired = nil, nil, 0
local function check(ok, what)
  if not ok then engine.quit(); error("GARAGE FAILED: " .. what, 0) end
  print("  ok  " .. what)
end

local started, done
local function setup()
  started = engine.ticks()
  local ok, result = pcall(require, "systems.garage")
  check(ok, "repair garage is available")
  garage = result
  check(#engine.find("garage") >= 4, "garage has visible bay and canopy")
  engine.despawn(G.player)
  G.player = nil
  car = vehicle.spawn(garage.x, garage.z)
  G.vehicle = car
  engine.orient(car, 0)
  H.set(car, H.VEHICLE_HP)
  H.damage(car, 80)
  G.cash = 250
end
engine.on("vehicle_repaired", function(id, price)
  check(id == car and price == 100, "repair event identifies car and price")
  repaired = repaired + 1
end)
engine.on("tick", function()
  if done then return end
  if not started then return setup() end
  if engine.ticks() - started < 30 then return end
  done = true
  engine.emit("key", "r", true)
  check(H.get(car) == H.VEHICLE_HP, "R restores vehicle health")
  check(G.cash == 150, "repair costs exactly $100")
  check(repaired == 1, "one repair event")
  check(engine.stats().voices > 0, "repair sound is playing")
  engine.emit("key", "r", true)
  check(G.cash == 150 and repaired == 1, "healthy car is not charged again")
  H.set(car, H.VEHICLE_HP)
  H.damage(car, 80)
  engine.set_pos(car, garage.x + 20, 0.95, garage.z)
  engine.emit("key", "r", true)
  check(H.get(car) == 20 and G.cash == 150, "cannot repair outside the bay")
  engine.set_pos(car, garage.x, 0.95, garage.z)
  engine.set_vel(car, 0, 0, 0)
  engine.set_angvel(car, 0, 0, 0)
  engine.emit("key", "r", false)
  check(H.get(car) == 20, "key release does not purchase a repair")
  local wanted = require "lib.wanted"
  wanted.set(1)
  engine.emit("key", "r", true)
  check(H.get(car) == 20 and G.cash == 150, "wanted drivers are refused")
  wanted.clear()
  G.cash = 99
  engine.emit("key", "r", true)
  check(H.get(car) == 20 and G.cash == 99, "insufficient funds never charges or heals")
  G.cash = 100
  engine.set_vel(car, 0, 0, 5)
  engine.emit("key", "r", true)
  check(H.get(car) == 20 and G.cash == 100, "moving cars must stop first")
  engine.set_vel(car, 0, 0, 0)
  H.damage(car, 25)
  check(C.burning[car] ~= nil, "car is burning before rescue")
  engine.emit("key", "r", true)
  check(H.get(car) == H.VEHICLE_HP and G.cash == 0, "exact funds repair a burning car")
  check(C.burning[car] == nil, "repair cancels pending explosion")
  check(repaired == 2, "refused attempts emit no repair event")
  G.player, G.vehicle = car, nil
  engine.emit("key", "r", true)
  check(G.cash == 0 and repaired == 2, "on-foot input does not buy repairs")
  G.player, G.vehicle = nil, car
  G.dead = engine.time()
  engine.emit("key", "r", true)
  check(G.cash == 0 and repaired == 2, "dead players cannot repair")
  G.dead = nil
  -- Contact batches can outlive an entity removed by an earlier handler.
  local stale = vehicle.spawn(garage.x + 15, garage.z)
  engine.despawn(stale)
  engine.emit("contact", stale, car, 12)
  print("GARAGE PASSED")
  engine.quit()
end)
