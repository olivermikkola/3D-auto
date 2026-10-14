-- Turku: Finland's oldest city and cultural capital on the Aurajoki river.
-- Co-exists seamlessly alongside Raisio with cross-border highway, arterial road,
-- and river footbridge transitions.
local osm = require "maps.raisio_osm" -- shared roadnet primitives and textures

return {
  name = "Turku",
  id = "turku",

  -- 8 x 8 blocks centered on Kauppatori / Aurakatu / Eerikinkatu
  grid = {nx = 8, nz = 8, bx = 80, bz = 55, avenue = 16, street = 13},

  -- Aurajoki river corridor blocks: cleared of generic buildings so the water,
  -- stone quays, bridge decks, restaurant boats, and Föri ferry are unobstructed.
  water_blocks = {
    {6, 1}, {5, 2}, {4, 3}, {3, 4}, {2, 5}, {1, 6}, {0, 7}
  },

  districts = {
    {"residential", j = {0, 2}, brownstones = 0.6}, -- Portsa wooden district vibe
    {"downtown", j = {3, 5}},                       -- Kauppatori & commercial center
  },

  skyline = {
    peaks = {
      {k = 4, l = 4, rx = 160, rz = 140, weight = 1.0}, -- Kauppatori core
      {k = 6, l = 2, rx = 120, rz = 100, weight = 0.8}, -- Tuomiokirkko hill
    },
    supertall = {24, 38},
  },

  specials = {
    lot = {2, 2},
    plaza = {4, 4},       -- Kauppatori
    stunt = {1, 4},
    carpark = {3, 3},     -- Louhi underground parking entrance
    tower = {6, 2},       -- Tuomiokirkko cathedral spire
    park = {{5, 4}, {6, 3}}, -- Samppalinnanpuisto / Vartiovuori
  },

  billboards = {{3, 3}, {4, 4}},

  -- Named landmarks on the radar minimap
  labels = {
    {x = 0, z = 0, letter = "K", name = "Turun Kauppatori"},
    {x = 320, z = -180, letter = "T", name = "Turun Tuomiokirkko"},
    {x = -1400, z = 850, letter = "C", name = "Turun linna (Castle)"},
    {x = -600, z = 150, letter = "P", name = "Port Arthur (Portsa)"},
    {x = 950, z = -450, letter = "U", name = "Kupittaanpuisto"},
  },

  -- Cross-border transit points connecting Turku directly back into Raisio
  crossings = {
    {pos = {-2200, -800}, yaw = -1.25, target_map = "raisio", name = "Naantalin pikatie (185) -> Raisio", target_pos = {2200, 720}},
    {pos = {-2800, 600}, yaw = 1.99, target_map = "raisio", name = "Raisiontie -> Raisio", target_pos = {2850, -600}},
    {pos = {-2600, 50}, yaw = -1.60, target_map = "raisio", name = "Satakunnantie -> Raisio", target_pos = {2650, -50}},
    {pos = {-920, -820}, yaw = -0.85, target_map = "raisio", name = "Pansiontie -> Raisio / Pansio", target_pos = {920, 810}},
  },

  places = {
    hospital = {node = {3, 5}},       -- TYKS (Turun yliopistollinen keskussairaala)
    taxi_rank = {node = {4, 4}},      -- Kauppatori taxi rank
    police_station = {node = {5, 5}}, -- Eerikinkatu police station
    joyride_garage = {node = {6, 2}},
    race_start = {node = {2, 4}},
    race = {route = {{2, 4}, {2, 1}, {5, 1}, {5, 6}, {2, 6}}},
    bank = {node = {4, 2}},           -- Aurakatu banking quarter
    getaway_start = {node = {3, 3}},
    cargo_pickup = {node = {1, 2}},
    cargo_drop = {node = {6, 5}},
    takedown_start = {node = {4, 2}},
    target_start = {node = {2, 4}},
    smuggle = {route = {{1, 5}, {6, 6}, {6, 2}, {1, 1}}},
    smuggle_drop = {node = {5, 1}},
    stunt = {node = {1, 4}},
    castle = {node = {0, 6}},
    speedboat_dock = {node = {0, 6}},
    archipelago_drop = {node = {0, 1}},
  },

  pickups = {
    {"health", 4, 4, -1, -1},
    {"ammo", 4, 4, 1, -1},
    {"smg", 6, 2, 1, 1}, -- pickup near cathedral
  },

  gunshop = {{4, 5}, {2, 3}},
}
