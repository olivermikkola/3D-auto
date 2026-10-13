-- Collect packages across town. Every one turns up the heat; lose the cops
-- before you make the drop.
local city = require "lib.city"
local U = require "lib.util"
local wanted = require "lib.wanted"

if not city.has("smuggle", "smuggle_drop") then return false end

local route = city.route("smuggle")

return {
  title = "Smuggler's Run",
  after = "06_takedown",
  start = {city.place("smuggle_drop")},
  reward = 2000,
  run = function(m)
    m:timer(240)
    for i, n in ipairs(route) do
      local pkg = m:spawn{mesh = "crate", pos = {n[1], 0.6 + U.ground(n[1], n[2]), n[2]}, size = 0.9, color = {0.75, 0.55, 0.3}}
      local marker = m:marker(n[1], n[2], {1, 0.5, 0.1})
      m:say(string.format("Pick up package %d of %d%s.", i, #route, m:on_street(n[1], n[2])))
      m:wait(function() return m:near(marker, 5) end)
      m:remove(marker)
      m:remove(pkg)
      engine.play("pickup")
      U.message(string.format("PACKAGE %d/%d", i, #route), 2)
      wanted.set(math.min(3, math.max(wanted.stars(), i - 1)))
    end

    local dx, dz = city.place("smuggle_drop")
    local drop = m:marker(dx, dz, {0.2, 1, 0.4})
    local where = m:on_street(dx, dz)
    m:wait(function()
      local hot = wanted.stars() > 0
      m:say(hot and "Lose the cops, then make the drop." or ("Make the drop" .. where .. "."))
      return not hot and m:near(drop, 6)
    end)
  end,
}
