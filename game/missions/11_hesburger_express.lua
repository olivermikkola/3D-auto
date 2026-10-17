-- Mission 11: Häsburger Express
-- Fast courier rush: pick up hot meals from Turku Kauppatori Häsburger
-- and deliver them across the river to Kupittaa and Auransilta before they get cold!
local city = require "lib.city"
local U = require "lib.util"
local vehicle = require "lib.vehicle"

local is_turku = city.map().id == "turku" or city.map().name == "Turku"
local start_pos = is_turku and {-120, 40} or {850, -1700}

local drops = is_turku and {
  {name = "Auransilta Jokiranta", pos = {-25, 300}},
  {name = "Kupittaankenttä", pos = {880, 540}}, -- the field there (OSM)
  {name = "Tuomiokirkontori", pos = {300, -80}},
} or {
  {name = "Raisiontori Kioski", pos = {890, -1720}},
  {name = "Kuloisten koulu", pos = {1850, -1750}},
  {name = "Mylly Ravintolamaailma", pos = {2700, -2200}},
}

return {
  title = "Häsburger Express",
  after = "02_checkpoints",
  start = start_pos,
  reward = 1200,
  run = function(m)
    m:timer(150)
    m:say("Rush courier orders from Häsburger to hungry customers across town!")
    engine.play("star")

    for i, drop in ipairs(drops) do
      local dp = drop.pos
      local marker = m:marker(dp[1], dp[2], {0.95, 0.2, 0.1}) -- Häsburger red marker
      m:say(string.format("Order (%d/%d): Deliver to %s!", i, #drops, drop.name))

      m:wait(function()
        return m:near(marker, 10)
      end)

      m:remove(marker)
      engine.play("pickup")
      U.message(string.format("ORDER DELIVERED: %s (+400$)", drop.name), 2)
    end

    U.message("ALL HÄSBURGER ORDERS DELIVERED ON TIME!", 4)
  end,
}
