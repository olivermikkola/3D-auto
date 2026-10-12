-- Shared plumbing for places that sell things: a zone you stand (or park)
-- in, a prompt at the bottom of the screen, a letter on the minimap, and R
-- to use it. systems/gunshop, paintshop and dealer are built on this.
--
--   shop.add{name = "GUN SHOP", x = .., z = .., hw = 2, hd = 2, letter = "G",
--            color = {r,g,b}, car = false,      -- true: you must be driving
--            prompt = fn -> text | nil,         -- optional; default "R: <name>"
--            use = fn}                          -- R pressed in the zone
local G = require "lib.state"
local U = require "lib.util"

local S = {list = {}}

function S.add(def)
  S.list[#S.list + 1] = def
  return def
end

-- The player (or their car) is in the shop's zone, on foot or driving as it requires.
function S.here(def)
  if G.dead or (def.car and not G.vehicle) or (not def.car and G.vehicle) then return false end
  local x, y, z = U.player_pos()
  return x ~= nil and math.abs(x - def.x) <= def.hw and math.abs(z - def.z) <= def.hd and y < 3
end

function S.current()
  for _, def in ipairs(S.list) do if S.here(def) then return def end end
end

-- Take the money, or say why not. Returns true if paid.
function S.pay(price)
  if G.cash < price then
    U.message(string.format("YOU NEED $%d", price), 2)
    engine.play("click", {ui = true})
    return false
  end
  G.cash = G.cash - price
  engine.play("buy", {ui = true})
  engine.emit("purchase", price)
  return true
end

-- Value text for a menu row: the price, red when you can't afford it.
function S.price(price)
  return string.format("$%d", price), G.cash >= price and {0.4, 0.9, 0.4} or {1, 0.35, 0.3}
end

-- Cars must be stopped and on their wheels before anyone works on them.
function S.parked(id)
  local vx, vy, vz = engine.vel(id)
  return vx and vx * vx + vy * vy + vz * vz <= 1 and require("lib.vehicle").on_wheels(id)
end

engine.on("init", function()
  engine.synth("buy", {wave = "square", notes = {660, 990}, note_len = 0.06, volume = 0.25, lowpass = 0.5})
end)

engine.on("key", function(k, down)
  if k ~= "r" or not down then return end
  local def = S.current()
  if def then def.use() end
end)

engine.on("frame", function()
  local def = S.current()
  if not def then return end
  local text = def.prompt and def.prompt() or ("R: " .. def.name)
  local w, h = engine.screen()
  local tw = engine.text_width(text, 18)
  local c = def.color
  engine.rect((w - tw) / 2 - 10, h - 135, tw + 20, 30, 0, 0, 0, 0.7)
  engine.text(text, (w - tw) / 2, h - 129, 18, c[1], c[2], c[3], 1)
end)

engine.on("minimap", function(map)
  for _, def in ipairs(S.list) do
    local x, y = map(def.x, def.z)
    local c = def.color
    engine.rect(x - 4, y - 4, 8, 8, c[1], c[2], c[3], 1)
    engine.text(def.letter, x + 6, y - 6, 10, c[1], c[2], c[3], 1)
  end
end)

return S
