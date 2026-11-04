-- Turun Kauppahalli (1896, architect Gustaf Nyström): Finland's second oldest
-- market hall, running between Eerikinkatu 16 and Linnankatu 15 in the center
-- of Turku. OSM building 24911: center (-215.2, 195.5), length 118.4, width 17.3,
-- yaw -0.954, height 10.8.
--
-- On foot: walk in through the ornate brick entrance on Eerikinkatu, browse along
-- the bustling central market aisle with its historic wooden food stalls (fresh fish,
-- bakery, local cheeses, hot soup, cafe), buy warm korvapuusti and coffee or fresh
-- lohileipä to recover health, and walk out the other end onto Linnankatu near
-- Aurajoki (or vice versa).
--
-- Layer 1: the interior is an authentic high-ceiling timber market hall with arched
-- wooden roof trusses, clerestory skylight ridge, hanging bronze pendant lamps,
-- detailed food stalls, market traders and browsing shoppers. Hiding inside breaks
-- police line-of-sight and drops wanted heat.
local G = require "lib.state"
local U = require "lib.util"
local health = require "lib.health"
local wanted = require "lib.wanted"

local M = {built = false, stalls = {}}

-- Building footprint and orientation (from turku_osm.lua:24911)
local CX, CZ = -215.2, 195.5
local YAW = -0.954 -- rad (~ -54.7 degrees)
local HF = 4.80    -- floor elevation (Eerikinkatu 4.92, Linnankatu 4.60)
local LAYER = 1

local FA_X = math.sin(YAW)  -- -0.815714: forward along length toward Linnankatu
local FA_Z = math.cos(YAW)  --  0.578453
local CA_X = -FA_Z          -- -0.578453: across to the right (west side)
local CA_Z = FA_X           -- -0.815714

-- Convert local (along, across) to world (x, z)
local function hall_xz(along, across)
  return CX + FA_X * along + CA_X * (across or 0),
         CZ + FA_Z * along + CA_Z * (across or 0)
end
M.hall_xz = hall_xz

-- Convert world (x, z) to local (along, across)
local function hall_ac(x, z)
  local dx, dz = x - CX, z - CZ
  return dx * FA_X + dz * FA_Z,
         dx * CA_X + dz * CA_Z
end
M.hall_ac = hall_ac

-- Door waypoints
-- Door 1: Eerikinkatu (along ~ -57)
-- Door 2: Linnankatu (along ~ +57)
M.DOORS = {
  eerikinkatu = {
    name = "Eerikinkatu",
    along_out = -59.0, along_in = -54.5,
    out_x = 0, out_z = 0, in_x = 0, in_z = 0,
    y = 4.92,
  },
  linnankatu = {
    name = "Linnankatu",
    along_out = 59.0, along_in = 54.5,
    out_x = 0, out_z = 0, in_x = 0, in_z = 0,
    y = 4.60,
  },
}

-- Builder kit for accumulating meshes in local frame
local function make_kit()
  local k = {parts = {}, solids = {}}
  local yaw_a = YAW
  local yaw_c = YAW - math.pi / 2

  local function put(p, solid)
    k.parts[#k.parts + 1] = p
    if solid then k.solids[#k.solids + 1] = p end
    return p
  end

  function k.box(along, across, cy, l, w, h, color, solid, emissive)
    local x, z = hall_xz(along, across)
    return put({mesh = "cube", pos = {x, cy, z}, yaw = yaw_a, size = {w, h, l},
                color = color, emissive = emissive}, solid)
  end

  function k.box_c(along, across, cy, l, w, h, color, solid, emissive)
    local x, z = hall_xz(along, across)
    return put({mesh = "cube", pos = {x, cy, z}, yaw = yaw_c, size = {l, h, w},
                color = color, emissive = emissive}, solid)
  end

  function k.text_a(along, across, y, s, height, color, emissive, side)
    local x, z = hall_xz(along, across)
    local yaw = side == -1 and (yaw_a + math.pi) or yaw_a
    k.parts[#k.parts + 1] = {text = s, pos = {x, y, z}, yaw = yaw, height = height,
                             depth = 0.04, color = color or {1, 1, 1}, emissive = emissive}
  end

  function k.text_c(along, across, y, s, height, color, emissive, side)
    local x, z = hall_xz(along, across)
    local yaw = side == -1 and (yaw_c + math.pi) or yaw_c
    k.parts[#k.parts + 1] = {text = s, pos = {x, y, z}, yaw = yaw, height = height,
                             depth = 0.04, color = color or {1, 1, 1}, emissive = emissive}
  end

  function k.text_stall(along, across, y, s, height, color, emissive, side)
    local x, z = hall_xz(along, across)
    -- side 1: east stall, facing -c (into aisle); side -1: west stall, facing +c (into aisle)
    local yaw = side == 1 and (yaw_c + math.pi) or yaw_c
    k.parts[#k.parts + 1] = {text = s, pos = {x, y, z}, yaw = yaw, height = height,
                             depth = 0.04, color = color or {1, 1, 1}, emissive = emissive}
  end

  return k
end

-- Stalls definition: position along length, side (-1 = west/right, 1 = east/left)
local STALL_DEFS = {
  {along = -45, side =  1, name = "KAHVILA HALLI",   item = "KORVAPUUSTI & KAHVI", price = 5,  heal = 30, color = {0.85, 0.45, 0.2}},
  {along = -45, side = -1, name = "LEIPOMO JUURI",    item = "RUISLEIPÄ",           price = 4,  heal = 25, color = {0.75, 0.55, 0.3}},
  {along = -29, side = -1, name = "KALALIIKE VIRTANEN", item = "LOHILEIPÄ",        price = 8,  heal = 50, color = {0.2, 0.6, 0.8}},
  {along = -29, side =  1, name = "TURUN JUUSTOPUOTI",item = "LEIPÄJUUSTO",         price = 6,  heal = 35, color = {0.9, 0.8, 0.3}},
  {along = -13, side = -1, name = "LIHAKAUPPA LAINE", item = "TURUN MAKKARA",       price = 5,  heal = 30, color = {0.8, 0.25, 0.2}},
  {along = -13, side =  1, name = "PIIRAKKAPAJA",     item = "KARJALANPIIRAKKA",    price = 4,  heal = 25, color = {0.9, 0.7, 0.35}},
  {along =   3, side =  1, name = "HERKKU-KEITTO",    item = "LOHIKEITTO",          price = 10, heal = 65, color = {0.85, 0.35, 0.15}},
  {along =   3, side = -1, name = "VIHANNES-AITTA",   item = "MARJARASIA",          price = 4,  heal = 20, color = {0.3, 0.75, 0.3}},
  {along =  19, side = -1, name = "SAVUSTAMO SAARISTO",item = "SAVUSIIKA",          price = 9,  heal = 55, color = {0.65, 0.45, 0.25}},
  {along =  19, side =  1, name = "SUKLAAPUOTI ÅBO",  item = "SUKLAARASIA",         price = 6,  heal = 30, color = {0.45, 0.25, 0.15}},
  {along =  35, side =  1, name = "LUOMUTILA KESTI",  item = "METSÄHUNAJAA",        price = 7,  heal = 35, color = {0.95, 0.65, 0.1}},
  {along =  35, side = -1, name = "KAHVIPAATTI",      item = "PANNUKAHVI",          price = 3,  heal = 15, color = {0.5, 0.3, 0.15}},
}

-- Build exterior entrance facades in Layer 0
local function build_exterior(d1, d2)
  local k = make_kit()
  local BRICK = {0.58, 0.28, 0.22}
  local TRIM = {0.85, 0.82, 0.75}
  local WOOD = {0.18, 0.24, 0.18}
  local GOLD = {0.95, 0.82, 0.32}
  local GLASS = {0.2, 0.25, 0.3}

  -- Build portal arch at an entrance end
  local function portal(along, facing, y_ground)
    local dir = facing > 0 and 1 or -1
    local a_wall = along
    local a_frame = along + dir * 0.25
    local a_sign = along + dir * 0.45

    -- Brick entrance pillars & gable portal
    k.box(a_wall, -3.2, y_ground + 2.5, 0.8, 2.2, 5.0, BRICK, true)
    k.box(a_wall,  3.2, y_ground + 2.5, 0.8, 2.2, 5.0, BRICK, true)
    -- Arch header over door
    k.box(a_wall, 0, y_ground + 4.2, 0.8, 4.4, 1.8, BRICK, true)
    -- Stone pediment / cornice trim
    k.box(a_frame, 0, y_ground + 5.1, 0.4, 8.8, 0.35, TRIM, true)
    k.box(a_frame, 0, y_ground + 5.6, 0.3, 4.2, 0.65, BRICK, true)

    -- Entrance doors (dark green wooden frames with glass panels)
    k.box(a_frame, -1.1, y_ground + 1.5, 0.15, 1.8, 3.0, WOOD, true)
    k.box(a_frame,  1.1, y_ground + 1.5, 0.15, 1.8, 3.0, WOOD, true)
    k.box(a_frame, -1.1, y_ground + 1.6, 0.18, 1.3, 2.2, GLASS, false, 0.25)
    k.box(a_frame,  1.1, y_ground + 1.6, 0.18, 1.3, 2.2, GLASS, false, 0.25)
    -- Brass door handles
    k.box(a_sign, -0.2, y_ground + 1.4, 0.08, 0.08, 0.4, GOLD)
    k.box(a_sign,  0.2, y_ground + 1.4, 0.08, 0.08, 0.4, GOLD)

    -- Signboard with gold embossed lettering
    k.box(a_sign, 0, y_ground + 3.8, 0.12, 6.2, 0.75, {0.12, 0.18, 0.14})
    k.text_a(a_sign + dir * 0.08, 0, y_ground + 3.8, "TURUN KAUPPAHALLI", 0.38, GOLD, 0.8, facing)
    k.text_a(a_sign + dir * 0.08, 0, y_ground + 4.4, "ANNO 1896", 0.24, TRIM, 0.6, facing)

    -- Brass coach lanterns flanking entrance
    for _, side in ipairs{-2.4, 2.4} do
      k.box(a_sign, side, y_ground + 2.8, 0.2, 0.2, 0.5, GOLD)
      k.box(a_sign, side, y_ground + 2.8, 0.16, 0.16, 0.3, {1.0, 0.9, 0.6}, false, 1.0)
    end
  end

  portal(d1.along_out + 1.0, -1, d1.y) -- Eerikinkatu facing -a
  portal(d2.along_out - 1.0,  1, d2.y) -- Linnankatu facing +a

  -- Spawn exterior meshes in Layer 0
  engine.mesh("kauppahalli_exterior", k.parts)
  engine.spawn{mesh = "kauppahalli_exterior", pos = {0, 0, 0}, layer = 0, tag = "building"}
  for _, s in ipairs(k.solids) do
    engine.spawn{mesh = "cube", pos = s.pos, yaw = s.yaw, size = s.size, visible = false,
                 body = "static", tag = "wall", layer = 0}
  end

  -- Street lights by entrance doors
  local x1, z1 = hall_xz(d1.along_out, 0)
  local x2, z2 = hall_xz(d2.along_out, 0)
  engine.light{pos = {x1, d1.y + 3.2, z1}, color = {1.0, 0.92, 0.75}, intensity = 1.0, radius = 10, layer = 0}
  engine.light{pos = {x2, d2.y + 3.2, z2}, color = {1.0, 0.92, 0.75}, intensity = 1.0, radius = 10, layer = 0}
end

-- Build indoor market hall in Layer 1
local function build_interior()
  local k = make_kit()

  local TILE1 = {0.78, 0.74, 0.68}   -- warm limestone tile
  local TILE2 = {0.55, 0.38, 0.30}   -- terracotta tile
  local BRICK = {0.54, 0.26, 0.20}   -- interior red brick
  local TIMBER = {0.30, 0.20, 0.14}  -- dark stained timber beams
  local WOOD_PINE = {0.62, 0.48, 0.32}
  local STALL_GREEN = {0.18, 0.32, 0.22}
  local GLASS = {0.65, 0.78, 0.85}
  local SKYLIGHT = {0.85, 0.92, 1.0}
  local GOLD = {0.95, 0.82, 0.35}

  -- 1. Main Tiled Floor: 112 m long, 15 m wide
  -- Base subfloor
  k.box(0, 0, HF - 0.25, 112, 15.4, 0.5, {0.45, 0.43, 0.40}, true)
  -- Patterned checkerboard tiles down the central walking aisle
  for a = -54, 54, 3 do
    for c = -2.0, 2.0, 1.0 do
      local col = (math.floor(a / 3) + math.floor(c)) % 2 == 0 and TILE1 or TILE2
      k.box(a + 1.5, c + 0.5, HF + 0.02, 3.0, 1.0, 0.04, col)
    end
  end
  -- Border tiles under stalls
  k.box(0, -4.6, HF + 0.02, 110, 4.8, 0.04, TILE1)
  k.box(0,  4.6, HF + 0.02, 110, 4.8, 0.04, TILE1)

  -- 2. Perimeter Walls
  local H_WALL = 6.8
  -- West and East long walls
  k.box(0, -7.5, HF + H_WALL / 2, 112, 0.6, H_WALL, BRICK, true)
  k.box(0,  7.5, HF + H_WALL / 2, 112, 0.6, H_WALL, BRICK, true)
  -- North wall (Eerikinkatu end) with 2.8m wide doorway
  k.box(-55.8, -4.8, HF + H_WALL / 2, 0.6, 5.4, H_WALL, BRICK, true)
  k.box(-55.8,  4.8, HF + H_WALL / 2, 0.6, 5.4, H_WALL, BRICK, true)
  k.box(-55.8,  0.0, HF + 4.8, 0.6, 4.2, H_WALL - 2.8, BRICK, true)
  -- South wall (Linnankatu end) with doorway
  k.box( 55.8, -4.8, HF + H_WALL / 2, 0.6, 5.4, H_WALL, BRICK, true)
  k.box( 55.8,  4.8, HF + H_WALL / 2, 0.6, 5.4, H_WALL, BRICK, true)
  k.box( 55.8,  0.0, HF + 4.8, 0.6, 4.2, H_WALL - 2.8, BRICK, true)

  -- Doors back to street inside
  for _, end_a in ipairs{-55.6, 55.6} do
    k.box(end_a, 0, HF + 1.4, 0.1, 2.6, 2.8, {0.2, 0.25, 0.28}, false, 0.4)
  end

  -- 3. Arched Timber Roof Trusses and Ceiling
  -- Sloped ceiling panels rising from wall eaves (y = 9.8) to clerestory (y = 11.5)
  for a = -54, 54, 12 do
    -- Exposed timber roof arches every 6m
    for da = 0, 6, 6 do
      local ta = a + da
      if math.abs(ta) <= 54 then
        -- Vertical wall pillars
        k.box(ta, -7.2, HF + 3.4, 0.45, 0.45, 6.6, TIMBER, true)
        k.box(ta,  7.2, HF + 3.4, 0.45, 0.45, 6.6, TIMBER, true)
        -- Horizontal tie beam across hall
        k.box(ta, 0, HF + 6.8, 0.4, 14.8, 0.4, TIMBER, true)
        -- King post and diagonals
        k.box(ta, 0, HF + 8.2, 0.35, 0.35, 2.8, TIMBER)
        k.box(ta, -3.2, HF + 7.8, 0.3, 0.3, 2.2, TIMBER)
        k.box(ta,  3.2, HF + 7.8, 0.3, 0.3, 2.2, TIMBER)
      end
    end
  end

  -- Sloped roof boards
  k.box(0, -4.6, HF + 8.2, 112, 5.8, 0.25, WOOD_PINE, true)
  k.box(0,  4.6, HF + 8.2, 112, 5.8, 0.25, WOOD_PINE, true)

  -- 4. Central Clerestory Skylight Ridge (Glass letting in soft daylight)
  -- Raised clerestory walls
  k.box(0, -1.9, HF + 8.9, 112, 0.15, 1.4, TIMBER, true)
  k.box(0,  1.9, HF + 8.9, 112, 0.15, 1.4, TIMBER, true)
  -- Skylight windows with soft emissive glow
  k.box(0, -1.92, HF + 8.9, 110, 0.08, 1.0, SKYLIGHT, false, 0.45)
  k.box(0,  1.92, HF + 8.9, 110, 0.08, 1.0, SKYLIGHT, false, 0.45)
  -- Ridge roof top cap
  k.box(0, 0, HF + 9.8, 112, 4.2, 0.3, TIMBER, true)

  -- 5. Market Stalls (12 authentic vendor booths)
  for _, def in ipairs(STALL_DEFS) do
    local sa = def.along
    local sc = def.side * 4.6 -- stall center across
    local front_c = def.side * 2.2 -- counter front edge
    local back_c = def.side * 7.1  -- back wall

    -- Stall partition walls (separating booths along length)
    k.box(sa - 6.5, sc, HF + 1.8, 0.25, 4.6, 3.6, TIMBER, true)
    k.box(sa + 6.5, sc, HF + 1.8, 0.25, 4.6, 3.6, TIMBER, true)

    -- Stall back storage shelves and wooden cabinets
    k.box(sa, back_c - def.side * 0.3, HF + 1.5, 11.8, 0.6, 3.0, {0.35, 0.22, 0.15}, true)
    for shelf_y = 1.0, 2.5, 0.6 do
      k.box(sa, back_c - def.side * 0.3, HF + shelf_y, 11.6, 0.7, 0.08, WOOD_PINE)
    end

    -- Decorative goods on shelves (bottles, bread, boxes, cheese)
    for g = -4.5, 4.5, 1.5 do
      k.box(sa + g, back_c - def.side * 0.35, HF + 1.25, 0.5, 0.35, 0.4, def.color)
      k.box(sa + g + 0.5, back_c - def.side * 0.35, HF + 1.85, 0.4, 0.3, 0.35, def.color)
    end

    -- Front sales counter (green/wood panelling, polished oak top)
    k.box(sa, front_c, HF + 0.55, 10.6, 0.7, 1.1, STALL_GREEN, true)
    k.box(sa, front_c, HF + 1.12, 10.8, 0.85, 0.1, {0.82, 0.78, 0.70}, true) -- counter slab

    -- Glass display case on counter
    k.box(sa, front_c - def.side * 0.1, HF + 1.45, 8.8, 0.5, 0.55, GLASS, true, 0.2)
    -- Counter top merchandise
    for m = -3.0, 3.0, 1.8 do
      k.box(sa + m, front_c - def.side * 0.1, HF + 1.3, 0.6, 0.35, 0.22, def.color)
    end

    -- Overhead brass hanging signboard with stall name
    local sign_y = HF + 3.2
    k.box(sa, front_c, sign_y, 7.8, 0.12, 0.65, {0.12, 0.18, 0.14})
    k.box(sa, front_c, sign_y, 8.0, 0.14, 0.72, GOLD)
    -- Sign text facing aisle
    k.text_stall(sa, front_c - def.side * 0.1, sign_y, def.name, 0.32, GOLD, 0.85, def.side)

    -- Stall brass counter bell / till
    k.box(sa + 4.2, front_c, HF + 1.25, 0.3, 0.3, 0.16, GOLD)

    -- Register stall interactive zone
    M.stalls[#M.stalls + 1] = {
      name = def.name,
      item = def.item,
      price = def.price,
      heal = def.heal,
      along = sa,
      across = front_c - def.side * 0.9, -- standing spot in aisle in front of counter
      x = 0, z = 0, -- populated below
    }
  end

  -- 6. Hanging Period Bronze Lanterns down central aisle
  for a = -50, 50, 10 do
    local lx, lz = hall_xz(a, 0)
    -- Suspension rod
    k.box(a, 0, HF + 6.0, 0.08, 0.08, 3.0, TIMBER)
    -- Lantern housing
    k.box(a, 0, HF + 4.4, 0.45, 0.45, 0.6, GOLD)
    -- Glowing warm filament
    k.box(a, 0, HF + 4.4, 0.32, 0.32, 0.4, {1.0, 0.95, 0.8}, false, 1.0)
    -- Point light in Layer 1
    engine.light{pos = {lx, HF + 4.2, lz}, color = {1.0, 0.92, 0.82}, intensity = 1.15,
                 radius = 15, layer = LAYER}
  end

  -- 7. Ambient Market Traders & Customers (NPCs in Layer 1)
  -- Spawn traders behind interactive counters
  local trader_spots = {
    {along = -45, across =  3.4, yaw = -math.pi / 2, mesh = "ped1"},  -- Kahvila barista
    {along = -29, across = -3.4, yaw =  math.pi / 2, mesh = "ped3"},  -- Fishmonger
    {along = -13, across =  3.4, yaw = -math.pi / 2, mesh = "ped5"},  -- Piirakkapaja baker
    {along =   3, across =  3.4, yaw = -math.pi / 2, mesh = "ped7"},  -- Soup chef
  }
  for _, tr in ipairs(trader_spots) do
    local tx, tz = hall_xz(tr.along, tr.across)
    engine.spawn{mesh = tr.mesh, pos = {tx, HF + 0.9, tz}, yaw = tr.yaw + YAW,
                 size = {0.7, 1.8, 0.7}, layer = LAYER, tag = "ped"}
  end

  -- Ambient customers walking/browsing the aisle
  local customer_spots = {
    {along = -40, across =  0.6, yaw = 0.2,  mesh = "ped2"},
    {along = -24, across = -0.5, yaw = -1.2, mesh = "ped4"},
    {along =  -8, across =  0.8, yaw = 2.4,  mesh = "ped6"},
    {along =   8, across = -0.7, yaw = 1.1,  mesh = "ped8"},
    {along =  25, across =  0.3, yaw = -0.5, mesh = "ped9"},
  }
  for _, cu in ipairs(customer_spots) do
    local cx, cz = hall_xz(cu.along, cu.across)
    engine.spawn{mesh = cu.mesh, pos = {cx, HF + 0.9, cz}, yaw = cu.yaw + YAW,
                 size = {0.7, 1.8, 0.7}, layer = LAYER, tag = "ped"}
  end

  -- Spawn interior meshes and collision solids in Layer 1
  engine.mesh("kauppahalli_interior", k.parts)
  engine.spawn{mesh = "kauppahalli_interior", pos = {0, 0, 0}, layer = LAYER, tag = "building"}
  for _, s in ipairs(k.solids) do
    engine.spawn{mesh = "cube", pos = s.pos, yaw = s.yaw, size = s.size, visible = false,
                 body = "static", tag = s.tag or "wall", layer = LAYER}
  end

  -- Calculate world coordinates for stall interaction points
  for _, st in ipairs(M.stalls) do
    st.x, st.z = hall_xz(st.along, st.across)
  end
end

-- Initialize sounds
local function init_audio()
  engine.synth("market_eat", {wave = "noise", freq = 800, freq_end = 250, dur = 0.14,
                              attack = 0.01, release = 0.1, volume = 0.35, lowpass = 0.4})
  engine.synth("market_bell", {wave = "sine", notes = {1174, 1568}, note_len = 0.12, volume = 0.3})
end

function M.build(map)
  if not map or map.id ~= "turku" or M.built then return end
  M.built = true
  M.map = map

  init_audio()

  -- Calculate door world coordinates
  local d1, d2 = M.DOORS.eerikinkatu, M.DOORS.linnankatu
  d1.out_x, d1.out_z = hall_xz(d1.along_out, 0)
  d1.in_x,  d1.in_z  = hall_xz(d1.along_in, 0)
  d2.out_x, d2.out_z = hall_xz(d2.along_out, 0)
  d2.in_x,  d2.in_z  = hall_xz(d2.along_in, 0)

  build_exterior(d1, d2)
  build_interior()
end

-- Check if player is near a door to transition layers
local function check_door_transition()
  if not G.player or G.vehicle or not engine.exists(G.player) then return end
  local px, py, pz = engine.pos(G.player)
  local cur_layer = engine.layer(G.player) or 0

  for _, d in pairs(M.DOORS) do
    if cur_layer == 0 then
      -- Outside on street: walking up to door entrance
      local dist = U.dist2d(px, pz, d.out_x, d.out_z)
      if dist < 1.6 and math.abs(py - d.y) < 2.5 then
        -- Step into Kauppahalli (Layer 1)
        engine.play("door", {volume = 0.5})
        engine.play("market_bell", {volume = 0.25})
        engine.set_pos(G.player, d.in_x, HF + 0.9, d.in_z)
        engine.set_vel(G.player, 0, 0, 0)
        engine.set_layer(G.player, LAYER)
        engine.view_layer(LAYER)
        U.message("TURUN KAUPPAHALLI (1896)", 3)
        engine.emit("interior_enter", "kauppahalli")

        -- Evading police: lose direct sight
        if wanted.stars() > 0 then
          wanted.seen = false
          wanted.hiding = true
        end
        return
      end
    elseif cur_layer == LAYER then
      -- Inside hall: walking up to exit door
      local dist = U.dist2d(px, pz, d.in_x, d.in_z)
      if dist < 1.6 then
        -- Step out onto street (Layer 0)
        engine.play("door", {volume = 0.5})
        engine.set_pos(G.player, d.out_x, d.y + 0.9, d.out_z)
        engine.set_vel(G.player, 0, 0, 0)
        engine.set_layer(G.player, 0)
        engine.view_layer(0)
        wanted.hiding = nil
        engine.emit("interior_exit", "kauppahalli")
        return
      end
    end
  end
end

-- Find nearest interactive stall
local function current_stall()
  if not G.player or G.vehicle or not engine.exists(G.player) then return nil end
  if (engine.layer(G.player) or 0) ~= LAYER then return nil end
  local px, _, pz = engine.pos(G.player)

  for _, st in ipairs(M.stalls) do
    if U.dist2d(px, pz, st.x, st.z) < 2.0 then
      return st
    end
  end
  return nil
end
M.current_stall = current_stall

-- Handle user interaction
local function buy_from_stall(st)
  if not st then return end
  if G.cash < st.price then
    U.message(string.format("TARVITSET $%d", st.price), 2)
    engine.play("click", {ui = true})
    return
  end

  G.cash = G.cash - st.price
  health.heal_player(st.heal)
  engine.play("buy", {ui = true})
  engine.play("market_eat", {volume = 0.4})
  U.message(string.format("+%d HP: %s (-$%d)", st.heal, st.item, st.price), 3)
  engine.emit("purchase", st.price)
end

-- Key press interaction
engine.on("key", function(k, down)
  if not down or (k ~= "r" and k ~= "e") then return end
  local st = current_stall()
  if st then buy_from_stall(st) end
end)

-- Main tick
engine.on("tick", function(dt)
  if not M.built then return end
  check_door_transition()

  -- Hiding decay in wanted heat
  if G.player and (engine.layer(G.player) or 0) == LAYER and wanted.stars() > 0 then
    wanted.unseen(dt * 1.5, CX, CZ)
  end
end)

-- On-screen HUD prompt when standing near stall
engine.on("frame", function()
  local st = current_stall()
  if not st then return end
  local prompt = string.format("R: %s - %s ($%d, +%d HP)", st.name, st.item, st.price, st.heal)
  local w, h = engine.screen()
  local tw = engine.text_width(prompt, 18)
  engine.rect((w - tw) / 2 - 12, h - 135, tw + 24, 30, 0, 0, 0, 0.75)
  engine.text(prompt, (w - tw) / 2, h - 129, 18, 0.95, 0.85, 0.4, 1.0)
end)

-- Minimap icon
engine.on("minimap", function(map_fn)
  if not M.built then return end
  local mx, my = map_fn(CX, CZ)
  engine.rect(mx - 4, my - 4, 8, 8, 0.95, 0.8, 0.3, 1)
  engine.text("H", mx + 6, my - 6, 10, 0.95, 0.8, 0.3, 1)
end)

return M
