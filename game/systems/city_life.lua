-- Turku City Life: Wave 4 life & polish
-- 1. Kauppatori market square life by day (06:00 - 18:00):
--    - Iconic Turku Torikahvilateltta with tables, benches, coffee urns, pastries
--    - Vendor NPC behind the counter
--    - "R: OSTA KAHVI & POSSUMUNKKI ($5, +35 HP)" / "E: LIHAPIIRAKKA ($6, +45 HP)"
--    - Market stall quick-purchases (strawberries, peas, new potatoes, rye bread)
--    - Full daytime schedule: bustling morning/day market, closes at 18:00
-- 2. Aurajoki Riverboats (Jokilaivat):
--    - Svarte Rudolf, Donna, and Majland flagship vessels along Aurajoki quays
--    - Walkable Layer 0 gangways (kulkusillat) from stone quays to decks
--    - Walkable solid decks with railings, deck tables, umbrellas, and deck bars
--    - Bartender NPCs and seated patron NPCs
--    - Bar interaction: "R: TILAA KYLMÄ HUURTEINEN ($6, +25 HP)"
--    - Warm glowing fairy/string lights that illuminate from dusk through the night (16:00 - 04:00)

local U = require "lib.util"
local G = require "lib.state"
local health = require "lib.health"
local daynight = require "lib.daynight"
local prefabs = require "lib.prefabs"
local aurajoki = require "systems.aurajoki"

local M = {
  built = false,
  map = nil,
  torikahvila = nil,
  boats = {},
  lights = {},
  stalls = {},
  entities = {},
  day_entities = {},
  night_entities = {},
  light_entities = {},
}

-- Sound synthesis for civic market and boat life
local function init_audio()
  -- Steaming hot morning market coffee
  engine.synth("torikahvi", {wave = "sine", notes = {440, 554, 659}, note_len = 0.08, volume = 0.35})
  -- Crispy fresh sugar doughnut / pastry bite
  engine.synth("possumunkki", {wave = "triangle", notes = {330, 392, 494}, note_len = 0.09, volume = 0.35})
  -- Cold clinking pint of beer / cocktail on the riverboat deck
  engine.synth("jokilaiva_drink", {wave = "sine", notes = {493, 622, 740}, note_len = 0.1, volume = 0.40})
end

local function init_npc_meshes()
  prefabs.person("baker_vendor", {0.95, 0.95, 0.92}, {0.2, 0.25, 0.3}, {0.85, 0.7, 0.55}, {0.4, 0.25, 0.15})
  prefabs.person("bartender_rudolf", {0.18, 0.18, 0.22}, {0.15, 0.15, 0.18}, {0.88, 0.72, 0.58}, {0.15, 0.1, 0.05})
  prefabs.person("bartender_donna", {0.96, 0.88, 0.25}, {0.95, 0.95, 0.95}, {0.92, 0.78, 0.65}, {0.85, 0.7, 0.35})
  prefabs.person("bartender_majland", {0.16, 0.38, 0.22}, {0.22, 0.22, 0.25}, {0.82, 0.65, 0.50}, {0.3, 0.2, 0.1})

  local SHIRTS = {{0.8, 0.2, 0.2}, {0.2, 0.4, 0.8}, {0.9, 0.8, 0.3}, {0.3, 0.6, 0.35}, {0.95, 0.95, 0.92}, {0.9, 0.5, 0.2}}
  local PANTS = {{0.15, 0.2, 0.4}, {0.25, 0.25, 0.25}, {0.5, 0.4, 0.3}, {0.1, 0.1, 0.1}}
  local SKINS = {{0.95, 0.8, 0.65}, {0.85, 0.65, 0.5}, {0.6, 0.42, 0.3}}
  local HAIR = {{0.1, 0.07, 0.04}, {0.45, 0.3, 0.12}, {0.8, 0.7, 0.4}}

  for i = 1, 8 do
    local shirt = SHIRTS[(i * 3) % #SHIRTS + 1]
    local pants = PANTS[i % #PANTS + 1]
    local skin = SKINS[(i * 5) % #SKINS + 1]
    local hair = HAIR[(i * 7) % #HAIR + 1]
    engine.mesh("city_sitter" .. i, {
      {mesh = "cube", pos = {0.13, 0.06, 0.2}, size = {0.2, 0.18, 0.5}, color = pants},
      {mesh = "cube", pos = {-0.13, 0.06, 0.2}, size = {0.2, 0.18, 0.5}, color = pants},
      {mesh = "cube", pos = {0.13, -0.24, 0.42}, size = {0.18, 0.5, 0.18}, color = pants},
      {mesh = "cube", pos = {-0.13, -0.24, 0.42}, size = {0.18, 0.5, 0.18}, color = pants},
      {mesh = "cube", pos = {0, 0.48, -0.02}, size = {0.56, 0.66, 0.32}, color = shirt},
      {mesh = "cube", pos = {0.34, 0.45, 0.04}, size = {0.14, 0.55, 0.18}, color = skin},
      {mesh = "cube", pos = {-0.34, 0.45, 0.04}, size = {0.14, 0.55, 0.18}, color = skin},
      {mesh = "sphere", pos = {0, 0.98, 0}, size = 0.34, color = skin},
      {mesh = "cube", pos = {0, 1.07, -0.03}, size = {0.36, 0.12, 0.36}, color = hair},
    })
  end
end

--------------------------------------------------------------------------------
-- 1. KAUPPATORI: AITO TORIKAHVILA & TORIKOJUT
--------------------------------------------------------------------------------

local function build_torikahvila()
  -- Kauppatori plaza coordinates from kauppatori.lua
  local px, pz, pyaw, pw, pd = -172.3, -16.8, 0.602, 128.5, 115.0
  local c, s = math.cos(pyaw), math.sin(pyaw)
  local function at(u, v) return U.ground(px + c * pw * u + s * pd * v, pz - s * pw * u + c * pd * v) end
  local gu = (at(0.5, 0) - at(-0.5, 0)) / pw
  local gv = (at(0, 0.5) - at(0, -0.5)) / pd
  local function top(u, v) return at(0, 0) + 0.6 + gu * u + gv * v end

  -- Center of Torikahvila tent on the northern half of the plaza slab
  local ku, kv = -2.0, -36.0
  local kx = px + c * ku + s * kv
  local kz = pz - s * ku + c * kv
  local ky = top(ku, kv)
  local kw, kd, kh = 11.0, 7.2, 3.2

  local parts = {}
  local ORANGE = {0.94, 0.48, 0.12}
  local CREAM = {0.96, 0.96, 0.92}
  local POLE = {0.80, 0.82, 0.85}
  local PINE = {0.75, 0.56, 0.34}
  local DARK_WOOD = {0.42, 0.28, 0.18}
  local CHALKBOARD = {0.14, 0.16, 0.15}
  local GOLD = {0.95, 0.82, 0.30}
  local STEEL = {0.85, 0.86, 0.88}

  -- 4 Corner upright steel posts + 2 center ridge posts
  for _, ux in ipairs{-kw / 2 + 0.2, kw / 2 - 0.2} do
    for _, vz in ipairs{-kd / 2 + 0.2, kd / 2 - 0.2} do
      parts[#parts + 1] = {mesh = "cylinder", pos = {ux, 1.2, vz}, size = {0.12, 2.4, 0.12}, color = POLE}
    end
    -- Center ridge posts
    parts[#parts + 1] = {mesh = "cylinder", pos = {ux, 1.6, 0}, size = {0.14, 3.2, 0.14}, color = POLE}
  end

  -- Pitched canvas tent roof with traditional orange and cream canopy stripes
  -- Left roof slope
  parts[#parts + 1] = {mesh = "cube", pos = {0, 2.8, -kd / 4}, size = {kw + 0.4, 0.08, kd / 2 + 0.3},
                       pitch = 0.24, color = ORANGE}
  -- Right roof slope
  parts[#parts + 1] = {mesh = "cube", pos = {0, 2.8, kd / 4}, size = {kw + 0.4, 0.08, kd / 2 + 0.3},
                       pitch = -0.24, color = ORANGE}
  -- Alternating cream stripes on canopy
  for i = -4, 4, 2 do
    parts[#parts + 1] = {mesh = "cube", pos = {i * 1.15, 2.83, -kd / 4}, size = {0.55, 0.09, kd / 2 + 0.28},
                         pitch = 0.24, color = CREAM}
    parts[#parts + 1] = {mesh = "cube", pos = {i * 1.15, 2.83, kd / 4}, size = {0.55, 0.09, kd / 2 + 0.28},
                         pitch = -0.24, color = CREAM}
  end

  -- Front scalloped valance awning
  parts[#parts + 1] = {mesh = "cube", pos = {0, 2.25, kd / 2 + 0.05}, size = {kw + 0.3, 0.4, 0.06}, color = ORANGE}
  parts[#parts + 1] = {mesh = "cube", pos = {0, 2.25, -kd / 2 - 0.05}, size = {kw + 0.3, 0.4, 0.06}, color = ORANGE}

  -- 3D Lettering sign on front valance: "TURUN TORIKAHVILA"
  parts[#parts + 1] = {text = "TURUN TORIKAHVILA", pos = {0, 2.25, kd / 2 + 0.09},
                       yaw = 0, height = 0.28, depth = 0.04, color = CREAM, emissive = 0.3}

  -- Serving counter: timber counter at v = 1.2
  local counter_len = 5.6
  parts[#parts + 1] = {mesh = "cube", pos = {0, 0.5, 1.2}, size = {counter_len, 1.0, 0.8}, color = PINE}
  parts[#parts + 1] = {mesh = "cube", pos = {0, 1.02, 1.2}, size = {counter_len + 0.2, 0.06, 0.95}, color = DARK_WOOD}

  -- Stainless steel coffee urns / dispensers on counter
  for _, cx in ipairs{-1.8, -1.2} do
    parts[#parts + 1] = {mesh = "cylinder", pos = {cx, 1.35, 1.2}, size = {0.35, 0.60, 0.35}, color = STEEL}
    parts[#parts + 1] = {mesh = "cylinder", pos = {cx, 1.68, 1.2}, size = {0.10, 0.08, 0.10}, color = GOLD}
    -- Spigot tap
    parts[#parts + 1] = {mesh = "cylinder", pos = {cx, 1.15, 1.42}, size = {0.05, 0.12, 0.05}, color = GOLD}
  end

  -- Pastry display vitrine with fresh possumunkkeja and lihapiirakoita
  parts[#parts + 1] = {mesh = "cube", pos = {0.8, 1.22, 1.2}, size = {1.8, 0.35, 0.65}, color = {0.4, 0.6, 0.7}}
  -- Tray of possumunkkeja (sugar-crusted doughnuts)
  for _, px_pos in ipairs{0.3, 0.6, 0.9, 1.2} do
    parts[#parts + 1] = {mesh = "sphere", pos = {px_pos, 1.18, 1.2}, size = 0.16, color = {0.85, 0.58, 0.25}}
  end

  -- Chalkboard menu sign hanging by the counter
  parts[#parts + 1] = {mesh = "cube", pos = {-counter_len / 2 - 0.4, 1.4, 1.2}, size = {0.85, 1.1, 0.06}, color = CHALKBOARD}
  parts[#parts + 1] = {text = "KAHVI + POSSUMUNKKI $5", pos = {-counter_len / 2 - 0.4, 1.65, 1.24},
                       height = 0.07, depth = 0.02, color = {0.95, 0.95, 0.95}}
  parts[#parts + 1] = {text = "LIHAPIIRAKKA (2 NAKKIA) $6", pos = {-counter_len / 2 - 0.4, 1.45, 1.24},
                       height = 0.065, depth = 0.02, color = GOLD}
  parts[#parts + 1] = {text = "PULLA / TEE $3", pos = {-counter_len / 2 - 0.4, 1.25, 1.24},
                       height = 0.06, depth = 0.02, color = {0.95, 0.95, 0.95}}

  -- 4 Wooden picnic tables with benches on the café terrace area (v = -1.6)
  local table_xs = {-3.5, -1.2, 1.2, 3.5}
  for _, tx in ipairs(table_xs) do
    local tz = -1.6
    -- Table top
    parts[#parts + 1] = {mesh = "cube", pos = {tx, 0.74, tz}, size = {1.6, 0.06, 0.85}, color = PINE}
    -- Table legs
    for _, lx in ipairs{tx - 0.6, tx + 0.6} do
      parts[#parts + 1] = {mesh = "cube", pos = {lx, 0.36, tz}, size = {0.08, 0.70, 0.75}, color = DARK_WOOD}
    end
    -- Benches on either side
    for _, side_z in ipairs{-0.65, 0.65} do
      parts[#parts + 1] = {mesh = "cube", pos = {tx, 0.45, tz + side_z}, size = {1.6, 0.05, 0.32}, color = PINE}
      for _, lx in ipairs{tx - 0.6, tx + 0.6} do
        parts[#parts + 1] = {mesh = "cube", pos = {lx, 0.22, tz + side_z}, size = {0.06, 0.44, 0.25}, color = DARK_WOOD}
      end
    end
  end

  engine.mesh("torikahvila_tent", parts)

  -- Spawn Torikahvila tent entity
  local tent_id = engine.spawn{
    mesh = "torikahvila_tent",
    pos = {kx, ky, kz},
    yaw = pyaw,
    tag = "building",
    body = "static",
  }
  M.torikahvila = {
    id = tent_id,
    pos = {kx, ky, kz},
    yaw = pyaw,
    counter_x = kx + math.sin(pyaw) * 1.2,
    counter_z = kz + math.cos(pyaw) * 1.2,
    counter_y = ky,
  }

  -- Vendor NPC behind counter (Torikahvila baker/barista)
  local vx = kx + math.sin(pyaw) * 0.4
  local vz = kz + math.cos(pyaw) * 0.4
  local vendor_id = engine.spawn{
    mesh = "baker_vendor",
    pos = {vx, ky + 0.9, vz},
    yaw = pyaw,
    size = {0.7, 1.8, 0.7},
    tag = "ped",
  }
  M.day_entities[#M.day_entities + 1] = vendor_id

  -- Seated morning coffee drinkers at the picnic tables
  local sit_offsets = {
    {-3.5, -1.6 - 0.65, pyaw},
    {-1.2, -1.6 + 0.65, pyaw + math.pi},
    { 1.2, -1.6 - 0.65, pyaw},
    { 3.5, -1.6 + 0.65, pyaw + math.pi},
  }
  local sitter_meshes = {"city_sitter1", "city_sitter3", "city_sitter5", "city_sitter7"}
  for i, so in ipairs(sit_offsets) do
    local ox, oz, syaw = so[1], so[2], so[3]
    local sx = kx + c * ox + s * oz
    local sz = kz - s * ox + c * oz
    local sid = engine.spawn{
      mesh = sitter_meshes[i % #sitter_meshes + 1],
      pos = {sx, ky + 0.45, sz},
      yaw = syaw,
      size = {0.6, 1.3, 0.6},
      tag = "ped",
    }
    M.day_entities[#M.day_entities + 1] = sid
  end
end

--------------------------------------------------------------------------------
-- 2. AURAJOEN JOKILAIVAT (RIVERBOATS: SVARTE RUDOLF, DONNA, MAJLAND)
--------------------------------------------------------------------------------

-- Bank polylines from aurajoki.lua for nearest quay projection
local BANKS = aurajoki.BANKS

-- The three iconic flagship restaurant boats
local FLAGSHIP_SPECS = {
  {
    name = "SVARTE RUDOLF",
    key = "rudolf",
    pos = {-158.8, 432.4},
    len = 44.5,
    beam = 7.0,
    yaw = -1.047,
    deck_y = 1.35,
    hull_color = {0.12, 0.12, 0.14},
    cabin_color = {0.26, 0.18, 0.12},
    awning_color = {0.85, 0.18, 0.16},
    accent_color = {0.95, 0.82, 0.30},
    funnel_color = {0.80, 0.15, 0.12},
    drink_name = "AURA-OLUT",
    drink_price = 6,
    drink_hp = 25,
    alt_drink_name = "LONKERO",
    alt_drink_price = 7,
    alt_drink_hp = 30,
    bartender_name = "Rudolf",
    ped_mesh = "bartender_rudolf",
  },
  {
    name = "DONNA",
    key = "donna",
    pos = {-322.8, 527.3},
    len = 35.7,
    beam = 8.6,
    yaw = 2.096,
    deck_y = 1.35,
    hull_color = {0.96, 0.88, 0.22},
    cabin_color = {0.94, 0.94, 0.96},
    awning_color = {0.96, 0.82, 0.15},
    accent_color = {0.95, 0.95, 0.95},
    funnel_color = {0.95, 0.85, 0.18},
    drink_name = "DONNA SPECIAL",
    drink_price = 7,
    drink_hp = 30,
    alt_drink_name = "KYLMÄ SIIDERI",
    alt_drink_price = 6,
    alt_drink_hp = 25,
    bartender_name = "Donna",
    ped_mesh = "bartender_donna",
  },
  {
    name = "MAJLAND",
    key = "majland",
    pos = {-747.0, 703.8},
    len = 37.2,
    beam = 6.5,
    yaw = 2.106,
    deck_y = 1.35,
    hull_color = {0.14, 0.35, 0.20},
    cabin_color = {0.92, 0.92, 0.94},
    awning_color = {0.16, 0.45, 0.24},
    accent_color = {0.92, 0.82, 0.35},
    funnel_color = {0.20, 0.40, 0.25},
    drink_name = "MAJLAND-IPA",
    drink_price = 6,
    drink_hp = 25,
    alt_drink_name = "AURA-OLUT",
    alt_drink_price = 6,
    alt_drink_hp = 25,
    bartender_name = "Matti",
    ped_mesh = "bartender_majland",
  },
}

-- Find the nearest dry stone quay by probing outward from the boat along lateral normal
local function find_dry_quay(sx, sz, syaw, sbeam)
  local R = require "lib.roadnet"
  local rx, rz = U.right(syaw)
  local best_side = nil
  local best_qx, best_qz = sx, sz
  local best_qy = 0
  local best_dist = math.huge

  for _, side in ipairs{-1, 1} do
    for d = sbeam / 2, sbeam / 2 + 15, 0.4 do
      local px = sx + side * rx * d
      local pz = sz + side * rz * d
      if not R.wet(px, pz) then
        if d < best_dist then
          best_dist = d
          best_side = side
          -- Step onto the solid stone promenade for a secure ramp footing
          local qx = px + side * rx * 2.2
          local qz = pz + side * rz * 2.2
          best_qx = qx
          best_qz = qz
          best_qy = U.ground(qx, qz)
        end
        break
      end
    end
  end

  if not best_side then
    best_side = 1
    best_qx = sx + rx * (sbeam / 2 + 3)
    best_qz = sz + rz * (sbeam / 2 + 3)
    best_qy = U.ground(best_qx, best_qz)
  end
  return best_qx, best_qz, best_qy, best_side, best_dist
end

local function build_riverboats()
  for _, spec in ipairs(FLAGSHIP_SPECS) do
    local sx, sz = spec.pos[1], spec.pos[2]
    local syaw = spec.yaw
    local slen, sbeam = spec.len, spec.beam
    local sdeck_y = spec.deck_y

    -- Direction vectors
    local fx, fz = U.forward(syaw)
    local rx, rz = U.right(syaw)

    -- 1. Find nearest dry stone quay on Aurajoki
    local qx, qz, qy, side = find_dry_quay(sx, sz, syaw, sbeam)

    -- Gate position on ship's edge facing the quay
    local gate_x = sx + side * rx * (sbeam / 2 - 0.2)
    local gate_z = sz + side * rz * (sbeam / 2 - 0.2)
    local gang_len = math.max(2.0, U.dist2d(qx, qz, gate_x, gate_z))
    local gang_cx = (qx + gate_x) / 2
    local gang_cz = (qz + gate_z) / 2
    local gang_cy = (qy + sdeck_y) / 2
    local gang_yaw = math.atan(gate_x - qx, gate_z - qz)
    local gang_pitch = -math.atan((sdeck_y - qy) / math.max(0.1, gang_len))

    -- 2. Walkable Gangway Ramp (Kulkusilta)
    -- Solid walking deck from quay to boat: tag = "deck", body = "static"
    local gang_mesh_name = "gangway_" .. spec.key
    local gparts = {
      -- Timber plank ramp
      {mesh = "cube", pos = {0, 0, 0}, size = {1.6, 0.16, gang_len + 0.3}, color = {0.68, 0.52, 0.36}},
    }
    -- Safety handrails on left and right of gangway
    for _, hside in ipairs{-0.75, 0.75} do
      gparts[#gparts + 1] = {mesh = "cube", pos = {hside, 0.55, 0}, size = {0.08, 0.90, gang_len + 0.2}, color = spec.hull_color}
      gparts[#gparts + 1] = {mesh = "cylinder", pos = {hside, 0.95, 0}, size = {0.12, gang_len + 0.2, 0.12}, axis = "z", color = spec.accent_color}
    end
    engine.mesh(gang_mesh_name, gparts)

    local gang_id = engine.spawn{
      mesh = gang_mesh_name,
      pos = {gang_cx, gang_cy, gang_cz},
      yaw = gang_yaw,
      pitch = gang_pitch,
      tag = "deck",
      body = "static",
    }
    M.entities[#M.entities + 1] = gang_id

    -- 3. Superstructure, Solid Deck & Railings
    local deck_mesh_name = "boat_deck_" .. spec.key
    local bparts = {}

    -- 3D Nameboards on both port and starboard with solid backing plates
    local board_w = #spec.name * 0.28 + 0.8
    -- Starboard sign (+X)
    bparts[#bparts + 1] = {mesh = "cube", pos = {sbeam / 2 - 0.29, 2.94, -slen * 0.15},
                           size = {0.08, 0.48, board_w}, color = spec.hull_color}
    bparts[#bparts + 1] = {text = spec.name, pos = {sbeam / 2 - 0.24, 2.75, -slen * 0.15}, yaw = math.pi / 2,
                           height = 0.38, depth = 0.06, color = spec.accent_color, emissive = 0.4}
    -- Port sign (-X)
    bparts[#bparts + 1] = {mesh = "cube", pos = {-sbeam / 2 + 0.29, 2.94, -slen * 0.15},
                           size = {0.08, 0.48, board_w}, color = spec.hull_color}
    bparts[#bparts + 1] = {text = spec.name, pos = {-sbeam / 2 + 0.24, 2.75, -slen * 0.15}, yaw = -math.pi / 2,
                           height = 0.38, depth = 0.06, color = spec.accent_color, emissive = 0.4}

    -- Sun deck awning canopy
    local canopy_len = slen * 0.45
    local canopy_w = sbeam - 0.6
    bparts[#bparts + 1] = {mesh = "cube", pos = {0, 2.65, slen * 0.1}, size = {canopy_w, 0.10, canopy_len}, color = spec.awning_color}
    -- Awning support stanchions
    for _, ux in ipairs{-canopy_w / 2 + 0.2, canopy_w / 2 - 0.2} do
      for _, uz in ipairs{slen * 0.1 - canopy_len / 2 + 0.4, slen * 0.1 + canopy_len / 2 - 0.4} do
        bparts[#bparts + 1] = {mesh = "cylinder", pos = {ux, 1.85, uz}, size = {0.08, 1.6, 0.08}, color = {0.85, 0.85, 0.88}}
      end
    end

    -- Bar counter on deck
    local bar_w = 3.6
    bparts[#bparts + 1] = {mesh = "cube", pos = {0, 0.55, -2.5}, size = {bar_w, 1.05, 0.85}, color = spec.cabin_color}
    bparts[#bparts + 1] = {mesh = "cube", pos = {0, 1.10, -2.5}, size = {bar_w + 0.2, 0.06, 1.0}, color = {0.80, 0.62, 0.42}}
    -- Brass beer tap tower
    bparts[#bparts + 1] = {mesh = "cylinder", pos = {-0.6, 1.35, -2.5}, size = {0.18, 0.45, 0.18}, color = {0.95, 0.82, 0.30}}
    bparts[#bparts + 1] = {mesh = "cylinder", pos = {-0.6, 1.55, -2.4}, size = {0.05, 0.15, 0.05}, color = {0.95, 0.82, 0.30}}

    -- Chalkboard on bar
    bparts[#bparts + 1] = {mesh = "cube", pos = {1.2, 1.45, -2.5}, size = {0.9, 0.65, 0.05}, color = {0.14, 0.16, 0.15}}
    bparts[#bparts + 1] = {text = spec.drink_name .. " $" .. spec.drink_price, pos = {1.2, 1.55, -2.46},
                           height = 0.065, depth = 0.02, color = {0.95, 0.95, 0.95}}

    -- Deck tables with parasol umbrellas
    local table_spots = {
      {-canopy_w / 3.2, slen * 0.15},
      { canopy_w / 3.2, slen * 0.15},
      {-canopy_w / 3.2, slen * 0.02},
      { canopy_w / 3.2, slen * 0.02},
    }
    for _, ts in ipairs(table_spots) do
      local tx, tz = ts[1], ts[2]
      -- Table pedestal and round top
      bparts[#bparts + 1] = {mesh = "cylinder", pos = {tx, 0.40, tz}, size = {0.08, 0.75, 0.08}, color = {0.3, 0.3, 0.32}}
      bparts[#bparts + 1] = {mesh = "cylinder", pos = {tx, 0.76, tz}, size = {1.1, 0.04, 1.1}, color = {0.78, 0.60, 0.40}}
      -- Parasol umbrella
      bparts[#bparts + 1] = {mesh = "cylinder", pos = {tx, 1.45, tz}, size = {0.05, 1.4, 0.05}, color = {0.85, 0.85, 0.88}}
      bparts[#bparts + 1] = {mesh = "cylinder", pos = {tx, 2.15, tz}, size = {1.8, 0.12, 1.8}, color = spec.awning_color}
    end

    -- Perimeter safety railings (with gate gap for the gangway)
    local rail_h = 0.95
    -- Fore and aft rails
    bparts[#bparts + 1] = {mesh = "cube", pos = {0, rail_h / 2, slen / 2 - 1.2}, size = {sbeam - 0.8, rail_h, 0.08}, color = spec.accent_color}
    bparts[#bparts + 1] = {mesh = "cube", pos = {0, rail_h / 2, -slen / 2 + 1.2}, size = {sbeam - 0.8, rail_h, 0.08}, color = spec.accent_color}
    -- Port and Starboard rails
    for _, rside in ipairs{-1, 1} do
      local x_edge = rside * (sbeam / 2 - 0.3)
      if rside ~= side then
        -- Full rail on the water side
        bparts[#bparts + 1] = {mesh = "cube", pos = {x_edge, rail_h / 2, 0}, size = {0.08, rail_h, slen - 2.8}, color = spec.accent_color}
      else
        -- Quay side: two segments leaving a 2.0m gate opening in the middle
        local half_span = (slen - 2.8 - 2.2) / 2
        bparts[#bparts + 1] = {mesh = "cube", pos = {x_edge, rail_h / 2, -half_span / 2 - 1.1}, size = {0.08, rail_h, half_span}, color = spec.accent_color}
        bparts[#bparts + 1] = {mesh = "cube", pos = {x_edge, rail_h / 2,  half_span / 2 + 1.1}, size = {0.08, rail_h, half_span}, color = spec.accent_color}
      end
    end

    engine.mesh(deck_mesh_name, bparts)

    -- Spawn deck features entity
    local deck_features_id = engine.spawn{
      mesh = deck_mesh_name,
      pos = {sx, sdeck_y, sz},
      yaw = syaw,
      tag = "deck",
      body = "static",
    }
    M.entities[#M.entities + 1] = deck_features_id

    -- 4. Solid Walkable Main Deck Floor: tag = "deck", body = "static"
    local floor_id = engine.spawn{
      mesh = "cube",
      pos = {sx, sdeck_y, sz},
      yaw = syaw,
      size = {sbeam - 0.5, 0.20, slen - 2.4},
      color = {0.70, 0.54, 0.38},
      tag = "deck",
      body = "static",
    }
    M.entities[#M.entities + 1] = floor_id

    -- 5. Bartender NPC behind the deck bar
    local bar_ped_x = sx - fx * 3.1
    local bar_ped_z = sz - fz * 3.1
    local bar_ped_id = engine.spawn{
      mesh = spec.ped_mesh,
      pos = {bar_ped_x, sdeck_y + 0.9, bar_ped_z},
      yaw = syaw,
      size = {0.7, 1.8, 0.7},
      tag = "ped",
    }
    M.night_entities[#M.night_entities + 1] = bar_ped_id

    -- 6. Seated Patrons on the deck
    local sitter_pool = {"city_sitter2", "city_sitter4", "city_sitter6", "city_sitter8"}
    for i, ts in ipairs(table_spots) do
      local tx, tz = ts[1], ts[2]
      local chair_offsets = {-0.65, 0.65}
      for ci, co in ipairs(chair_offsets) do
        local px_local = tx + (ci == 1 and co or 0)
        local pz_local = tz + (ci == 2 and co or 0)
        local px_world = sx + rx * px_local + fx * pz_local
        local pz_world = sz + rz * px_local + fz * pz_local
        local patron_id = engine.spawn{
          mesh = sitter_pool[(i + ci) % #sitter_pool + 1],
          pos = {px_world, sdeck_y + 0.50, pz_world},
          yaw = syaw + (ci == 1 and math.pi / 2 or 0),
          size = {0.6, 1.3, 0.6},
          tag = "ped",
        }
        M.night_entities[#M.night_entities + 1] = patron_id
      end
    end

    -- 7. Overhead Festoon String Lights for Night
    local light_points = {
      {sx + fx * (slen * 0.1), sdeck_y + 3.0, sz + fz * (slen * 0.1)},
      {sx - fx * 2.0, sdeck_y + 2.8, sz - fz * 2.0},
    }
    for _, lp in ipairs(light_points) do
      local lid = engine.light{
        pos = {lp[1], lp[2], lp[3]},
        color = {1.0, 0.88, 0.60},
        intensity = 1.3,
        radius = 14,
        layer = 0,
      }
      M.light_entities[#M.light_entities + 1] = lid
    end

    -- Save riverboat data
    M.boats[#M.boats + 1] = {
      spec = spec,
      pos = {sx, sdeck_y, sz},
      bar_pos = {sx - fx * 2.1, sdeck_y, sz - fz * 2.1},
      gangway_pos = {gang_cx, gang_cy, gang_cz},
      quay_pos = {qx, qy, qz},
      gate_pos = {gate_x, sdeck_y, gate_z},
    }
  end
end

--------------------------------------------------------------------------------
-- 3. INTERACTION DETECTION & EXECUTION
--------------------------------------------------------------------------------

local function current_interaction()
  if not G.player or G.vehicle or not engine.exists(G.player) then return nil end
  local px, py, pz = engine.pos(G.player)
  local cur_layer = engine.layer(G.player) or 0
  if cur_layer ~= 0 then return nil end

  local hour = daynight.hour or 12

  -- 1. Check Torikahvila serving counter on Kauppatori
  if M.torikahvila then
    local tk = M.torikahvila
    local dist_counter = U.dist2d(px, pz, tk.counter_x, tk.counter_z)
    if dist_counter < 2.4 and math.abs(py - tk.counter_y) < 2.5 then
      local is_open = (hour >= 6.0 and hour < 18.0)
      return {
        kind = "torikahvila",
        open = is_open,
        title = "TURUN TORIKAHVILA",
        prompt = is_open and "R: KAHVI & POSSUMUNKKI ($5, +35 HP)   [E: LIHAPIIRAKKA $6, +45 HP]"
                         or "TORIKAHVILA ON SULJETTU (AUKI 06:00 - 18:00)",
      }
    end
  end

  -- 2. Check regular market stalls on Kauppatori
  local kauppatori = package.loaded["systems.kauppatori"]
  if kauppatori and kauppatori.stalls and (hour >= 6.0 and hour < 18.0) then
    for i, sid in ipairs(kauppatori.stalls) do
      if engine.exists(sid) then
        local sx, sy, sz = engine.pos(sid)
        if U.dist2d(px, pz, sx, sz) < 1.9 and math.abs(py - sy) < 2.2 then
          -- Stall goods type cycle: 1=strawberries, 2=peas, 3=potatoes, 4=pastries...
          local goods_type = ((i - 1) % 6) + 1
          if goods_type == 1 then
            return {kind = "stall_berries", name = "MANSIKKAKOJU", item = "LITRA MANSIKOITA", price = 6, hp = 20,
                    prompt = "R: OSTA LITRA MANSIKOITA ($6, +20 HP)"}
          elseif goods_type == 2 then
            return {kind = "stall_peas", name = "HERNEKOJU", item = "PUSSI HERNEITÄ", price = 4, hp = 15,
                    prompt = "R: OSTA PUSSI HERNEITÄ ($4, +15 HP)"}
          elseif goods_type == 3 then
            return {kind = "stall_potatoes", name = "PERUNAKOJU", item = "UUSIA PERUNOITA", price = 3, hp = 10,
                    prompt = "R: OSTA UUSIA PERUNOITA ($3, +10 HP)"}
          else
            return {kind = "stall_bread", name = "LEIPÄKOJU", item = "RUISLEIPÄ", price = 3, hp = 15,
                    prompt = "R: OSTA RUISLEIPÄ ($3, +15 HP)"}
          end
        end
      end
    end
  end

  -- 3. Check Riverboat bars along Aurajoki
  for _, boat in ipairs(M.boats) do
    local bx, by, bz = boat.bar_pos[1], boat.bar_pos[2], boat.bar_pos[3]
    local dist_bar = U.dist2d(px, pz, bx, bz)
    if dist_bar < 2.2 and math.abs(py - by) < 2.5 then
      local is_open = (hour >= 16.0 or hour < 4.0)
      local spec = boat.spec
      local prompt_str = is_open and string.format("R: %s ($%d, +%d HP)   [E: %s $%d, +%d HP]",
                                                   spec.drink_name, spec.drink_price, spec.drink_hp,
                                                   spec.alt_drink_name, spec.alt_drink_price, spec.alt_drink_hp)
                                  or "JOKILAIVAN BAARI ON SULJETTU (AUKI 16:00 - 04:00)"
      return {
        kind = "riverboat_bar",
        boat = boat,
        open = is_open,
        title = spec.name .. " KANSIBAARI",
        prompt = prompt_str,
      }
    end
  end

  return nil
end
M.current_interaction = current_interaction

local function interact(action_key)
  local act = current_interaction()
  if not act then return end

  if act.kind == "torikahvila" then
    if not act.open then
      U.message("TORIKAHVILA ON SULJETTU (AUKI KLO 06:00 - 18:00)", 2)
      engine.play("click", {ui = true})
      return
    end

    if action_key == "r" then
      -- Coffee & Possumunkki ($5, +35 HP)
      local price = 5
      if G.cash < price then
        U.message(string.format("TARVITSET $%d", price), 2)
        engine.play("click", {ui = true})
        return
      end
      G.cash = G.cash - price
      health.heal_player(35)
      engine.play("buy", {ui = true})
      engine.play("torikahvi", {volume = 0.4})
      U.message("+35 HP: HÖYRYÄVÄ TORIKAHVI JA TUORE POSSUMUNKKI! (-$5)", 3)
      engine.emit("purchase", price)
    elseif action_key == "e" then
      -- Lihapiirakka kahdella nakilla ($6, +45 HP)
      local price = 6
      if G.cash < price then
        U.message(string.format("TARVITSET $%d", price), 2)
        engine.play("click", {ui = true})
        return
      end
      G.cash = G.cash - price
      health.heal_player(45)
      engine.play("buy", {ui = true})
      engine.play("possumunkki", {volume = 0.4})
      U.message("+45 HP: LIHAPIIRAKKA KAHDELLA NAKILLA JA KAIKILLA MAUSTEILLA! (-$6)", 3)
      engine.emit("purchase", price)
    end

  elseif act.kind and act.kind:match("^stall_") then
    -- Market stall item
    local price = act.price
    if G.cash < price then
      U.message(string.format("TARVITSET $%d", price), 2)
      engine.play("click", {ui = true})
      return
    end
    G.cash = G.cash - price
    health.heal_player(act.hp)
    engine.play("buy", {ui = true})
    engine.play("possumunkki", {volume = 0.3})
    U.message(string.format("+%d HP: %s! (-$%d)", act.hp, act.item, price), 3)
    engine.emit("purchase", price)

  elseif act.kind == "riverboat_bar" then
    if not act.open then
      U.message("JOKILAIVAN BAARI ON SULJETTU (AUKI KLO 16:00 - 04:00)", 2)
      engine.play("click", {ui = true})
      return
    end

    local spec = act.boat.spec
    if action_key == "r" then
      local price = spec.drink_price
      if G.cash < price then
        U.message(string.format("TARVITSET $%d", price), 2)
        engine.play("click", {ui = true})
        return
      end
      G.cash = G.cash - price
      health.heal_player(spec.drink_hp)
      engine.play("buy", {ui = true})
      engine.play("jokilaiva_drink", {volume = 0.45})
      U.message(string.format("+%d HP: KYLMÄ %s JOEN RANNALLA! (-$%d)", spec.drink_hp, spec.drink_name, price), 3)
      engine.emit("purchase", price)
    elseif action_key == "e" then
      local price = spec.alt_drink_price
      if G.cash < price then
        U.message(string.format("TARVITSET $%d", price), 2)
        engine.play("click", {ui = true})
        return
      end
      G.cash = G.cash - price
      health.heal_player(spec.alt_drink_hp)
      engine.play("buy", {ui = true})
      engine.play("jokilaiva_drink", {volume = 0.45})
      U.message(string.format("+%d HP: RAIKAS %s! (-$%d)", spec.alt_drink_hp, spec.alt_drink_name, price), 3)
      engine.emit("purchase", price)
    end
  end
end

-- Key press listener
engine.on("key", function(k, down)
  if not down then return end
  if k == "r" or k == "e" then
    interact(k)
  end
end)

--------------------------------------------------------------------------------
-- 4. TICK & FRAME HANDLERS
--------------------------------------------------------------------------------

local wait_tick = 0
engine.on("tick", function(dt)
  if not M.built then return end
  wait_tick = wait_tick - dt
  if wait_tick > 0 then return end
  wait_tick = 1.0

  local hour = daynight.hour or 12

  -- Schedule Kauppatori day life: visible 06:00 - 18:00
  local tori_open = (hour >= 6.0 and hour < 18.0)
  for _, id in ipairs(M.day_entities) do
    if engine.exists(id) then
      engine.set_visible(id, tori_open)
    end
  end

  -- Schedule Jokilaivat afternoon/night life: visible 16:00 - 04:00
  local boats_open = (hour >= 16.0 or hour < 4.0)
  for _, id in ipairs(M.night_entities) do
    if engine.exists(id) then
      engine.set_visible(id, boats_open)
    end
  end

  -- String lights glow at dusk and night (glow > 0.15)
  local glow = daynight.glow or 0
  local lights_on = (glow > 0.15 or hour >= 19.0 or hour < 5.0)
  for _, lid in ipairs(M.light_entities) do
    if engine.exists(lid) then
      engine.set_visible(lid, lights_on)
    end
  end
end)

-- On-screen HUD prompt
engine.on("frame", function()
  local act = current_interaction()
  if not act then return end
  local w, h = engine.screen()
  local text = act.prompt
  local tw = #text * 9
  local x = math.floor((w - tw) / 2)
  local y = h - 68
  engine.text(text, x, y, 18, 1.0, 0.95, 0.8, 1.0)
end)

--------------------------------------------------------------------------------
-- 5. BUILD ENTRY POINT
--------------------------------------------------------------------------------

function M.build(map)
  if not map or (map.id ~= "turku" and map.name ~= "Turku") or M.built then return end
  M.built = true
  M.map = map

  init_audio()
  init_npc_meshes()
  build_torikahvila()
  build_riverboats()
end

return M
