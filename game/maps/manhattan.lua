-- Manhattan: an island of long blocks between wide avenues, Central Park,
-- and a skyline with two peaks. A map is plain data; lib/city builds it.
-- Coordinates are grid indices: block (i, j) sits between avenues i and
-- i+1 and streets j and j+1; node (k, l) is where avenue k meets street l.
-- North is -z, so j counts down the island from the north tip.
return {
  name = "Manhattan",

  -- 6 x 20 blocks of 84 x 36 m (sidewalks included), avenues 16 m wide,
  -- streets 12 m.
  grid = {nx = 6, nz = 20, bx = 84, bz = 36, avenue = 16, street = 12},

  -- Land in each row of blocks, {first, last}; rows not listed are land
  -- all the way across. Everything else in the grid is river.
  land = {[0] = {2, 5}, [1] = {1, 5}, [18] = {0, 4}, [19] = {1, 3}},

  -- Central Park: blocks i0..i1 x j0..j1. Its inner streets are gone except
  -- the transverse, on street line `transverse`.
  park = {i0 = 2, i1 = 3, j0 = 4, j1 = 10, transverse = 8},

  -- First match wins; blocks matching nothing are downtown. `brownstones`
  -- is the chance a mid-block residential lot is a terrace of row houses.
  districts = {
    {"industrial", i = {0, 0}, j = {13, 16}},                -- the old West Side yards
    {"residential", j = {0, 3}, brownstones = 0.75},         -- Harlem
    {"residential", j = {4, 10}, brownstones = 0.55},        -- the Upper West and East Sides
  },

  -- Where downtown grows tall: each peak is at node coordinates (k, l),
  -- falls to nothing rx meters across and rz along the island, and tops
  -- out at `weight`. Supertalls (floors) appear where it's over half.
  skyline = {
    peaks = {
      {k = 3, l = 12.8, rx = 360, rz = 200, weight = 1},    -- Midtown
      {k = 2.6, l = 18.8, rx = 210, rz = 140, weight = 0.9}, -- the Financial District
    },
    supertall = {30, 50},
  },

  -- Blocks with something special in them, by kind. Each is also a place
  -- of the same name (the block's center).
  specials = {
    lot = {2, 15}, plaza = {3, 16}, stunt = {1, 16}, carpark = {1, 15}, tower = {4, 1}, empire = {3, 13},
    square = {2, 17},                          -- Washington Square
    park = {{4, 17}, {1, 19}},                 -- Union Square, Battery Park
  },
  billboards = {{2, 11}},                      -- Times Square

  -- Named places for missions and systems. A node is an intersection; a
  -- block with `side` (n/s/e/w) is the middle of that side, `out` meters
  -- past the block's edge (negative is onto its sidewalk) and `along` it.
  places = {
    hospital = {block = {3, 15}, side = "w", out = -1.5},
    taxi_rank = {block = {2, 15}, side = "s", out = 2, along = 10},
    joyride_garage = {node = {5, 12}},          -- across Midtown, on the East Side
    race_start = {node = {2, 14}},
    -- A lap of the blocks around the lot: up the West Side, across, down the East Side.
    race = {route = {{1, 14}, {1, 17}, {4, 17}, {4, 14}, {3, 14}, {3, 16}}},
    bank = {node = {2, 19}},                    -- down in the Financial District
    getaway_start = {node = {4, 15}},
  },

  -- Pickups on the avenue sidewalks: kind, block, and which corner (signs).
  pickups = {
    {"health", 2, 15, -1, -1}, {"ammo", 2, 15, 1, -1}, {"health", 3, 16, 1, 1}, {"ammo", 1, 16, -1, 1},
    {"smg", 4, 12, 1, 1}, {"health", 1, 6, -1, -1}, {"ammo", 4, 18, 1, 1},
  },
  -- The gun shop goes on the south face of the first of these that's an
  -- ordinary downtown block.
  gunshop = {{2, 14}, {3, 14}, {3, 15}, {1, 14}},
}
