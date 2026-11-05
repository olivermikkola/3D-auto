-- Under the Square: Oliver's chase (docs/ROADMAP, Stairs to Hiding in
-- Logomo) as a mission. Rob the Lumis van at Kauppatori's taxi rank, then
-- three stars: down Toriparkki's ramp under the square, through to Louhi's
-- hall and up its tunnel to Ajurinkatu, leave the car, and into Logomo on
-- foot to lie low until the cops give up. Turku only: the places are the
-- underground's own (systems/louhi, toriparkki, hideouts).
local city = require "lib.city"

if not (city.has("under_square_start") and city.has("taxi_rank")) then return false end
if (city.map() or {}).id ~= "turku" then return false end

local OUT_OF_LOUHI = 45 -- m from the portal on Ajurinkatu: up its tunnel

return {
  title = "Under the Square",
  start = {city.place("under_square_start")},
  reward = 2500,
  run = function(m)
    local Lh = require "systems.louhi"
    local Tp = require "systems.toriparkki"
    local hideouts = require "systems.hideouts"
    local L = require "systems.landmarks"
    local logomo = hideouts.list[1]
    if not (Lh.built and Tp.portal and L.LOUHI and logomo) then m:fail("NO WAY UNDER THE SQUARE") end
    local rx, rz = city.place("taxi_rank")

    m:say("Get a car and drive to the Lumis van at Kauppatori's taxi rank.")
    local van = m:marker(rx, rz, {0.3, 1, 0.4})
    m:wait(function() return m:in_car() and m:near(van, 6) end)
    m:say("Stay in the marker while the crew empties the van...")
    local t = 0
    m:wait(function()
      t = m:near(van, 7) and t + 1 / 60 or 0
      return t > 3
    end)
    m:remove(van)

    m:wanted(3)
    local ox, oz = Lh.hall_xz(Tp.portal.outside[1], Tp.portal.outside[2])
    m:say("Under the square! Down Toriparkki's ramp on Yliopistonkatu.")
    local ramp = m:marker(ox, oz)
    m:wait(function() return Lh.down() end)
    m:remove(ramp)

    m:say("Through to Louhi's hall and up its tunnel to Ajurinkatu.")
    local lx, lz = L.LOUHI.x, L.LOUHI.z
    local portal = m:marker(lx, lz)
    m:wait(function()
      local you = require("lib.state").vehicle or require("lib.state").player
      if not you or Lh.down() then return false end
      local x, _, z = engine.pos(you)
      return require("lib.util").dist2d(x, z, lx, lz) < OUT_OF_LOUHI
    end)
    m:remove(portal)

    m:say("Ditch the car: over Logomonsilta on foot and into Logomo.")
    local door = m:marker(logomo.x, logomo.z)
    -- (Logomo's door only takes you in with the cops after you: lost them
    -- on the way, you're done.)
    m:wait(function() return hideouts.hidden() or m:stars() == 0 end)
    m:remove(door)

    m:say("Lie low in Logomo until they give up.")
    m:wait(function() return m:stars() == 0 end)
  end,
}
