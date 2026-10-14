-- © 2026 Oliver Mikkola. CC BY-NC 4.0, not MIT: see LICENSE in this folder.
-- Raisio, Finland, at real size: the center, Mylly, and Nesteentie down to
-- the harbor. The roads, buildings, water and woods come from OpenStreetMap
-- (maps/raisio_osm.lua, made by tools/osm_import.py; ODbL, see LICENSE).
-- This file adds the game: where things are and what happens there.
--
-- Coordinates are meters, x east and z south (north is -z), from the middle
-- of the surveyed area. Junctions are named after the streets that meet
-- there, "Nesteentie / Raisiontie"; where the same streets meet more than
-- once the later ones get " 2", " 3".
local osm = require "maps.raisio_osm"

return {
  name = "Raisio",
  size = {osm.bounds[3] - osm.bounds[1], osm.bounds[4] - osm.bounds[2]},
  center = {(osm.bounds[1] + osm.bounds[3]) / 2, (osm.bounds[2] + osm.bounds[4]) / 2}, -- 0, 0 isn't the middle
  junctions = osm.junctions,
  junction_order = {osm.first},
  roads = osm.roads,
  paved = osm.paved,
  footprints = osm.footprints,
  cover = osm.cover,
  terrain = osm.terrain, -- real heights (Maanmittauslaitos), roads graded in
  pitches = osm.pitches,
  footbridges = osm.footbridges,
  wooden_footbridges = {
    {
      name = "Punttamäenpolun silta",
      width = 2.8,
      points = {{2472.1, 102.6}, {2443.8, 81.1}},
    },
  },
  military = {
    {
      name = "Pansion varuskunta",
      stars = 3,
      polygon = require("maps.raisio_military_poly"),
      gates = {
        {pos = {-348.4, 2583.1}, yaw = 1.85, width = 8},
      },
    },
  },
  border_crossings = {
    {pos = {2226.5, 744.8}, yaw = 1.25, name = "Naantalin pikatie (185)", kind = "highway"},
    {pos = {2893.6, -614.7}, yaw = -1.99, name = "Raisiontie", kind = "main"},
    {pos = {2680.3, -61.4}, yaw = 1.60, name = "Satakunnantie", kind = "main"},
    {pos = {3782.8, -1830.7}, yaw = 2.03, name = "Kuninkojantie", kind = "main"},
    {pos = {936.0, 828.3}, yaw = 0.85, name = "Pansiontie", kind = "main"},
    {pos = {1340.4, 829.3}, yaw = 0.95, name = "Artukaistentie", kind = "street"},
  },
  -- Raised traffic islands (e.g. junction splitters, pedestrian refuges)
  islands = {
    {855, -1725, 2.8}, -- Raisiontori square / Raisiontie splitter
    {940, -1720, 2.5},
    {1250, -1780, 2.6}, -- near police station
    {2750, -2180, 3.2}, -- Mylly entrance island
    {2680, -2250, 3.0},
  },
  -- The map data's towers, and the police station's radio mast behind it.
  towers = (function()
    local t = {{1295, -1825, 45, "lattice"}, {-1000, -1590, 70, "chimney"}} -- and Raisio's factory chimney
    for _, v in ipairs(osm.towers) do t[#t + 1] = v end
    return t
  end)(),
  -- The parts of town the HUD names: the map data's suburbs and
  -- neighbourhoods (Turku's too, past the bay; the names Google Maps shows),
  -- the center, and Mylly.
  areas = (function()
    local t, seen = {{"Mylly", 2700, -2200}}, {}
    for _, a in ipairs(osm.areas) do
      if a[4] == "town" then t[#t + 1] = {"Raision keskusta", a[2], a[3]}
      elseif not seen[a[1]] then t[#t + 1], seen[a[1]] = a, true end
    end
    return t
  end)(),
  -- Roads the map data knows only by number.
  street_names = {["185"] = "Naantalin pikatie"},
  -- Buildings that look like themselves: footprints within r of {x, z, r}
  -- get the look (a wall color, brick or glass, floors; or an air dome h
  -- meters high).
  looks = {
    {772, -1125, 50, {color = {0.42, 0.52, 0.64}, floors = 3}},                  -- Raision kirjasto: blue-grey panels
    {625, -806, 50, {style = "glass", color = {0.85, 0.92, 0.97}, floors = 3}},  -- Uintikeskus Ulpukka
    {826, -968, 40, {dome = 18}},                                                -- LähiTapiola Areena, the air dome
    {945, -990, 60, {color = {0.6, 0.53, 0.47}, floors = 3}},                    -- Tiedonpuiston koulu, grey-brown brick
    {790, -880, 70, {color = {0.66, 0.34, 0.26}, floors = 2}},                   -- Raseko, Eeronkuja 3: red brick
    {665, -953, 30, {color = {0.86, 0.77, 0.6}, floors = 3}},                    -- Raseko, Eeronkuja 4: the new tan block
    {537, -960, 40, {color = {0.66, 0.34, 0.26}, floors = 3}},                   -- Raseko, Purokatu 1
    {1110, -1160, 60, {color = {0.86, 0.85, 0.8}, floors = 2}},                  -- Raision lukio
    -- Raisio's factory (Raisio Oyj): the silo block, smaller silos, tall
    -- pale mill buildings and yellow brick ones.
    {-1045, -1565, 30, {height = 46, color = {0.9, 0.9, 0.88}}},
    {-1041, -1510, 15, {height = 32, color = {0.88, 0.88, 0.86}}},
    {-852, -1453, 16, {height = 26, color = {0.86, 0.86, 0.84}}},
    {-1141, -1520, 45, {color = {0.88, 0.86, 0.78}, floors = 7}},
    {-1050, -1440, 40, {color = {0.86, 0.84, 0.76}, floors = 6}},
    {-980, -1713, 70, {color = {0.86, 0.84, 0.78}, floors = 4}},
    {-960, -1336, 50, {color = {0.95, 0.78, 0.4}, floors = 3}},
    -- The centre. Raisiontie's north side: flats of the 2010s with glass
    -- balconies and orange-red panels. Raision Lasikuutio (Mehiläinen):
    -- the dark glass cube at the square's east end. Tasalanaukio 9
    -- (Tasalanpuisto, 1986) and 7 (Tasalanhovi, 1984): pale tiled blocks.
    -- Sofram's grey building, Tasalanaukio 12. And the white 1980s shops
    -- and offices of Tasala round the square (S-market, the pharmacy...).
    {800.2, -1779.5, 6, {style = "balconies", color = {1, 1, 1}, floors = 5}},
    {850.9, -1779.5, 6, {style = "balconies", color = {1, 1, 1}, floors = 5}},
    {917, -1779.5, 6, {style = "balconies", color = {1, 1, 1}, floors = 5}},
    {956.8, -1725.3, 8, {style = "glass", color = {0.6, 0.64, 0.7}, floors = 3}},
    {733, -1581, 14, {color = {0.88, 0.83, 0.72}, floors = 4}},
    {762, -1602, 26, {color = {0.88, 0.83, 0.72}, floors = 5}},
    {713, -1630.7, 8, {color = {0.6, 0.6, 0.58}, floors = 2}},
    {850, -1650, 75, {color = {0.93, 0.93, 0.91}}},
    -- Raisiontori: Tokmanni, white.
    {915, -1895, 60, {color = {0.93, 0.93, 0.91}, floors = 2}},
  },
  -- The lanterns strung across Raisiontie through the center.
  string_lights = {{610, -1755.5, 940, -1755.5, 13}},
  cranes = osm.cranes,
  piers = osm.piers,
  fog = {170, 700}, -- see across the bay to the shipyard
  trees = 6000,
  lamp_every = 60,

  -- The game's features, each on a 40 x 40 m pad clear of the roads.
  specials = {
    lot = {905, -1586},     -- behind the S-market, in the center
    plaza = {671, -1513},
    stunt = {-500, 0},      -- out in the fields off Nesteentie
  },

  -- Kerttula's running track, west of the football pitch (the map data
  -- has only the pitch): {x, z, yaw of the straights}.
  tracks = {{482, -2382, 1.847}},

  -- Mylly: park on the roof, up a ramp at either end.
  roof_parking = {
    {x = 2790, z = -2200, r = 230, height = 9, ramps = {{2574.4, -2196.9, 1.783}, {2999.7, -2255.7, -1.359}}},
  },

  labels = {
    {x = 2700, z = -2200, letter = "M", name = "Kauppakeskus Mylly"},
    {x = 850, z = -1700, letter = "R", name = "Raisiontori"},
    {x = -2760, z = 1820, letter = "S", name = "the harbor"},
    {x = 1260, z = -1805, letter = "P", name = "Raision poliisiasema"},
    {x = 1077, z = -1144, letter = "L", name = "Raision lukio"},
  },

  places = {
    hospital = {at = {945, -1741}},  -- Mehiläinen, by Raisiontori
    police_station = {at = {1233, -1796}}, -- Raision poliisiasema: busted, you walk out here
    taxi_rank = {at = {870, -1700}},
    joyride_garage = {junction = "Kuloistentie / Sarkamaantie"}, -- the car dealers past Mylly
    race_start = {junction = "Peltopohjankatu / Sarkamaantie"},
    race = {route = {"Kytökuja / Sarkamaantie", "Pökkälänkatu / Tuulenkatu", "Kerttulantie / Raisiontie",
                     "Nesteentie / Raisiontie", "Hurstikatu / Hurstipolku", "Liponkuja / Ounelantie",
                     "Peltopohjankatu / Sarkamaantie"}},
    bank = {junction = "Raisiontie / Tornikatu"},       -- Osuuspankki
    getaway_start = {junction = "Nesteentie / Raisiontie"},
    cargo_pickup = {junction = "Nesteentie / Poppelikuja"}, -- the harbor end of Nesteentie
    cargo_drop = {junction = "Pläkkisepänkatu / Salvumiehenkatu"},
    takedown_start = {junction = "Hurstikatu / Hurstipolku"},
    target_start = {junction = "Raisiontie / Tahviontie"},
    smuggle = {route = {"Kytökuja / Sarkamaantie", "Krookilantie / Mäntykankareenkatu", "Hahdenniementie / Nesteentie",
                        "Liponkuja / Ounelantie"}},
    smuggle_drop = {junction = "Raisiontie / Teräskatu"},
    heist_start = {at = {-320, 2560}},
    heist_pasi = {at = {-880, 2820}},
    heist_drop = {junction = "Kuloistentie / Sarkamaantie"},
  },

  pickups = {
    {"health", 950, -1650}, {"ammo", 2705, -2264}, {"health", -2700, 1800}, {"smg", 5, -786},
    {"health", -1300, -1900}, {"ammo", 1500, -2400}, {"health", 2200, 400},
  },
  -- The gun shop's door: on its own small block, facing south.
  gunshop = {1000, -1800},
}
