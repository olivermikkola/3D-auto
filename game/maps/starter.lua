-- Starter Town: the smallest map that runs the whole game, meant to be
-- copied. Rename it after your town, change the grid and the places, and
-- play it with MAP=<file name>. Every field is explained in the README
-- ("Make your own city"). Unlike the other maps here, this file is MIT
-- licensed like the code: start yours from it however you like.
return {
  name = "Starter Town",

  -- 5 x 7 blocks of 64 x 40 m (sidewalks included), avenues 14 m wide,
  -- streets 12 m. Blocks are (i, j); intersections are nodes (k, l).
  grid = {nx = 5, nz = 7, bx = 64, bz = 40, avenue = 14, street = 12},

  -- No `land` table: the town is land all the way across, ringed by water.
  -- No `park` table: no big park cutting the streets.

  -- First match wins; everything else is downtown.
  districts = {
    {"residential", j = {5, 6}, brownstones = 0.5},
  },

  skyline = {
    peaks = {{k = 2, l = 2, rx = 120, rz = 100, weight = 0.9}},
    supertall = {22, 32},
  },

  -- Blocks with something in them. The game needs lot, plaza, stunt,
  -- carpark and tower; parks are optional.
  specials = {
    lot = {1, 2}, plaza = {2, 2}, stunt = {0, 3}, carpark = {2, 1}, tower = {3, 0},
    park = {{1, 4}},
  },
  billboards = {{1, 1}},

  -- Named places. Missions and systems only ever ask for these by name; a
  -- mission whose places a map leaves out just isn't offered on it.
  places = {
    hospital = {block = {2, 3}, side = "w", out = -1.5},
    taxi_rank = {block = {1, 2}, side = "s", out = 2, along = 8},
    joyride_garage = {node = {4, 0}},
    race_start = {node = {1, 3}},
    race = {route = {{0, 3}, {0, 0}, {4, 0}, {4, 5}, {2, 5}, {2, 3}}},
    bank = {node = {4, 4}},
    getaway_start = {node = {0, 1}},
    cargo_pickup = {node = {4, 2}},
    cargo_drop = {node = {0, 5}},
    takedown_start = {node = {3, 3}},
    target_start = {node = {1, 0}},
    smuggle = {route = {{0, 4}, {4, 5}, {4, 1}, {1, 0}}},
    smuggle_drop = {node = {3, 2}},
  },

  -- Pickups: kind, block, and which corner of it (signs of x and z).
  pickups = {{"health", 1, 2, -1, -1}, {"ammo", 1, 2, 1, -1}, {"smg", 3, 3, 1, 1}},
  -- The gun shop goes on the first of these that's an ordinary block.
  gunshop = {{3, 2}, {0, 1}},
}
