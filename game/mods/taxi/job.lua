-- The mission: three fares across town in the yellow cab.
local G = require "lib.state"
local U = require "lib.util"
local city = require "lib.city"
local vehicle = require "lib.vehicle"
local cab = require "cab"

local lx, lz = city.block_center(2, 15)

-- A random street corner between `min` and 260 meters from (x, z).
local function corner_far_from(x, z, min)
  local k, l = city.random_node(x, z, min, 260)
  if k then return city.node(k, l) end
  return city.node(city.nearest_node(x, z))
end

return {
  title = "Taxi Driver",
  start = {lx + 18, lz - 14},
  reward = 150,
  run = function(m)
    m:say("Get in the yellow cab.")
    m:wait(function() return G.vehicle == cab.id end)
    for fare = 1, 3 do
      local x, _, z = engine.pos(cab.id)
      local px, pz = corner_far_from(x, z, 80)
      local pickup = m:marker(px, pz, {1, 0.8, 0.1})
      local rider = m:spawn{mesh = "ped" .. math.random(12), pos = {px + 3, 1.15, pz + 3}, size = {0.7, 1.8, 0.7}, tag = "rider"}
      m:say(string.format("Fare %d/3: pick up the passenger.", fare))
      m:clear_timer()
      m:wait(function()
        if G.vehicle ~= cab.id then m:fail("YOU LEFT THE CAB") end
        return m:near(pickup, 6) and math.abs(vehicle.speed(cab.id)) < 2
      end)
      m:remove(pickup)
      m:remove(rider)
      local dx, dz = corner_far_from(px, pz, 120)
      local drop = m:marker(dx, dz, {0.2, 1, 0.4})
      m:say("Take them to the green marker. Tips for speed!")
      local t0 = engine.time()
      m:timer(70)
      m:wait(function() return m:near(drop, 6) and math.abs(vehicle.speed(cab.id)) < 2 end)
      m:remove(drop)
      local tip = math.max(0, math.floor(60 - (engine.time() - t0)))
      G.cash = G.cash + 40 + tip
      engine.play("fare")
      U.message(string.format("FARE +$%d", 40 + tip), 2)
    end
  end,
}
