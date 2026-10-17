-- Turku Vanha Suurtori & Tuomiokirkkokortteli 500m visual slice.
-- Spawns Turun Tuomiokirkko (National Cathedral) with monumental steps,
-- Vanha Suurtori cobblestone square, Brinkkalan talo with the Christmas Peace balcony,
-- Porthaninpuisto bronze monument, and surrounding historic quarter.
local U = require "lib.util"

local S = {
  cathedral_id = nil,
  brinkkala_id = nil,
  porthan_id = nil,
  plaza_id = nil,
}

function S.build(map)
  if not map or (map.id ~= "turku" and map.name ~= "Turku") then return end

  local stone_plaza = {0.60, 0.58, 0.54}
  local granite_steps = {0.48, 0.46, 0.44}

  -- 1. Vanha Suurtori Cobblestone Square
  -- Historical civic plaza bounded by Brinkkala, Old Town Hall, and Hjelt House
  local sx, sz = 265.0, 95.0
  local sy = U.ground(sx, sz)
  S.plaza_id = engine.spawn{
    mesh = "cube",
    pos = {sx, sy + 0.15, sz},
    yaw = 1.08,
    size = {55.0, 0.3, 42.0},
    color = stone_plaza,
    tag = "sidewalk",
    body = "static",
  }

  -- 2. Brinkkalan talo with Joulurauha (Christmas Peace) Proclamation Balcony
  local bx, bz = 282.9, 117.7
  local by = U.ground(bx, bz)
  S.brinkkala_id = engine.spawn{
    mesh = "brinkkala_facade",
    pos = {bx, by, bz},
    yaw = 1.084 + math.pi,
    tag = "building",
    body = "static",
  }

  -- Historic Old Great Square street lanterns
  local lanterns = {
    {250.0, 78.0}, {278.0, 82.0}, {252.0, 112.0}
  }
  for _, lp in ipairs(lanterns) do
    engine.spawn{
      mesh = "lamp",
      pos = {lp[1], U.ground(lp[1], lp[2]), lp[2]},
      tag = "lamp",
    }
  end

  -- 3. Turun Tuomiokirkko (Cathedral), on the map data's footprint: the
  -- tower at the west end over the square, the choir to the east.
  local kx, kz = 450.8, -105.5
  S.cathedral_id = engine.spawn{
    mesh = "tuomiokirkko_cathedral",
    pos = {kx, U.ground(kx, kz), kz},
    yaw = -0.055,
    tag = "landmark",
    body = "static",
  }

  -- The terrace and steps on Tuomiokirkkotori, west of the tower
  local cx, cz = 424.0, -100.0
  local cy = U.ground(cx, cz)

  -- Tuomiokirkontori paved cathedral terrace
  engine.spawn{
    mesh = "cube",
    pos = {cx - 24.0, cy + 0.1, cz},
    yaw = 1.52,
    size = {42.0, 0.25, 38.0},
    color = stone_plaza,
    tag = "sidewalk",
    body = "static",
  }

  -- Monumental Tuomiokirkon portaat (Granite Cathedral Steps descending towards the river)
  local step_x, step_z = cx - 44.0, cz
  local step_yaw = 1.52
  for i = 1, 5 do
    local offset = (i - 1) * 2.2
    local drop = (5 - i) * 0.35
    engine.spawn{
      mesh = "cube",
      pos = {step_x - offset * math.cos(step_yaw), cy + drop, step_z - offset * math.sin(step_yaw)},
      yaw = step_yaw,
      size = {2.2, 0.4, 28.0},
      color = granite_steps,
      tag = "sidewalk",
      body = "static",
    }
  end

  -- 4. Henrik Gabriel Porthan Monument in Porthaninpuisto
  local px, pz = 315.0, -45.0
  local py = U.ground(px, pz)
  S.porthan_id = engine.spawn{
    mesh = "porthan_monument",
    pos = {px, py, pz},
    yaw = -1.5,
    tag = "prop",
    body = "static",
  }

  -- Porthaninpuisto park benches & leafy trees
  for _, offset in ipairs{{-6, 0}, {6, 0}, {0, -6}, {0, 6}} do
    local tx, tz = px + offset[1], pz + offset[2]
    engine.spawn{
      mesh = "willow_tree",
      pos = {tx, U.ground(tx, tz), tz},
      tag = "tree",
    }
  end
  local roadnet = require "lib.roadnet"
  for _, bx_off in ipairs{{-4, 4}, {4, 4}} do
    local bx, bz = px + bx_off[1], pz + bx_off[2]
    if not roadnet.on_carriageway(bx, bz, 1) then engine.spawn{
      mesh = "park_bench",
      pos = {bx, U.ground(bx, bz), bz},
      yaw = 0.5,
      tag = "prop",
    } end
  end

  -- 5. Tuomiokirkon grilli (Iconic Turku late-night food kiosk)
  local gx, gz = 331.9, -37.4
  local gy = U.ground(gx, gz)
  engine.spawn{
    mesh = "cube",
    pos = {gx, gy + 1.6, gz},
    yaw = 0.98,
    size = {6.0, 3.2, 4.5},
    color = {0.85, 0.25, 0.20},
    tag = "building",
    body = "static",
  }
  -- Grilli counter window & illuminated roof sign
  engine.spawn{
    mesh = "cube",
    pos = {gx, gy + 3.4, gz},
    size = {5.4, 0.4, 4.0},
    color = {0.96, 0.90, 0.25},
    emissive = 0.6,
    tag = "roof",
    body = "static",
  }
end

return S
