-- Entry point. The engine calls nothing but the event bus:
--   init, tick(dt), frame(dt), key(name, down), contact(a, b, speed)
-- Everything below is ordinary game code; change it and it hot-reloads.
local G = require "lib.state"
local prefabs = require "lib.prefabs"
local city = require "lib.city"
local player = require "lib.player"
local vehicle = require "lib.vehicle"
local mission = require "lib.mission"
local traffic = require "systems.traffic"
local police = require "systems.police"
local peds = require "systems.peds"
local daynight = require "lib.daynight"
local sfx = require "lib.sfx"
require "lib.stunts"
require "lib.camera"
require "lib.hud"

engine.on("init", function()
  math.randomseed(1337)
  engine.fog(90, 320)

  prefabs.build()
  sfx.build()
  police.build()
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

  traffic.start(18)
  peds.start()
  mission.load_all("missions")
  engine.grab_mouse(true)
end)

-- AUTO_TEST=1 plays the game by itself and quits (used by CI in headless mode).
if os.getenv("AUTO_TEST") then require "test.autoplay" end
if os.getenv("SOAK") then require "test.soak" end

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
