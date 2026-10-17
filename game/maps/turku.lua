-- Turku, Finland, at real size: Kauppatori, Aurajoki, Tuomiokirkko, Turun linna,
-- Kupittaa, Port of Turku, and Yliopistonmäki.
-- The roads, buildings, water, parks and forests come from OpenStreetMap
-- (maps/turku_osm.lua, made by tools/osm_import.py; ODbL).
-- The terrain comes from Maanmittauslaitos 2m LiDAR GeoTIFFs (N2000 heightfield).
local osm = require "maps.turku_osm"

-- Filter out generic procedural boxes at landmark sites replaced by custom high-fidelity prefabs
local filtered_footprints = {}
for _, f in ipairs(osm.footprints or {}) do
  local x, z = f[1], f[2]
  local d_tuomio = (x - 415)^2 + (z - (-100))^2
  local in_suurtori_plaza = (x > 245 and x < 325 and z > 70 and z < 125)
  local in_linna = (x > -2340 and x < -2185 and z > 1745 and z < 1825) -- Turun linna (systems/harbor.lua)
  if d_tuomio > 55*55 and not in_suurtori_plaza and not in_linna then
    filtered_footprints[#filtered_footprints + 1] = f
  end
end

return {
  name = "Turku",
  id = "turku",
  size = {osm.bounds[3] - osm.bounds[1], osm.bounds[4] - osm.bounds[2]},
  center = {(osm.bounds[1] + osm.bounds[3]) / 2, (osm.bounds[2] + osm.bounds[4]) / 2},
  junctions = osm.junctions,
  junction_order = {osm.first},
  roads = osm.roads,
  paved = osm.paved,
  footprints = filtered_footprints,
  cover = osm.cover,
  terrain = osm.terrain, -- real 2m LiDAR heights (MML), roads graded in
  pitches = osm.pitches,
  pools = osm.pools,
  footbridges = osm.footbridges,
  railways = osm.railways,
  outlines = osm.outlines,
  platforms = osm.platforms,
  cranes = osm.cranes,
  piers = osm.piers,
  fog = {180, 800},
  trees = 8000,
  lamp_every = 50,

  -- Named landmarks on the radar minimap
  labels = {
    {x = -175, z = -15, letter = "K", name = "Turun Kauppatori"},
    {x = 385, z = -100, letter = "T", name = "Turun Tuomiokirkko"},
    {x = 270, z = 95, letter = "V", name = "Vanha Suurtori & Brinkkala"},
    {x = 1222, z = -1865, letter = "O", name = "Koroistenniemi (Historic Cross)"},
    {x = -1450, z = 950, letter = "F", name = "Kakolanmäki & Funikulaari"},
    {x = -2265, z = 1785, letter = "C", name = "Turun linna (Castle)"},
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

  -- The parts of town the HUD and the radio name: the map data's suburbs,
  -- neighbourhoods and localities (not the city itself, single blocks or farms).
  areas = (function()
    local t, seen = {}, {}
    for _, a in ipairs(osm.areas) do
      local kind = a[4]
      if (kind == "suburb" or kind == "neighbourhood" or kind == "locality") and not seen[a[1]] then
        t[#t + 1], seen[a[1]] = a, true
      end
    end
    return t
  end)(),

  specials = {
    lot = {-300, -20},     -- starting lot in Puolalanpuisto park clear of roads
    plaza = {1000, 640},   -- Kupittaanpuisto open plaza
    stunt = {1480, 600},   -- Kupittaa sports park, off Lemminkäisenkatu: flat, with pavements near for pedestrians
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
    getaway_start = {junction = "Brahenkatu / Eerikinkatu"},
    cargo_pickup = {junction = "Linnankatu / Satamakatu"},          -- Turku harbor dock
    cargo_drop = {junction = "Aninkaistenkatu / Linnankatu"},
    takedown_start = {junction = "Aninkaistenkatu / Eerikinkatu"},
    target_start = {junction = "Aurakatu / Linnankatu"},
    smuggle = {route = {
      "Linnankatu / Satamakatu", "Linnankatu / Sairashuoneenkatu",
      "Aurakatu / Linnankatu", "Aninkaistenkatu / Linnankatu",
    }},
    smuggle_drop = {junction = "Eerikinkatu / Kristiinankatu"},
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

  -- Architectural styles and visual landmarks mapped to real OSM footprints
  looks = {
    -- Turun tuomiokirkko (National Cathedral): red brick nave and copper details
    {380, -90, 60, {color = {0.65, 0.28, 0.20}, floors = 8}},
    -- Mikaelinkirkko (St. Michael's Church, Portsa): red brick Gothic revival
    {-1185, 218, 50, {color = {0.70, 0.25, 0.18}, floors = 7}},
    -- Turun taidemuseo (Puolalanmäki): granite palace
    {-640, -150, 45, {color = {0.75, 0.73, 0.70}, floors = 4}},
    -- Vicklund & Hamburger Börs (Kauppatori commercial core)
    {-160, 70, 45, {style = "glass", color = {0.88, 0.90, 0.92}, floors = 5}},
    {-60, 20, 45, {style = "balconies", color = {0.95, 0.92, 0.88}, floors = 6}},
    -- Turun Kauppahalli: historic red brick market hall
    {-80, 100, 40, {color = {0.68, 0.30, 0.22}, floors = 2}},
    -- Kakolan Graniittilinna: central granite prison fortress & watchtowers
    {-1440, 950, 120, {style = "granite", color = {0.66, 0.65, 0.63}, floors = 5}},
    -- Kakolan Länsiselli & Tiililinna: institutional red-brick cellblock
    {-1535, 985, 90, {color = {0.58, 0.24, 0.18}, floors = 6}},
    -- Hotel Kakola & brewery courtyard (former prison warden quarters)
    {-1300, 820, 80, {style = "granite", color = {0.62, 0.61, 0.60}, floors = 4}},
    -- Portsa (Port Arthur) wooden quarter: traditional 2-storey wooden workers' houses
    {-1360, 640, 130, {style = "wooden", color = {0.88, 0.74, 0.32}, floors = 2}},
    {-1440, 680, 120, {style = "wooden", color = {0.68, 0.25, 0.20}, floors = 2}},
    {-1490, 640, 110, {style = "wooden", color = {0.55, 0.65, 0.52}, floors = 2}},
    -- Aboa Vetus Ars Nova: riverside museum mansion
    {138, 254, 40, {color = {0.85, 0.82, 0.75}, floors = 3}},
  },

  gunshop = {120, -80},
}
