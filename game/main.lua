-- Entry point. The engine calls nothing but the event bus:
--   init, tick(dt), frame(dt), key(name, down), contact(a, b, speed)
-- Everything below is ordinary game code; change it and it hot-reloads.
local G = require "lib.state"
require "lib.progress" -- loads saved cash and missions before anything reads them
local prefabs = require "lib.prefabs"
local city = require "lib.city"
local player = require "lib.player"
local vehicle = require "lib.vehicle"
local mission = require "lib.mission"
local traffic = require "systems.traffic"
local police = require "systems.police"
local peds = require "systems.peds"
local daynight = require "lib.daynight"
local pickups = require "lib.pickups"
require "lib.health"
require "systems.carnage"
require "systems.weapons"
local sfx = require "lib.sfx"
require "lib.stunts"
require "lib.camera"
require "lib.hud"
require "systems.garage"
require "lib.menu"
require "lib.shop"

engine.on("init", function()
  math.randomseed(1337)
  engine.fog(110, 380)

  prefabs.build()
  sfx.build()
  police.build()
  pickups.build()
  peds.build()
  G.city = city.build()
  daynight.light_lamps()
  daynight.set_hour(tonumber(os.getenv("HOUR") or "") or daynight.hour) -- HOUR=22 starts at night

  -- Start on the sidewalk by the parking lot, with a few cars to pick from.
  local lx, lz = city.block_center(G.city.lot[1], G.city.lot[2])
  for s = -3, 2 do vehicle.spawn(lx + s * 4 + 4, lz, 0) end
  G.spawn = {lx - 6, 1.2, lz - 15}
  player.spawn(G.spawn[1], G.spawn[2], G.spawn[3], 0)
  G.cam_yaw = 0.3

  traffic.start(20)
  peds.start()
  pickups.start()
  -- The hospital: where you wake up after getting wasted.
  local hx, hz = city.block_center(G.city.hospital[1], G.city.hospital[2])
  G.hospital = {hx - G.city.bx / 2 + 1.5, 1.2, hz}
  mission.load_all("missions")
  require("systems.garage").build()
  require("systems.gunshop").build()
  require("systems.paintshop").build()
  require("systems.dealer").build()
  engine.grab_mouse(true)
end)

-- AUTO_TEST=1 plays the game by itself and quits (used by CI in headless mode).
if os.getenv("AUTO_TEST") then require "test.autoplay" end
if os.getenv("SOAK") then require "test.soak" end
if os.getenv("GARAGE_TEST") then require "test.garage" end
if os.getenv("SAVE_TEST") then require "test.save" end
if os.getenv("MENU_TEST") then require "test.menu" end
if os.getenv("SHOP_TEST") then require "test.shops" end
if os.getenv("CITY_TEST") then require "test.city" end
if os.getenv("PAD_TEST") then require "test.pad" end
if os.getenv("SHOT_CAM") then require "test.shot" end

-- Click to recapture the mouse after Escape.
engine.on("key", function(k, down) if k == "mouse1" and down then engine.grab_mouse(true) end end)

-- Every crate you ram is worth a dollar (once). Contacts fire every tick bodies touch.
local rammed = {}
engine.on("contact", function(a, b)
  if G.vehicle and (a == G.vehicle or b == G.vehicle) then
    local other = a == G.vehicle and b or a
    if engine.tag(other) == "crate" and not rammed[other] then
      rammed[other] = true
      G.cash = G.cash + 1
    end
  end
end)

-- Mods last, so their "init" handlers run after the city exists.
engine.load_mods("mods")
