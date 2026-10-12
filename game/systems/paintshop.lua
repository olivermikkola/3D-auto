-- Pay 'n' Spray in the parking lot. Drive in, stop, press R and pick a
-- color. A respray also clears your wanted level, as long as the cops can't
-- see you go in. They don't do cop cars.
local G = require "lib.state"
local U = require "lib.util"
local city = require "lib.city"
local shop = require "lib.shop"
local menu = require "lib.menu"
local wanted = require "lib.wanted"
local prefabs = require "lib.prefabs"

local M = {BASE = 100, PER_STAR = 100}
M.names = {"RED", "BLUE", "YELLOW", "GREEN", "WHITE", "BLACK", "PURPLE", "ORANGE"}

function M.price() return M.BASE + M.PER_STAR * wanted.stars() end

-- Why the car can't be painted right now, if it can't.
function M.refusal(id)
  if engine.tag(id) ~= "car" then return "WE DON'T PAINT COP CARS" end
  if not shop.parked(id) then return "STOP ON YOUR WHEELS TO RESPRAY" end
  if wanted.stars() > 0 and wanted.seen then return "LOSE THE COPS' SIGHT FIRST" end
end

local car -- the car being painted while the menu is open

local page = {title = function() return string.format("PAY 'N' SPRAY  $%d", M.price()) end, items = {}}
for i = 1, #prefabs.car_colors do
  page.items[#page.items + 1] = {
    label = M.names[i] or ("COLOR " .. i),
    value = function()
      if engine.mesh_of(car) == "car" .. i then return "CURRENT", {0.6, 0.6, 0.6} end
      return shop.price(M.price())
    end,
    act = function()
      if engine.mesh_of(car) == "car" .. i then return end
      local stars = wanted.stars()
      if not shop.pay(M.price()) then return end
      engine.set_mesh(car, "car" .. i)
      if stars > 0 then wanted.clear() end
      menu.close()
      U.message(stars > 0 and "RESPRAYED. THE COPS LOST YOUR TRAIL" or "FRESH PAINT", 3)
      engine.play("spray", {follow = car})
      engine.emit("resprayed", car, i)
    end,
  }
end
page.items[#page.items + 1] = {label = "LEAVE", act = function() menu.close() end}
menu.add_page("paintshop", page)

function M.build()
  local lx, lz = city.block_center(G.city.lot[1], G.city.lot[2])
  M.x, M.z = lx + 9, lz + 10
  local x, z = M.x, M.z
  engine.spawn{mesh = "plane", pos = {x, 0.27, z}, size = {6, 1, 9}, color = {0.55, 0.15, 0.55}, tag = "shop"}
  for _, side in ipairs{-1, 1} do
    engine.spawn{mesh = "cube", pos = {x + side * 3.5, 2.4, z}, size = {0.35, 4.4, 9}, body = "static",
                 color = {0.45, 0.2, 0.5}, tag = "shop"}
  end
  engine.spawn{mesh = "cube", pos = {x, 4.8, z}, size = {8, 0.4, 9}, body = "static", color = {0.25, 0.1, 0.3}, tag = "shop"}
  engine.spawn{mesh = "cube", pos = {x, 4.4, z - 4.4}, size = {7, 0.4, 0.15}, color = {1, 0.3, 0.9}, glow = 1, tag = "shop"}
  engine.light{pos = {x, 3.8, z}, color = {1, 0.4, 0.9}, radius = 12, intensity = 1.5}
  engine.synth("spray", {wave = "noise", freq = 4000, dur = 1.2, attack = 0.1, release = 0.4, volume = 0.35, lowpass = 0.7})
  shop.add{name = "PAY 'N' SPRAY", x = x, z = z, hw = 2, hd = 2.5, letter = "P", color = {1, 0.4, 0.9}, car = true,
           prompt = function()
             return M.refusal(G.vehicle) or string.format("R: PAY 'N' SPRAY $%d", M.price())
           end,
           use = function()
             local why = M.refusal(G.vehicle)
             if why then return U.message(why, 2) end
             car = G.vehicle
             menu.show("paintshop")
           end}
end

return M
