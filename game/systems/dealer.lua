-- A car dealer in the parking lot. Buy a car of your own and it waits in
-- your space, marked on the minimap. It's saved: every time the game
-- starts, your car is back in its space, whatever happened to it.
local G = require "lib.state"
local U = require "lib.util"
local city = require "lib.city"
local shop = require "lib.shop"
local menu = require "lib.menu"
local vehicle = require "lib.vehicle"
local prefabs = require "lib.prefabs"

local M = {PRICE = 600}

-- Your car, in your space. Replaces the one you had (if it's still around).
function M.deliver(color)
  if M.car and engine.exists(M.car) and M.car ~= G.vehicle then engine.despawn(M.car) end
  M.car = vehicle.spawn(M.space[1], M.space[2], 0, color)
  G.owned_car = {color = color}
  require("lib.progress").touch()
  return M.car
end

local page = {title = "CAR DEALER", items = {}}
local names = require("systems.paintshop").names
for i = 1, #prefabs.car_colors do
  page.items[#page.items + 1] = {
    label = (names[i] or "COLOR " .. i) .. " CAR",
    value = function() return shop.price(M.PRICE) end,
    act = function()
      if not shop.pay(M.PRICE) then return end
      M.deliver(i)
      menu.close()
      U.message("YOUR NEW CAR IS IN YOUR SPACE", 4)
      engine.emit("car_bought", M.car, i)
    end,
  }
end
page.items[#page.items + 1] = {label = "LEAVE", act = function() menu.close() end}
menu.add_page("dealer", page)

function M.build()
  local lx, lz = city.place("lot")
  M.space = {lx - 9, lz + 11}
  M.x, M.z = lx - 13, lz + 4
  -- The sales booth, and your space with a blue outline.
  engine.spawn{mesh = "cube", pos = {M.x - 1, 1.5, M.z}, size = {2, 2.6, 2.4}, body = "static", color = {0.85, 0.85, 0.8}, tag = "shop"}
  engine.spawn{mesh = "cube", pos = {M.x - 1, 2.95, M.z}, size = {2.4, 0.3, 2.8}, color = {0.2, 0.5, 1}, glow = 1, tag = "shop"}
  local sx, sz = M.space[1], M.space[2]
  for _, e in ipairs{{0, -3, 3.4, 0.15}, {0, 3, 3.4, 0.15}, {-1.7, 0, 0.15, 6}, {1.7, 0, 0.15, 6}} do
    engine.spawn{mesh = "plane", pos = {sx + e[1], 0.25, sz + e[2]}, size = {e[3], 1, e[4]}, color = {0.2, 0.5, 1}, glow = 0.5}
  end
  shop.add{name = "CAR DEALER", x = M.x + 0.6, z = M.z, hw = 1.6, hd = 2, letter = "D", color = {0.3, 0.6, 1},
           use = function() menu.show("dealer") end}
  if G.owned_car then M.deliver(G.owned_car.color) end
end

engine.on("resprayed", function(id, color)
  if id == M.car then
    G.owned_car = {color = color}
    require("lib.progress").touch()
  end
end)

engine.on("minimap", function(map)
  if not (M.car and engine.exists(M.car)) or M.car == G.vehicle then return end
  local x, _, z = engine.pos(M.car)
  local px, py = map(x, z)
  engine.rect(px - 3, py - 3, 6, 6, 1, 1, 1, 1)
  engine.rect(px - 2, py - 2, 4, 4, 0.2, 0.5, 1, 1)
end)

return M
