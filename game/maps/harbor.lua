-- © 2026 Oliver Mikkola. CC BY-NC 4.0, not MIT: see LICENSE in this folder.
-- Harbor Town: a small port on a squarer grid, with a bay cut into the
-- south-east corner, docks along the water, one modest downtown and no big
-- park. See maps/manhattan.lua for what each field means.
return {
  name = "Harbor Town",

  grid = {nx = 5, nz = 7, bx = 64, bz = 40, avenue = 14, street = 12},

  -- The bay takes the south-east corner.
  land = {[5] = {0, 3}, [6] = {0, 2}},

  districts = {
    {"industrial", i = {3, 4}, j = {3, 4}},                  -- the docks, on the bay
    {"industrial", i = {3, 3}, j = {5, 5}},
    {"residential", j = {0, 1}, brownstones = 0.7},          -- the old town up the hill
    {"residential", i = {0, 0}, brownstones = 0.4},
  },

  skyline = {
    peaks = {{k = 2, l = 3, rx = 160, rz = 120, weight = 0.8}},
    supertall = {18, 28},
  },

  specials = {
    lot = {2, 4}, plaza = {1, 4}, stunt = {1, 5}, carpark = {2, 2}, tower = {4, 0},
    park = {{1, 2}, {2, 6}},
  },
  billboards = {{2, 3}},

  places = {
    hospital = {block = {1, 3}, side = "e", out = -1.5},
    taxi_rank = {block = {2, 4}, side = "s", out = 2, along = 8},
    joyride_garage = {node = {0, 0}},
    race_start = {node = {2, 5}},
    race = {route = {{0, 5}, {0, 1}, {3, 1}, {3, 3}, {5, 3}, {5, 0}, {2, 0}, {2, 4}}},
    bank = {node = {4, 1}},
    getaway_start = {node = {1, 6}},
    cargo_pickup = {node = {4, 4}},             -- the docks
    cargo_drop = {node = {0, 1}},               -- the old town
    takedown_start = {node = {1, 3}},
    target_start = {node = {4, 0}},
    smuggle = {route = {{1, 0}, {5, 1}, {3, 5}, {0, 6}}},
    smuggle_drop = {node = {2, 1}},
  },

  pickups = {{"health", 2, 4, -1, -1}, {"ammo", 2, 4, 1, -1}, {"smg", 3, 1, 1, 1}, {"health", 0, 6, 1, 1}},
  gunshop = {{2, 3}, {1, 1}},
}
