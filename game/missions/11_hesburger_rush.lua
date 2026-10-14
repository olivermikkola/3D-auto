-- Fast-paced courier run across Turku: pick up food orders at Kauppatori,
-- cross the Aurajoki bridges at high speed, and deliver to Teatterisilta,
-- Samppalinna, and Tuomiokirkontori before the food gets cold.
local city = require "lib.city"
local U = require "lib.util"
local vehicle = require "lib.vehicle"

local start_pos = {0, 0} -- Turun Kauppatori market square
local drops = {
  {name = "Kaupunginteatteri (Teatterisilta)", pos = {-60, 40}},
  {name = "Samppalinnanpuisto Pavilion", pos = {-240, -110}},
  {name = "Tuomiokirkontori Steps", pos = {320, -180}},
}

return {
  title = "Hesburger Express",
  after = "01_joyride",
  start = start_pos,
  reward = 2200,
  run = function(m)
    m:timer(180)
    m:say("Pick up the express order at Kauppatori and deliver across the river before it gets cold!")

    U.message("HESBURGER EXPRESS ACTIVE: 3 DELIVERIES REMAINING", 3)
    engine.play("star")

    for i, drop in ipairs(drops) do
      local dp = drop.pos
      local marker = m:marker(dp[1], dp[2], {0.95, 0.3, 0.1})
      m:say(string.format("Rush delivery (%d/%d): %s!", i, #drops, drop.name))

      m:wait(function()
        return m:near(marker, 10)
      end)

      m:remove(marker)
      engine.play("pickup")
      U.message(string.format("DELIVERY COMPLETE: %s!", string.upper(drop.name)), 2)
    end

    U.message("ALL DELIVERIES COMPLETE: FAST FOOD DELIVERED HOT!", 4)
  end,
}
