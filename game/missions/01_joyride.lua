-- The tutorial: steal a car and bring it to a garage across town.
local city = require "lib.city"

local lx, lz = city.block_center(4, 3)

return {
  title = "Joyride",
  start = {lx - 13, lz - 9},
  reward = 250,
  run = function(m)
    m:say("Steal a car. Walk up to one and press E.")
    m:wait(function() return m:in_car() end)

    local gx, gz = city.node(1, 7)
    local garage = m:marker(gx, gz)
    m:say("Drive it to the garage before the owner notices.")
    m:timer(75)
    m:wait(function() return m:near(garage, 5) end)

    m:say("Park it. Stop the car.")
    m:wait(function()
      return m:in_car() and math.abs(require("lib.vehicle").speed(require("lib.state").vehicle)) < 1
    end)
  end,
}
