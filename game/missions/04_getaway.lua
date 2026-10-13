-- Rob the bank, then shake a three-star pursuit.
local city = require "lib.city"

if not city.has("bank", "getaway_start") then return false end

local bx, bz = city.place("bank")

return {
  title = "Getaway",
  start = {city.place("getaway_start")},
  reward = 1200,
  run = function(m)
    m:say("Get a fast car and drive to the bank" .. m:on_street(bx, bz) .. ".")
    m:wait(function() return m:in_car() end)
    local bank = m:marker(bx, bz, {0.3, 1, 0.4})
    m:wait(function() return m:near(bank, 5) end)

    m:say("Stay in the marker while the crew loads the cash...")
    local t = 0
    m:wait(function()
      t = m:near(bank, 6) and t + 1 / 60 or 0
      return t > 3
    end)
    m:remove(bank)

    m:wanted(3)
    m:say("Lose the cops! Get out of the red circle unseen.")
    m:wait(function() return m:stars() == 0 end)
  end,
}
