-- Deliver a car full of something breakable. Every knock costs condition.
local G = require "lib.state"
local H = require "lib.health"
local city = require "lib.city"
local vehicle = require "lib.vehicle"

if not city.has("cargo_pickup", "cargo_drop") then return false end

local cx, cz = city.place("cargo_pickup")
local MIN = 60 -- condition below this and the cargo is ruined

return {
  title = "Fragile Cargo",
  after = "04_getaway",
  start = {cx - 8, cz - 8},
  reward = 900,
  run = function(m)
    -- Clear the spot (a dented car from your last try, a parked one).
    for _, id in ipairs(engine.find("car")) do
      local x, _, z = engine.pos(id)
      if id ~= G.vehicle and (x - cx) ^ 2 + (z - cz) ^ 2 < 36 then engine.despawn(id) end
    end
    -- Not m:spawn: the car stays in town (with you in it) when the mission ends.
    m.car = vehicle.spawn(cx, cz, 0, 5)
    local van = m:marker(cx, cz, {0.3, 1, 0.4})
    m:say("Get in the white car. Gently.")
    m:wait(function()
      if not engine.exists(m.car) then m:fail("THE CARGO IS GONE") end
      return G.vehicle == m.car
    end)
    m:remove(van)

    local dx, dz = city.place("cargo_drop")
    local drop = m:marker(dx, dz)
    m:timer(110)
    m:wait(function()
      if G.vehicle ~= m.car then m:fail("YOU LEFT THE CARGO") end
      local hp = H.get(m.car) or 0
      if hp < MIN then m:fail("THE CARGO IS RUINED") end
      m:say(string.format("Deliver it and stop. Cargo: %d%%", math.floor((hp - MIN) / (H.VEHICLE_HP - MIN) * 100 + 0.5)))
      return m:near(drop, 6) and math.abs(vehicle.speed(m.car)) < 1
    end)
  end,
}
