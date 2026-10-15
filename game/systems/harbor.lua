-- Turku Harbor & Turun linna (Castle) 500m visual slice.
-- Spawns the authentic medieval castle keep, outer bailey walls, S/S Bore museum ship,
-- quayside portal cranes, and container terminal stacks.
local U = require "lib.util"

local H = {
  castle_id = nil,
  bore_id = nil,
  cranes = {},
  containers = {},
}

function H.build(map)
  if not map or (map.id ~= "turku" and map.name ~= "Turku") then return end

  -- 1. Turun linna (Turku Castle) Main Keep & Outer Bailey
  -- Coordinates align with Linnankatu / Vallihaudankatu
  local cx, cz, cyaw = -2140, 1720, -0.65
  local gy = U.ground(cx, cz)
  H.castle_id = engine.spawn{
    mesh = "turun_linna",
    pos = {cx, gy, cz},
    yaw = cyaw,
    tag = "building",
    body = "static",
  }

  -- Outer bailey defensive curtain walls (esilinna courtyard)
  local stone = {0.70, 0.68, 0.65}
  local wall_pts = {
    {-2115, 1690}, {-2090, 1735}, {-2120, 1775}, {-2165, 1745}, {-2155, 1705}
  }
  for i = 1, #wall_pts do
    local p0 = wall_pts[i]
    local p1 = wall_pts[i % #wall_pts + 1]
    local mx, mz = (p0[1] + p1[1]) / 2, (p0[2] + p1[2]) / 2
    local wy = U.ground(mx, mz)
    local len = U.dist2d(p0[1], p0[2], p1[1], p1[2])
    local yaw = math.atan(p1[1] - p0[1], p1[2] - p0[2])
    engine.spawn{
      mesh = "cube",
      pos = {mx, wy + 2.5, mz},
      yaw = yaw,
      size = {1.8, 5.0, len * 1.02},
      color = stone,
      tag = "wall",
      body = "static",
    }
  end

  -- Historic Linnanpuisto park buildings (Suomusjärven aitta, Perniön tupa)
  local wood_ochre = {0.85, 0.72, 0.35}
  engine.spawn{
    mesh = "cube",
    pos = {-2320, U.ground(-2320, 1857) + 1.8, 1857},
    yaw = -0.6,
    size = {6.5, 3.6, 5.2},
    color = wood_ochre,
    tag = "building",
    body = "static",
  }
  engine.spawn{
    mesh = "cube",
    pos = {-2231, U.ground(-2231, 1871) + 2.0, 1871},
    yaw = -0.5,
    size = {9.0, 4.0, 8.2},
    color = {0.68, 0.25, 0.20}, -- Falun red
    tag = "building",
    body = "static",
  }

  -- 2. S/S Bore museum ship at Forum Marinum quayside
  -- Moored along Linnankatu river quayside
  local bx, bz, byaw = -1998, 1825, -0.65
  H.bore_id = engine.spawn{
    mesh = "ss_bore",
    pos = {bx, 0.2, bz},
    yaw = byaw,
    tag = "ship",
    body = "static",
  }

  -- 3. Port of Turku quayside container portal cranes
  local crane_spots = {
    {-2415, 1915, -0.68},
    {-2510, 1975, -0.68},
  }
  for _, cs in ipairs(crane_spots) do
    local cid = engine.spawn{
      mesh = "port_crane",
      pos = {cs[1], U.ground(cs[1], cs[2]), cs[2]},
      yaw = cs[3],
      tag = "landmark",
      body = "static",
    }
    H.cranes[#H.cranes + 1] = cid
  end

  -- 4. Intermodal container stacks along Satamakatu container terminal berths
  local container_spots = {
    {-2380, 1880, -0.68},
    {-2400, 1895, -0.68},
    {-2440, 1920, -0.68},
    {-2460, 1935, -0.68},
    {-2475, 1900, 0.85},
    {-2495, 1915, 0.85},
  }
  for _, cpos in ipairs(container_spots) do
    local stid = engine.spawn{
      mesh = "container_stack",
      pos = {cpos[1], U.ground(cpos[1], cpos[2]), cpos[2]},
      yaw = cpos[3],
      tag = "wall",
      body = "static",
    }
    H.containers[#H.containers + 1] = stid
  end
end

return H
