-- A gun shop on the sidewalk across the street from the parking lot. On
-- foot, R opens its counter (a menu page): pistol ammo and the SMG.
local G = require "lib.state"
local U = require "lib.util"
local city = require "lib.city"
local shop = require "lib.shop"
local menu = require "lib.menu"

local M = {}
M.items = {
  {label = "PISTOL AMMO (+24)", weapon = "pistol", rounds = 24, price = 60},
  {label = "SMG (+90 ROUNDS)", weapon = "smg", rounds = 90, price = 250},
}

local page = {title = "GUN SHOP", items = {}}
for _, it in ipairs(M.items) do
  page.items[#page.items + 1] = {
    label = it.label,
    value = function() return shop.price(it.price) end,
    act = function()
      if not shop.pay(it.price) then return end
      G.ammo[it.weapon] = (G.ammo[it.weapon] or 0) + it.rounds
      U.message(string.format("%s -$%d", it.label, it.price), 2)
    end,
  }
end
page.items[#page.items + 1] = {label = "LEAVE", act = function() menu.close() end}
menu.add_page("gunshop", page)

-- The first ordinary downtown block of the map's candidates gets the shop
-- on its south face (the street wall is flush with the sidewalk), facing the
-- street. No candidate, no gun shop.
function M.build()
  local L = G.city
  local bi, bj
  for _, c in ipairs(city.map().gunshop or {}) do
    if L.kinds[c[1] .. "," .. c[2]] == "buildings" and city.district(c[1], c[2]) == "downtown" then bi, bj = c[1], c[2] break end
  end
  if not bi then return end
  local cx, cz = city.block_center(bi, bj)
  local face = cz + L.bz / 2 - L.walk -- buildings' south wall
  local x = cx
  -- Storefront: door, window, a red awning and a glowing sign. Nothing solid,
  -- so pedestrians still walk the sidewalk.
  engine.spawn{mesh = "cube", pos = {x, 1.45, face + 0.08}, size = {1.6, 2.5, 0.12}, color = {0.25, 0.12, 0.08}, tag = "shop"}
  engine.spawn{mesh = "cube", pos = {x + 2.2, 1.6, face + 0.08}, size = {2.2, 1.6, 0.12}, color = {0.9, 0.75, 0.4}, glow = 0.6, tag = "shop"}
  engine.spawn{mesh = "cube", pos = {x + 0.8, 3.15, face + 0.9}, size = {5.4, 0.2, 1.8}, color = {0.75, 0.1, 0.08}, tag = "shop"}
  engine.spawn{mesh = "cube", pos = {x + 0.8, 3.75, face + 0.1}, size = {4, 0.7, 0.15}, color = {1, 0.25, 0.15}, glow = 1, tag = "shop"}
  engine.light{pos = {x + 0.8, 2.8, face + 1.5}, color = {1, 0.4, 0.3}, radius = 9, intensity = 1.2}
  M.x, M.z = x, face + 1.6
  shop.add{name = "GUN SHOP", x = M.x, z = M.z, hw = 2.2, hd = 1.5, letter = "G", color = {1, 0.35, 0.25},
           use = function() menu.show("gunshop") end}
end

return M
