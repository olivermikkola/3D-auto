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
  junctions = osm.junctions,
  junction_order = {osm.first},
  roads = osm.roads,
  paved = osm.paved,
  footprints = osm.footprints,
  cover = osm.cover,
  pitches = osm.pitches,
  footbridges = osm.footbridges,
  -- The map data's towers, and the police station's radio mast behind it.
  towers = (function()
    local t = {{1295, -1825, 45, "lattice"}}
    for _, v in ipairs(osm.towers) do t[#t + 1] = v end
    return t
  end)(),
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
  },

  pickups = {
    {"health", 950, -1650}, {"ammo", 2705, -2264}, {"health", -2700, 1800}, {"smg", 5, -786},
    {"health", -1300, -1900}, {"ammo", 1500, -2400}, {"health", 2200, 400},
  },
  -- The gun shop's door: on its own small block, facing south.
  gunshop = {1000, -1800},
}
