-- Infiltrate Pansion varuskunta, steal the prototype Sisu Pasi 6x6 APC from the motor pool,
-- smash through the security gate, and escape to the safehouse.
local city = require "lib.city"
local U = require "lib.util"
local vehicle = require "lib.vehicle"
local wanted = require "lib.wanted"

if not city.has("heist_start", "heist_pasi", "heist_drop") then return false end

local start_pos = {city.place("heist_start")}
local pasi_pos = {city.place("heist_pasi")}
local drop_pos = {city.place("heist_drop")}

return {
  title = "Pansio Base Heist",
  after = "07_smuggler",
  start = start_pos,
  reward = 5000,
  run = function(m)
    m:timer(300)
    m:say("Infiltrate the garrison and reach the prototype Sisu Pasi APC.")

    -- Spawn prototype Sisu Pasi parked in the military depot
    local pasi_id = m:spawn(vehicle.spawn(pasi_pos[1], pasi_pos[2], 0, nil, "pasi", "pasi"))

    -- Infiltration marker
    local target_marker = m:marker(pasi_pos[1], pasi_pos[2], {0.2, 0.8, 0.3})
    m:wait(function()
      return m:in_vehicle(pasi_id) or m:near(target_marker, 6)
    end)
    m:remove(target_marker)

    -- Player gets into the Pasi -> sound the military alarm and raise 5 stars!
    m:wait(function() return m:in_vehicle(pasi_id) end)
    wanted.set(5)
    U.message("MILITARY ALARM: SISU PASI STOLEN!", 4)
    engine.play("star")

    -- Guide player to break out through the boom barrier gate and deliver to the safehouse
    local drop_marker = m:marker(drop_pos[1], drop_pos[2], {0.9, 0.2, 0.1})
    m:say("Smash through the gate and deliver the Pasi to the safehouse!")

    m:wait(function()
      local in_pasi = m:in_vehicle(pasi_id)
      local near_drop = m:near(drop_marker, 10)
      if not in_pasi then
        m:say("Get back in the Sisu Pasi!")
      end
      return in_pasi and near_drop
    end)

    m:remove(drop_marker)
    wanted.clear()
    U.message("PASI DELIVERED SAFELY!", 4)
  end,
}
