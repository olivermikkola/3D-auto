-- Airtime and rollover bonuses, scored when the player's car comes back down.
local G = require "lib.state"
local U = require "lib.util"
local vehicle = require "lib.vehicle"

local air, peak, flips, last_up, upside_t = 0, 0, 0, 1, 0

engine.on("tick", function(dt)
  local id = G.vehicle
  if not id or not engine.exists(id) then air, peak, flips = 0, 0, 0 return end
  local _, y = engine.pos(id)
  local _, uy = engine.up(id)
  if not engine.grounded(id) then
    air = air + dt
    peak = math.max(peak, y)
    -- Count half-rolls: the up axis crossing horizontal.
    if (uy < 0) ~= (last_up < 0) then flips = flips + 0.5 end
  else
    if air > 0.8 then
      local cash = math.floor(air * 40 + peak * 8 + math.floor(flips) * 150)
      local what = flips >= 1 and string.format("%d-FLIP STUNT!", math.floor(flips)) or "STUNT JUMP!"
      G.cash = G.cash + cash
      U.message(string.format("%s %.1fs  +$%d", what, air, cash), 3)
      engine.emit("stunt", air, peak, flips)
    end
    air, peak, flips = 0, 0, 0
  end
  last_up = uy

  -- Stuck on the roof: tell the player how to get out.
  upside_t = vehicle.upside_down(id) and math.abs(vehicle.speed(id)) < 2 and upside_t + dt or 0
  if upside_t > 1.5 and math.floor(upside_t * 2) ~= math.floor((upside_t - dt) * 2) and upside_t < 2.1 then
    U.message("WRECKED. PRESS E TO GET OUT", 3)
  end
end)
