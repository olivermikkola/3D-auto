-- Turku, Finland, at real size: Kauppatori, Aurajoki, Tuomiokirkko, Turun linna,
-- Kupittaa, Port of Turku, and Yliopistonmäki.
-- The roads, buildings, water, parks and forests come from OpenStreetMap
-- (maps/turku_osm.lua, made by tools/osm_import.py; ODbL).
-- The terrain comes from Maanmittauslaitos 2m LiDAR GeoTIFFs (N2000 heightfield).
local osm = require "maps.turku_osm"

return {
  name = "Turku",
  id = "turku",
  size = {osm.bounds[3] - osm.bounds[1], osm.bounds[4] - osm.bounds[2]},
  center = {(osm.bounds[1] + osm.bounds[3]) / 2, (osm.bounds[2] + osm.bounds[4]) / 2},
  junctions = osm.junctions,
  junction_order = {osm.first},
  roads = osm.roads,
  paved = osm.paved,
  footprints = osm.footprints,
  cover = osm.cover,
  terrain = osm.terrain, -- real 2m LiDAR heights (MML), roads graded in
  pitches = osm.pitches,
  footbridges = osm.footbridges,
  cranes = osm.cranes,
  piers = osm.piers,
  fog = {180, 800},
  trees = 8000,
  lamp_every = 50,

  -- Named landmarks on the radar minimap
  labels = {
    {x = 0, z = 0, letter = "K", name = "Turun Kauppatori"},
    {x = 320, z = -180, letter = "T", name = "Turun Tuomiokirkko"},
    {x = -2600, z = 1750, letter = "C", name = "Turun linna (Castle)"},
    {x = -1400, z = 200, letter = "P", name = "Port Arthur (Portsa)"},
    {x = 1200, z = 500, letter = "U", name = "Kupittaanpuisto"},
    {x = -2900, z = 1900, letter = "S", name = "Turun Satama (Port)"},
    {x = 850, z = -450, letter = "Y", name = "Yliopistonmäki"},
  },

  -- Cross-border transit points connecting Turku directly into Raisio
  crossings = {
    {pos = {-3150, -900}, yaw = -1.25, target_map = "raisio", name = "Naantalin pikatie (185) -> Raisio", target_pos = {2200, 720}},
    {pos = {-2800, 600}, yaw = 1.99, target_map = "raisio", name = "Raisiontie -> Raisio", target_pos = {2850, -600}},
    {pos = {-2600, 50}, yaw = -1.60, target_map = "raisio", name = "Satakunnantie -> Raisio", target_pos = {2650, -50}},
    {pos = {-920, -820}, yaw = -0.85, target_map = "raisio", name = "Pansiontie -> Raisio / Pansio", target_pos = {920, 810}},
  },

  specials = {
    lot = {-300, -20},     -- starting lot in Puolalanpuisto park clear of roads
    plaza = {1000, 640},   -- Kupittaanpuisto open plaza
    stunt = {1200, 500},   -- Kupittaanpuisto sports grounds
  },

  places = {
    hospital = {at = {880, 240}},                                   -- TYKS (Kiinamyllynkatu)
    taxi_rank = {at = {10, -10}},                                   -- Kauppatori taxi rank
    police_station = {at = {-220, 110}},                            -- Turun pääpoliisiasema (Eerikinkatu)
    joyride_garage = {junction = "Linnankatu / Sairashuoneenkatu"},
    race_start = {junction = "Aurakatu / Eerikinkatu"},
    race = {route = {
      "Aurakatu / Eerikinkatu", "Aninkaistenkatu / Eerikinkatu",
      "Aninkaistenkatu / Linnankatu", "Aurakatu / Linnankatu",
      "Aurakatu / Eerikinkatu",
    }},
    bank = {junction = "Aurakatu / Linnankatu"},                    -- Aurakatu banking quarter
    getaway_start = {junction = "Aurakatu / Eerikinkatu"},
    cargo_pickup = {junction = "Linnankatu / Satamakatu"},          -- Turku harbor dock
    cargo_drop = {junction = "Aninkaistenkatu / Linnankatu"},
    takedown_start = {junction = "Aninkaistenkatu / Eerikinkatu"},
    target_start = {junction = "Aurakatu / Linnankatu"},
    smuggle = {route = {
      "Linnankatu / Satamakatu", "Linnankatu / Sairashuoneenkatu",
      "Aurakatu / Linnankatu", "Aninkaistenkatu / Linnankatu",
    }},
    smuggle_drop = {junction = "Aninkaistenkatu / Eerikinkatu"},
    stunt = {junction = "Aninkaistenkatu / Eerikinkatu"},
    castle = {junction = "Linnankatu / Satamakatu"},
    speedboat_dock = {junction = "Aurakatu / Auransilta"},
    archipelago_drop = {junction = "Linnankatu / Satamakatu"},
  },

  pickups = {
    {"health", 50, -30},
    {"ammo", -40, 20},
    {"smg", 310, -170}, -- near cathedral
    {"health", -2550, 1720}, -- near castle
    {"ammo", 1200, 480}, -- Kupittaa
  },

  gunshop = {120, -80},
}
