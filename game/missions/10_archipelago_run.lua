-- Infiltrate the Port of Turku container berths past Turun linna (Turku Castle),
-- commandeer an offshore Puskuri speedboat, blast down the Aurajoki mouth,
-- dodge marine pursuit, and escape into the Turku archipelago.
local city = require "lib.city"
local U = require "lib.util"
local vehicle = require "lib.vehicle"
local wanted = require "lib.wanted"

if not city.has("castle", "speedboat_dock", "archipelago_drop") then return false end

local start_pos = {city.place("castle")}
local dock_pos = {city.place("speedboat_dock")}
local drop_pos = {city.place("archipelago_drop")}

return {
  title = "The Archipelago Run",
  after = "09_foli_transit",
  start = start_pos,
  reward = 6000,
  run = function(m)
    m:timer(280)
    m:say("Head past Turun linna to the harbor berths and secure the offshore speedboat.")

    -- Spawn Puskuri speedboat moored at the pier
    local boat_id = m:spawn(vehicle.spawn(dock_pos[1], dock_pos[2], -0.7, nil, "speedboat", "boat"))

    local dock_marker = m:marker(dock_pos[1], dock_pos[2], {0.2, 0.8, 0.3})
    m:wait(function()
      return m:in_vehicle(boat_id) or m:near(dock_marker, 6)
    end)
    m:remove(dock_marker)

    -- Player boards the speedboat -> marine alarm triggers wanted level 4!
    m:wait(function() return m:in_vehicle(boat_id) end)
    wanted.set(4)
    U.message("HARBOR ALARM: SPEEDBOAT COMMANDERED!", 4)
    engine.play("star")

    -- Guide player to blast open throttle down the river mouth into the archipelago
    local drop_marker = m:marker(drop_pos[1], drop_pos[2], {0.95, 0.85, 0.1})
    m:say("Open the throttle! Blast down the river mouth and escape into the archipelago!")

    m:wait(function()
      local in_boat = m:in_vehicle(boat_id)
      local near_drop = m:near(drop_marker, 12)
      if not in_boat then
        m:say("Get back in the speedboat!")
      end
      return in_boat and near_drop
    end)

    m:remove(drop_marker)
    wanted.clear()
    U.message("ARCHIPELAGO REACHED: CLEAN GETAWAY!", 4)
  end,
}
