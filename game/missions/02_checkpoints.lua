-- Street race through checkpoints. One at a time, against the clock.
local city = require "lib.city"
local U = require "lib.util"

local route = {{2, 2}, {2, 6}, {6, 6}, {6, 2}, {4, 2}, {4, 4}}

return {
  title = "Street Race",
  start = {city.node(5, 3)},
  reward = 600,
  run = function(m)
    m:say("You need wheels for this one.")
    m:wait(function() return m:in_car() end)
    m:timer(90)
    for i, n in ipairs(route) do
      local x, z = city.node(n[1], n[2])
      local cp = m:marker(x, z, {0.2, 0.8, 1.0})
      m:say(string.format("Checkpoint %d of %d", i, #route))
      m:wait(function()
        if not m:in_car() then m:fail("YOU LEFT YOUR CAR") end
        return m:near(cp, 6)
      end)
      m:remove(cp)
      engine.emit("checkpoint", i)
      U.message(string.format("%d/%d", i, #route), 1)
    end
  end,
}
