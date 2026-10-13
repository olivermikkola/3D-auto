-- A small repair bay in the starting lot. R confirms the purchase.
local G = require "lib.state"
local H = require "lib.health"
local city = require "lib.city"
local U = require "lib.util"
local garage = {PRICE = 100}

-- Keep the entire car inside the painted bay, not just near its center.
function garage.inside(id)
  if not garage.x or not id or not engine.exists(id) then return false end
  local x, y, z = engine.pos(id)
  y = y - U.ground(x, z)
  return math.abs(x - garage.x) <= 2 and math.abs(z - garage.z) <= 2.5 and y >= 0.3 and y <= 1.6
end

function garage.build()
  local x, z = city.place("lot")
  garage.x, garage.z = x, z - 10
  -- Open north/south entrances; tucked behind the parked cars, beside spawn.
  engine.spawn{mesh = "plane", pos = {x, 0.27 + U.ground(x, garage.z), garage.z}, size = {6, 1, 9}, color = {0.1, 0.65, 0.7}, tag = "garage"}
  for _, side in ipairs{-1, 1} do
    engine.spawn{mesh = "cube", pos = {x + side * 3.5, 2.4 + U.ground(x + side * 3.5, garage.z), garage.z}, size = {0.35, 4.4, 0.35},
                 body = "static", color = {0.15, 0.7, 0.75}, tag = "garage"}
  end
  engine.spawn{mesh = "cube", pos = {x, 4.8 + U.ground(x, garage.z), garage.z}, size = {8, 0.4, 9}, body = "static",
               color = {0.12, 0.3, 0.35}, tag = "garage"}
  engine.spawn{mesh = "cube", pos = {x, 4.4 + U.ground(x, garage.z - 4.4), garage.z - 4.4}, size = {7, 0.4, 0.15},
               color = {0.1, 1, 0.9}, glow = 1, tag = "garage"}
  engine.light{pos = {x, 3.8 + U.ground(x, garage.z), garage.z}, color = {0.2, 1, 0.9}, radius = 12, intensity = 1.5}
  engine.synth("repair", {wave = "triangle", notes = {440, 554, 659, 880}, note_len = 0.09, volume = 0.4})
end

engine.on("key", function(k, down)
  if k ~= "r" or not down or not G.vehicle then return end
  local id = G.vehicle
  if G.dead or not garage.inside(id) then return end
  if require("lib.wanted").stars() > 0 then return U.message("GARAGE CLOSED: LOSE THE COPS", 2) end
  local vx, vy, vz = engine.vel(id)
  if vx * vx + vy * vy + vz * vz > 1 or not require("lib.vehicle").on_wheels(id) then
    return U.message("STOP ON YOUR WHEELS TO REPAIR", 2)
  end
  local hp = H.get(id)
  if not hp then return end
  if hp >= H.VEHICLE_HP then return U.message("CAR ALREADY REPAIRED", 2) end
  if G.cash < garage.PRICE then return U.message("REPAIR NEEDS $" .. garage.PRICE, 2) end
  H.hp[id] = H.max[id] or H.VEHICLE_HP
  require("systems.carnage").burning[id] = nil
  G.cash = G.cash - garage.PRICE
  U.message("CAR REPAIRED -$" .. garage.PRICE, 3)
  engine.play("repair", {follow = id})
  engine.emit("vehicle_repaired", id, garage.PRICE)
end)

engine.on("minimap", function(map)
  if not garage.x then return end
  local x, y = map(garage.x, garage.z)
  engine.rect(x - 4, y - 4, 8, 8, 0.1, 1, 0.9, 1)
  engine.text("R", x + 6, y - 6, 10, 0.1, 1, 0.9, 1)
end)

engine.on("frame", function()
  if G.dead or not garage.inside(G.vehicle or G.player) then return end
  local text = "REPAIR GARAGE: BRING A CAR"
  if G.vehicle then
    text = "R: REPAIR CAR -$" .. garage.PRICE
    if require("lib.wanted").stars() > 0 then text = "GARAGE CLOSED: LOSE THE COPS"
    elseif (H.get(G.vehicle) or H.VEHICLE_HP) >= H.VEHICLE_HP then text = "CAR ALREADY REPAIRED"
    elseif G.cash < garage.PRICE then text = "REPAIR NEEDS $" .. garage.PRICE
    else
      local vx, vy, vz = engine.vel(G.vehicle)
      if vx * vx + vy * vy + vz * vz > 1 or not require("lib.vehicle").on_wheels(G.vehicle) then
        text = "STOP ON YOUR WHEELS TO REPAIR -$" .. garage.PRICE
      end
    end
  end
  local w, h = engine.screen()
  local tw = engine.text_width(text, 18)
  engine.rect((w - tw) / 2 - 10, h - 135, tw + 20, 30, 0, 0, 0, 0.7)
  engine.text(text, (w - tw) / 2, h - 129, 18, 0.1, 1, 0.9, 1)
end)

return garage
