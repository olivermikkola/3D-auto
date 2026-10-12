-- © 2026 Oliver Mikkola. CC BY-NC 4.0, not MIT: see LICENSE in this folder.
-- Raisio, Finland: a small town drawn as roads instead of a grid, from the
-- map. Raisiontie runs north-west out of the center, E18 crosses it west to
-- east, E8 sweeps north-south past the interchange, and the Ruskonjoki
-- winds down the east side. Compressed to about half real size.
--
-- Coordinates are meters, x east and z south (north is -z), with the
-- central junction at 0, 0. A road is a list of points: names are
-- junctions (the only places roads meet), {x, z} pairs are bends. Kinds:
-- "highway" (no pavement, nothing built along it), "main" and "street".
return {
  name = "Raisio",
  size = {1500, 1300},

  junctions = {
    center = {0, 0},
    -- Raisiontie, north
    kt0 = {-48, -50}, hulv = {-140, -140}, innan = {-250, -235}, keila = {-410, -400}, raisio_n = {-480, -600},
    -- Kerttula
    torni = {35, -48}, keon_n = {72, -55}, hv_torni = {42, -195}, venheen = {115, -200}, kerttula = {150, -300},
    venheen_n = {200, -470},
    -- E18 west and the campus
    soli = {-85, 22}, nest = {-250, 70}, e18_op = {-322, 87}, juhan_w = {-520, 115}, e18_w = {-740, 100},
    ulpukka = {-320, 125}, ulpukka_end = {-400, 125}, ra_s = {-320, 200}, ns_mid = {-250, 200},
    kirkko_w = {-250, 232}, op_s = {-320, 255}, ns_n = {-268, -100}, ns_s = {-240, 450},
    kk_mid = {-150, 215}, sl = {-140, 400}, sl_end = {-200, 560}, west_n = {-380, -260},
    -- Raisiontie, south
    rs_kirk = {-15, 200}, rs_mid = {-22, 400}, rs_s = {-20, 600}, cemetery = {55, 180},
    -- E18 east, E8, Mylly
    keon_s = {72, 3}, e8x = {130, 8}, ind = {300, 55}, ind_n = {360, -150}, mylly = {470, 140}, mall = {470, 185},
    e18_e = {740, 245}, e8_n = {280, -620}, e8_s = {50, 640},
  },
  junction_order = {"center"},
  roundabouts = {ulpukka = 7, ra_s = 7},

  roads = {
    {name = "Raisiontie", kind = "main", "raisio_n", {-450, -500}, "keila", {-330, -310}, "innan", {-190, -185}, "hulv",
     {-95, -95}, "kt0", "center", {-5, 100}, "rs_kirk", {-25, 300}, "rs_mid", "rs_s"},
    {name = "E18", kind = "highway", "e18_w", {-640, 110}, "juhan_w", {-430, 108}, "e18_op", "nest", {-160, 45}, "soli",
     {-40, 10}, "center", {40, 1}, "keon_s", "e8x", {234, 30}, "ind", {377, 85}, "mylly", {600, 195}, "e18_e"},
    {name = "E8", kind = "highway", "e8_n", {255, -470}, {230, -300}, {160, -130}, "e8x", {104, 133}, {75, 289}, {60, 450}, "e8_s"},
    {name = "Kerttulantie", kind = "main", "kt0", {-5, -52}, "torni", "keon_n", {95, -120}, "venheen", {135, -250}, "kerttula"},
    {name = "Tornikatu", "torni", {38, -110}, "hv_torni"},
    {name = "Keonkatu", "keon_n", {74, -25}, "keon_s"},
    {name = "Hulvelankatu", "hulv", {-70, -172}, "hv_torni", "venheen"},
    {name = "Innanmaankatu", "innan", {-180, -285}, {-100, -315}, {0, -320}, {80, -312}, "kerttula"},
    {name = "Venheenkatu", "kerttula", {175, -380}, "venheen_n"},
    {name = "Soliniuksenkuja", "soli", {-112, -40}, {-135, -95}, "hulv"},
    {name = "Nesteentie", kind = "main", "ns_n", {-262, -10}, "nest", {-252, 130}, "ns_mid", "kirkko_w", {-246, 330}, "ns_s"},
    {name = "Opinpolku", "e18_op", "ulpukka", "ra_s", "op_s"},
    {name = "to Ulpukka", "ulpukka", "ulpukka_end"},
    {name = "campus link", "ra_s", "ns_mid"},
    {name = "Juhaninkuja", "ra_s", {-400, 180}, {-470, 150}, "juhan_w"},
    {name = "Kirkkotie", kind = "main", "op_s", "kirkko_w", "kk_mid", "rs_kirk", {20, 195}, "cemetery"},
    {name = "south loop", "kk_mid", {-145, 320}, "sl", "rs_mid"},
    {name = "south lane", "sl", {-180, 480}, "sl_end"},
    {name = "Nesteentie south link", "ns_s", "sl"},
    {name = "west lane", "ns_n", {-330, -180}, "west_n", "keila"},
    {name = "to the yards", "ind", {320, -40}, "ind_n"},
    {name = "to Mylly", "mylly", "mall"},
  },

  rivers = {
    {width = 12, {740, -210}, {480, -110}, {380, -40}, {290, 40}, {210, 120}, {150, 200}, {125, 320}, {80, 450}, {40, 560}, {-20, 650}},
  },

  -- Districts, first match wins; elsewhere is detached houses. "open" and
  -- "park" keep the auto-builder out (hand-placed buildings go there).
  default_district = "suburb",
  trees = 2200,
  areas = {
    {"open", x = -340, z = 180, r = 75},     -- the campus
    {"open", x = 470, z = 225, r = 75},      -- Mylly
    {"park", x = 70, z = 255, r = 40},       -- the cemetery
    {"downtown", x = -10, z = -30, r = 150},
    {"industrial", x = 340, z = -90, r = 130},
    {"apartments", x = -170, z = -230, r = 150},
    {"apartments", x = -120, z = 330, r = 110},
  },

  -- The game's features, each on a 40 x 40 m pad clear of the roads.
  specials = {
    lot = {-15, -95}, plaza = {-75, 120}, stunt = {50, -255}, carpark = {560, 250}, tower = {-430, -250},
  },

  buildings = {
    {name = "Raision kaupungintalo", x = -160, z = 110, w = 50, d = 30, floors = 3, color = {0.92, 0.9, 0.86}},
    {name = "Raision kaupunginkirjasto", x = -285, z = 165, w = 30, d = 22, floors = 2, style = "glass", letter = "K"},
    {name = "LähiTapiola Areena", x = -372, z = 160, w = 34, d = 24, floors = 3, color = {0.75, 0.78, 0.8}},
    {name = "Vaisaaren koulu", x = -395, z = 222, w = 40, d = 20, floors = 2, color = {0.85, 0.6, 0.45}},
    {name = "Raision lukio", x = -370, z = 290, w = 45, d = 25, floors = 3, color = {0.82, 0.7, 0.55}},
    {name = "Uintikeskus Ulpukka", x = -430, z = 135, w = 26, d = 20, floors = 2, color = {0.6, 0.75, 0.85}},
    {name = "Raisio center shops", x = -78, z = -25, w = 18, d = 24, floors = 2, color = {0.65, 0.55, 0.75}},
    {name = "Raisiontori", x = 5, z = -150, w = 40, d = 22, floors = 2, color = {0.6, 0.5, 0.72}},
    {name = "Kauppakeskus Mylly", x = 470, z = 230, w = 120, d = 70, floors = 2, color = {0.85, 0.78, 0.6}, letter = "M"},
    {name = "Keilailukeskus", x = -470, z = -390, w = 36, d = 24, floors = 2, color = {0.8, 0.4, 0.55}},
    {name = "Raision kirkko", x = 60, z = 230, w = 22, d = 14, floors = 3, color = {0.95, 0.95, 0.92}},
  },

  places = {
    hospital = {at = {-242, 140}},
    taxi_rank = {at = {10, -60}},
    joyride_garage = {junction = "kerttula"},
    race_start = {junction = "keon_s"},
    race = {route = {"keon_n", "venheen", "hv_torni", "hulv", "soli", "nest", "kirkko_w", "rs_kirk", "center"}},
    bank = {junction = "soli"},
    getaway_start = {junction = "torni"},
    cargo_pickup = {junction = "ind"},
    cargo_drop = {junction = "juhan_w"},
    takedown_start = {junction = "ra_s"},
    target_start = {junction = "keila"},
    smuggle = {route = {"kerttula", "ns_n", "cemetery", "mall"}},
    smuggle_drop = {junction = "nest"},
  },

  pickups = {
    {"health", -20, -65}, {"ammo", 15, -62}, {"health", -242, 180}, {"smg", 140, -150},
    {"health", 482, 160}, {"ammo", -400, -380}, {"health", -30, 300},
  },
  -- The gun shop's door: on its own small block, facing south onto E18.
  gunshop = {30, -20},
}
