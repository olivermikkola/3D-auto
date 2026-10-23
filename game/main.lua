-- Entry point. The engine calls nothing but the event bus:
--   init, tick(dt), frame(dt), key(name, down), contact(a, b, speed)
-- Everything below is ordinary game code; change it and it hot-reloads.
local G = require "lib.state"
local U = require "lib.util"
require "lib.progress" -- loads saved cash and missions before anything reads them
local prefabs = require "lib.prefabs"
local city = require "lib.city"
local settings = require "lib.settings"
-- The map, before anything asks the city where things are: the one picked
-- in the pause menu, or MAP=<name> for any in maps/.
city.use(city.start())
local player = require "lib.player"
local vehicle = require "lib.vehicle"
local mission = require "lib.mission"
local traffic = require "systems.traffic"
local police = require "systems.police"
local peds = require "systems.peds"
local daynight = require "lib.daynight"
local weather = require "lib.weather"
local pickups = require "lib.pickups"
local wanted = require "lib.wanted"
require "lib.health"
require "systems.carnage"
require "systems.shore"
require "systems.weapons"
local sfx = require "lib.sfx"
require "lib.stunts"
require "lib.camera"
require "lib.hud"
require "lib.story"
require "story.radio"
require "systems.garage"
require "systems.cashvan"
require "systems.heli"
require "systems.racer"
require "systems.fares"
require "systems.ambulance"
require "lib.menu"
require "lib.shop"

engine.on("init", function()
  -- Keep the default repeatable; SEED makes population/AI failures reproducible.
  local seed = os.getenv("SEED")
  seed = seed and assert(math.tointeger(tonumber(seed)), "SEED must be an integer") or 1337
  math.randomseed(seed)
  print(string.format("map=%s seed=%d", city.map().id or city.map().name, seed))
  local fog = city.map().fog or {110, 380} -- a map can see further
  settings.watch("view", function(p) weather.base_fog(fog[1] * p / 100, fog[2] * p / 100) end)

  prefabs.build()
  sfx.build()
  police.build()
  pickups.build()
  peds.build()
  G.city = city.build()
  require("lib.borders").build(city.map())
  require("systems.aurajoki").build(city.map())
  require("systems.kakola").build(city.map())
  require("systems.harbor").build(city.map())
  require("systems.kauppatori").build(city.map())
  require("systems.suurtori").build(city.map())
  daynight.light_lamps()
  daynight.set_hour(tonumber(os.getenv("HOUR") or "") or daynight.hour) -- HOUR=22 starts at night

  -- Start on the sidewalk by the parking lot, with a few cars to pick from.
  local lx, lz = city.place("lot")
  -- (the far end: a sports car and a van)
  for s = -3, 2 do vehicle.spawn(lx + s * 4 + 4, lz, 0, nil, s == 1 and "sports" or (s == 2 and "van" or nil)) end
  G.spawn = {lx - 6, 1.2 + U.ground(lx - 6, lz - 15), lz - 15}

  local transfer = engine.load("cross_city_transfer")
  if transfer then
    engine.save("cross_city_transfer", nil)
    local tx, tz = transfer.target_pos[1], transfer.target_pos[2]
    G.spawn = {tx, 1.2 + U.ground(tx, tz), tz}
    player.spawn(G.spawn[1], G.spawn[2], G.spawn[3], 0)
    if transfer.in_vehicle then
      local v_id = vehicle.spawn(tx, tz, 0)
      G.vehicle = v_id
      if G.player then
        engine.despawn(G.player)
        G.player = nil
      end
    end
    if transfer.wanted_stars and transfer.wanted_stars > 0 then
      wanted.set(transfer.wanted_stars)
    end
  else
    player.spawn(G.spawn[1], G.spawn[2], G.spawn[3], 0)
  end
  G.cam_yaw = 0.3

  traffic.start(20)
  peds.start()
  pickups.start()
  -- The hospital: where you wake up after getting wasted.
  local hx, hz = city.place("hospital")
  G.hospital = {hx, 1.2 + U.ground(hx, hz), hz}
  mission.load_all("missions")
  require("systems.garage").build()
  require("systems.gunshop").build()
  require("systems.paintshop").build()
  require("systems.dealer").build()
  require("systems.cashvan").build()
  require("systems.ambulance").build()
  require("systems.heli").build()
  engine.grab_mouse(true)
end)

-- Every test ends by calling engine.quit(), passed or failed. Running out of
-- --headless ticks first means it got stuck, which must not exit zero.
local TESTS = {"AUTO_TEST", "SOAK", "GARAGE_TEST", "SAVE_TEST", "MENU_TEST", "SHOP_TEST",
               "CITY_TEST", "PAD_TEST", "RELIABILITY_TEST", "MISSION_TEST"}
for _, var in ipairs(TESTS) do
  if os.getenv(var) then
    local quit, reload, finished = engine.quit, engine.reload, false
    engine.quit = function(...) finished = true; return quit(...) end
    engine.reload = function(...) finished = true; return reload(...) end -- it carries on afresh
    engine.on("quit", function()
      if not finished then error("TEST FAILED: " .. var .. " ran out of ticks before finishing", 0) end
    end)
    break
  end
end

-- AUTO_TEST=1 plays the game by itself and quits (used by CI in headless mode).
if os.getenv("AUTO_TEST") then require "test.autoplay" end
if os.getenv("SOAK") then require "test.soak" end
if os.getenv("GARAGE_TEST") then require "test.garage" end
if os.getenv("SAVE_TEST") then require "test.save" end
if os.getenv("MENU_TEST") then require "test.menu" end
if os.getenv("SHOP_TEST") then require "test.shops" end
if os.getenv("CITY_TEST") then require "test.city" end
if os.getenv("PAD_TEST") then require "test.pad" end
if os.getenv("RELIABILITY_TEST") then require "test.reliability" end
if os.getenv("MISSION_TEST") then require "test.missions" end
if os.getenv("TERRAIN_TEST") then require "test.terrain" end
if os.getenv("BORDER_TEST") then require "test.border_probe" end
if os.getenv("KERB_TEST") then require "test.kerb_probe" end
if os.getenv("ARCH_TEST") then require "test.arch_probe" end
if os.getenv("PASI_TEST") then require "test.pasi_probe" end
if os.getenv("FOLI_TEST") then require "test.foli_probe" end
if os.getenv("CHUNK_TEST") then require "test.chunk_probe" end
if os.getenv("CORRIDOR_TEST") then require "test.corridor_probe" end
if os.getenv("MAP_TEST") then require "test.map_probe" end
if os.getenv("AURAJOKI_TEST") then require "test.aurajoki_probe" end
if os.getenv("DIRECTION_TEST") then require "test.direction_probe" end
if os.getenv("DEAD_END_TEST") then require "test.dead_end_probe" end
if os.getenv("POI_TEST") then require "test.poi_probe" end
if os.getenv("TEMPLATE_TEST") then require "test.template_probe" end
if os.getenv("DRIVE_SWEEP") then require "test.drive_sweep" end
if os.getenv("PED_SWEEP") then require "test.ped_sweep" end
if os.getenv("PROFILE_DRIVE") then require "test.profile_drive" end
if os.getenv("PLAYER_SWEEP") then require "test.player_sweep" end
if os.getenv("BRIDGE_AUDIT") then require "test.bridge_audit" end
if os.getenv("HEIST_TEST") then require "test.heist_probe" end
if os.getenv("KAKOLA_TEST") then require "test.kakola_probe" end
if os.getenv("HARBOR_TEST") then require "test.harbor_probe" end
if os.getenv("KAUPPATORI_TEST") then require "test.kauppatori_probe" end
if os.getenv("SUURTORI_TEST") then require "test.suurtori_probe" end
if os.getenv("PED_EVASION_TEST") then require "test.ped_evasion_probe" end
if os.getenv("PED_PASS_TEST") then require "test.ped_pass_probe" end
if os.getenv("STORY_TEST") then require "test.story_probe" end
if os.getenv("SPEED_TEST") then require "test.speed_probe" end
if os.getenv("LAMP_TEST") then require "test.lamp_probe" end
if os.getenv("WANTED_TEST") then require "test.wanted_probe" end
if os.getenv("TOUCH_TEST") then require "test.touch_probe" end
if os.getenv("ROAD_CLEAR_TEST") then require "test.road_clear_probe" end
if os.getenv("RAIL_CROSSING_TEST") then require "test.rail_crossing_probe" end
if os.getenv("OFFROAD_TEST") then require "test.offroad_probe" end
if os.getenv("RACER_TEST") then require "test.racer_probe" end
if os.getenv("HELI_TEST") then require "test.heli_probe" end
if os.getenv("CARKINDS_TEST") then require "test.carkinds_probe" end
if os.getenv("ROADBLOCK_TEST") then require "test.roadblock_probe" end
if os.getenv("CONVOY_TEST") then require "test.convoy_probe" end
if os.getenv("WEATHER_TEST") then require "test.weather_probe" end
if os.getenv("CASHVAN_TEST") then require "test.cashvan_probe" end
if os.getenv("GPS_TEST") then require "test.gps_probe" end
if os.getenv("FARES_TEST") then require "test.fares_probe" end
if os.getenv("WAYPOINT_TEST") then require "test.waypoint_probe" end
if os.getenv("AMBULANCE_TEST") then require "test.ambulance_probe" end
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
